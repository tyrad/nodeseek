import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import FramePlay

@MainActor
final class ManualClock: PlaybackClock {
    var now: TimeInterval = 0
    var onTick: (@MainActor (TimeInterval) -> Void)?
    private(set) var running = false
    func start() { running = true }
    func stop() { running = false }
    func advance(_ interval: TimeInterval) { now += interval; if running { onTick?(now) } }
}

enum TestFixtures {
    static func webP() throws -> Data {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: FixtureBundleToken.self)
        #endif
        let url = try XCTUnwrap(bundle.url(forResource: "animated", withExtension: "webp", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    static func frame(_ red: CGFloat = 1, side: Int = 8) -> CGImage {
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: red, green: 0.2, blue: 0.4, alpha: 0.5)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        return context.makeImage()!
    }

    static func encoded(type: String = "com.compuserve.gif", delays: [Double] = [0.1, 0.2, 0.3], loops: Int? = 0) throws -> Data {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, type as CFString, delays.count, nil))
        let dictionary = type == "public.png" ? kCGImagePropertyPNGDictionary : kCGImagePropertyGIFDictionary
        let delayKey = type == "public.png" ? kCGImagePropertyAPNGDelayTime : kCGImagePropertyGIFDelayTime
        let loopKey = type == "public.png" ? kCGImagePropertyAPNGLoopCount : kCGImagePropertyGIFLoopCount
        if let loops { CGImageDestinationSetProperties(destination, [dictionary: [loopKey: loops]] as CFDictionary) }
        for (index, delay) in delays.enumerated() {
            CGImageDestinationAddImage(destination, frame(CGFloat(index + 1) / 4), [dictionary: [delayKey: delay]] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

private final class FixtureBundleToken: NSObject {}

final class DecodeProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [Int: Int] = [:]
    private var factories = 0
    private var active = 0
    private var peak = 0
    private var usedMain = false
    func created() { lock.lock(); factories += 1; lock.unlock() }
    func begin(_ index: Int) {
        lock.lock()
        counts[index, default: 0] += 1
        active += 1
        peak = max(peak, active)
        usedMain = usedMain || Thread.isMainThread
        lock.unlock()
    }
    func end() { lock.lock(); active -= 1; lock.unlock() }
    var snapshot: (counts: [Int: Int], factories: Int, peak: Int, usedMain: Bool) {
        lock.lock(); defer { lock.unlock() }
        return (counts, factories, peak, usedMain)
    }
}

final class FakeDecoder: FrameDecoding, @unchecked Sendable {
    let metadata: AnimationMetadata
    let frames: [CGImage]
    let probe: DecodeProbe
    let failAt: Set<Int>
    let blockAt: Int?
    let gate: DispatchSemaphore?
    let delay: TimeInterval

    init(durations: [Double] = [0.1, 0.2, 0.3], plays: Int? = nil, frames: [CGImage]? = nil,
         probe: DecodeProbe = DecodeProbe(), failAt: Set<Int> = [], blockAt: Int? = nil,
         gate: DispatchSemaphore? = nil, delay: TimeInterval = 0) {
        self.frames = frames ?? durations.indices.map { TestFixtures.frame(CGFloat($0 + 1) / 4) }
        metadata = AnimationMetadata(pixelWidth: self.frames[0].width, pixelHeight: self.frames[0].height,
                                     frameDurations: durations, totalPlayCount: plays)
        self.probe = probe
        self.failAt = failAt
        self.blockAt = blockAt
        self.gate = gate
        self.delay = delay
    }

    func frame(at index: Int) throws -> CGImage {
        probe.begin(index)
        defer { probe.end() }
        if index == blockAt { _ = gate?.wait(timeout: .now() + 5) }
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        if failAt.contains(index) { throw PlaybackFailure.frameDecodingFailed(index: index) }
        return frames[index]
    }
}

@MainActor
func eventually(timeout: TimeInterval = 4, file: StaticString = #filePath, line: UInt = #line,
                _ condition: @MainActor () -> Bool) async throws {
    let start = ProcessInfo.processInfo.systemUptime
    while !condition() {
        if ProcessInfo.processInfo.systemUptime - start > timeout {
            XCTFail("等待条件超时", file: file, line: line)
            throw PlaybackFailure.bufferTimeout
        }
        try await Task.sleep(nanoseconds: 1_000_000)
    }
}

@MainActor
func environment(_ decoder: FakeDecoder, bytes: Int = 32 * 1_024 * 1_024,
                 poster: CGImage? = nil) -> PlaybackEnvironment {
    PlaybackEnvironment(maximumBufferBytes: bytes, decoderFactory: { _, _ in
        decoder.probe.created()
        return decoder
    }, posterFactory: { _, _ in poster })
}
