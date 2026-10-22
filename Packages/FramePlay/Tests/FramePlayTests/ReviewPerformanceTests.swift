#if canImport(UIKit)
import Darwin
import UIKit
import XCTest
@testable import FramePlay

/// 与普通单测分开，覆盖错峰共享、原尺寸压力及进程资源开销。
@MainActor
final class ReviewPerformanceTests: XCTestCase {
    func testPlaybackResourceMeasurements() async throws {
        guard ProcessInfo.processInfo.environment["FRAMEPLAY_REVIEW_PERFORMANCE"] == "1" else {
            throw XCTSkip("设置 TEST_RUNNER_FRAMEPLAY_REVIEW_PERFORMANCE=1 启用审核性能采样")
        }
        let data = try TestFixtures.webP()
        let staticPoster = try XCTUnwrap(ImageIODecoder.poster(data: data, configuration: PlaybackConfiguration(maximumPixelSize: 320)))
        var reports: [ReviewReport] = []
        let scenarios: [(String, Int, Int, Bool, Bool, Int)] = [
            ("static-baseline", 0, 320, false, false, 6),
            ("single-320", 1, 320, false, false, 6),
            ("independent-320", 4, 320, false, false, 6),
            ("shared-aligned-320", 4, 320, true, false, 6),
            ("shared-staggered-320", 4, 320, true, true, 6),
            ("shared-staggered-default-512", 4, 512, true, true, 6),
            ("independent-default-512", 4, 512, false, false, 6),
            ("independent-640", 4, 640, false, false, 6),
            ("single-320-full-buffer", 1, 320, false, false, 25),
            ("shared-staggered-320-full-buffer", 4, 320, true, true, 25),
        ]
        let selected = ProcessInfo.processInfo.environment["FRAMEPLAY_REVIEW_SCENARIO"]
        let byteBudgetMiB = ProcessInfo.processInfo.environment["FRAMEPLAY_REVIEW_BUFFER_MIB"].flatMap(Int.init)
        for (name, count, pixels, shared, staggered, bufferedFrames) in scenarios {
            if let selected, name != selected { continue }
            let probe = ReviewDecodeProbe()
            let environment = PlaybackEnvironment(decoderFactory: { data, config in
                ReviewMeasuredDecoder(base: try ImageIODecoder(data: data, configuration: config), probe: probe)
            }, posterFactory: { ImageIODecoder.poster(data: $0, configuration: $1) })
            let window = makeTestWindow()
            guard window.windowScene != nil else { throw XCTSkip("需要独立 iOS 宿主的真实窗口") }
            let root = window.rootViewController!.view!
            let scroll = UIScrollView(frame: root.bounds)
            scroll.contentSize = CGSize(width: scroll.bounds.width, height: scroll.bounds.height + 100)
            root.addSubview(scroll)
            window.makeKeyAndVisible()
            let sampler = ReviewSampler(count: count, scroll: scroll, environment: environment)
            let source = AnimatedImageSource(data: data)
            let bufferBytes = (byteBudgetMiB ?? (bufferedFrames > 6 ? 12 : 8)) * 1_024 * 1_024
            var players: [AnimatedImagePlayer] = []
            var fallbacks: [String] = []
            defer {
                sampler.stop()
                players.forEach { $0.reset() }
                window.isHidden = true
                window.rootViewController = nil
            }
            let beforePreparation = ReviewProcessSnapshot.read()
            for index in 0 ..< max(4, count) {
                let view = UIImageView(frame: CGRect(x: 20 + (index % 2) * 175,
                                                      y: 100 + (index / 2) * 175, width: 160, height: 160))
                view.contentMode = .scaleAspectFit
                scroll.addSubview(view)
                guard index < count else {
                    if count == 0 { view.image = UIImage(cgImage: staticPoster) }
                    continue
                }
                let player = AnimatedImagePlayer(environment: environment)
                player.onFrame = { [weak player, weak view] image in
                    view?.image = image.map { UIImage(cgImage: $0) }
                    if let frame = player?.currentFrameIndex, image != nil { sampler.record(player: index, frame: frame) }
                }
                player.onFallback = { fallbacks.append(String(describing: $0)) }
                players.append(player)
                player.load(shared ? source : AnimatedImageSource(data: data),
                            configuration: PlaybackConfiguration(maximumPixelSize: pixels,
                                                                 bufferBytes: bufferBytes,
                                                                 maximumBufferedFrames: bufferedFrames))
                if staggered { try await Task.sleep(nanoseconds: 350_000_000) }
            }
            try await eventually(timeout: 10) { players.allSatisfy { $0.state != .loading } }
            sampler.start()
            let before = ReviewProcessSnapshot.read()
            let wallStart = ProcessInfo.processInfo.systemUptime
            try await Task.sleep(nanoseconds: 9_000_000_000)
            let wallSeconds = ProcessInfo.processInfo.systemUptime - wallStart
            let after = ReviewProcessSnapshot.read()
            sampler.stop()
            let decoder = probe.snapshot
            let cacheBytes = sampler.peakCacheBytes
            let resources = environment.statistics.resourceCount
            let states = players.map { String(describing: $0.state) }
            XCTAssertTrue(fallbacks.isEmpty, name)
            XCTAssertTrue(players.allSatisfy { $0.state == .playing }, name)
            XCTAssertLessThanOrEqual(cacheBytes, 32 * 1_024 * 1_024)
            let screenshot = XCTAttachment(image: UIGraphicsImageRenderer(bounds: root.bounds).image { _ in
                XCTAssertTrue(root.drawHierarchy(in: root.bounds, afterScreenUpdates: true))
            })
            screenshot.name = "review-\(name)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            players.forEach { $0.reset() }
            XCTAssertEqual(environment.statistics.resourceCount, 0)
            XCTAssertEqual(environment.statistics.bufferedBytes, 0)
            try await eventually { environment.statistics.pendingOperations == 0 }
            let idleBefore = ReviewProcessSnapshot.read()
            try await Task.sleep(nanoseconds: 1_000_000_000)
            let idleAfter = ReviewProcessSnapshot.read()
            reports.append(ReviewReport(
                scenario: name, bufferBytes: bufferBytes, wallSeconds: wallSeconds,
                cpuPercentOfOneCore: (after.cpuSeconds - before.cpuSeconds) / wallSeconds * 100,
                idleCPUSeconds: idleAfter.cpuSeconds - idleBefore.cpuSeconds,
                residentBeforePreparation: beforePreparation.residentBytes, residentBeforeSampling: before.residentBytes,
                peakResidentBytes: sampler.peakResidentBytes, residentAfterReset: idleAfter.residentBytes,
                peakCacheBytes: cacheBytes, resourceCount: resources, decodeMS: decoder,
                displayIntervalsMS: sampler.intervals, events: sampler.events, finalStates: states, fallbacks: fallbacks
            ))
            print("FRAMEPLAY_REVIEW \(name) cpu=\(reports.last!.cpuPercentOfOneCore)% rss=\(sampler.peakResidentBytes) decodes=\(decoder.count)")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let attachment = XCTAttachment(data: try encoder.encode(reports), uniformTypeIdentifier: "public.json")
        attachment.name = "FramePlay-review-performance.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private struct ReviewReport: Codable {
    let scenario: String
    let bufferBytes: Int
    let wallSeconds: Double
    let cpuPercentOfOneCore: Double
    let idleCPUSeconds: Double
    let residentBeforePreparation: UInt64
    let residentBeforeSampling: UInt64
    let peakResidentBytes: UInt64
    let residentAfterReset: UInt64
    let peakCacheBytes: Int
    let resourceCount: Int
    let decodeMS: [Double]
    let displayIntervalsMS: [Double]
    let events: [[ReviewEvent]]
    let finalStates: [String]
    let fallbacks: [String]
}

private struct ReviewEvent: Codable { let frame: Int; let timeMS: Double }

private struct ReviewProcessSnapshot {
    let cpuSeconds: Double
    let residentBytes: UInt64
    static func read() -> Self {
        var usage = rusage()
        precondition(getrusage(RUSAGE_SELF, &usage) == 0)
        let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        var info = mach_task_basic_info()
        var size = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &size)
            }
        }
        precondition(status == KERN_SUCCESS)
        return Self(cpuSeconds: cpu, residentBytes: info.resident_size)
    }
}

private final class ReviewDecodeProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var milliseconds: [Double] = []
    func record(_ value: Double) { lock.lock(); milliseconds.append(value); lock.unlock() }
    var snapshot: [Double] { lock.lock(); defer { lock.unlock() }; return milliseconds }
}

private final class ReviewMeasuredDecoder: FrameDecoding, @unchecked Sendable {
    let base: ImageIODecoder
    let probe: ReviewDecodeProbe
    var metadata: AnimationMetadata { base.metadata }
    init(base: ImageIODecoder, probe: ReviewDecodeProbe) { self.base = base; self.probe = probe }
    func frame(at index: Int) throws -> CGImage {
        let start = ProcessInfo.processInfo.systemUptime
        defer { probe.record((ProcessInfo.processInfo.systemUptime - start) * 1_000) }
        return try base.frame(at: index)
    }
}

@MainActor
private final class ReviewSampler: NSObject {
    let scroll: UIScrollView
    let environment: PlaybackEnvironment
    private var link: CADisplayLink?
    private var started: Double?
    private var last: Double?
    private(set) var intervals: [Double] = []
    private(set) var events: [[ReviewEvent]]
    private(set) var peakResidentBytes: UInt64 = 0
    private(set) var peakCacheBytes = 0
    init(count: Int, scroll: UIScrollView, environment: PlaybackEnvironment) {
        self.scroll = scroll; self.environment = environment
        events = Array(repeating: [], count: count)
    }
    func start() {
        started = ProcessInfo.processInfo.systemUptime
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFramesPerSecond = 60
        link.add(to: .main, forMode: .common)
        self.link = link
    }
    func stop() { link?.invalidate(); link = nil }
    func record(player: Int, frame: Int) {
        guard let started else { return }
        events[player].append(ReviewEvent(frame: frame, timeMS: (ProcessInfo.processInfo.systemUptime - started) * 1_000))
    }
    @objc private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        if let last { intervals.append((now - last) * 1_000) }
        last = now
        peakResidentBytes = max(peakResidentBytes, ReviewProcessSnapshot.read().residentBytes)
        peakCacheBytes = max(peakCacheBytes, environment.statistics.bufferedBytes)
        scroll.contentOffset.y = 30 + 30 * sin((now - (started ?? now)) * 2)
    }
}
#endif
