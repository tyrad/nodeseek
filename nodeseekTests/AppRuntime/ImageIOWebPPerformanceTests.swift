import Darwin
import ImageIO
import UIKit
import XCTest

/// 仅用于测量的播放原型，不接入业务图片加载或缓存。
final class ImageIOWebPPerformanceTests: XCTestCase {
    @MainActor
    func testDecodeCostAndVisiblePlayback() async throws {
        try await runBenchmark(
            modes: [.predecoded640, .system640, .buffered640, .buffered320], counts: [1, 4], measureDecode: true
        )
    }

    @MainActor
    func testParallelPlaybackForFourImages() async throws {
        try await runBenchmark(modes: [.parallel640, .parallel320], counts: [4], measureDecode: false)
    }

    @MainActor
    private func runBenchmark(modes: [WebPPlaybackMode], counts: [Int], measureDecode: Bool) async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "post-881951-animated", withExtension: "webp"))
        let data = try Data(contentsOf: url)
        let decodeResults = try await Task.detached(priority: .userInitiated) {
            guard measureDecode else { return [WebPDecodeMeasurement]() }
            return try [640, 320].map { try WebPDecodeMeasurement.measure(data: data, side: $0) }
        }.value
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .normal + 1
        defer {
            window.isHidden = true
            previousWindow?.makeKey()
        }

        var playbackResults: [WebPPlaybackMeasurement] = []
        for count in counts {
            for mode in modes {
                let harness = WebPPlaybackHarness(data: data, mode: mode, playerCount: count)
                window.rootViewController = harness
                window.makeKeyAndVisible()
                try await harness.prepare()
                let result = await harness.run(seconds: 9)
                playbackResults.append(result)
                XCTAssertGreaterThan(result.displayIntervalsMS.count, 30)
                XCTAssertEqual(result.animationEvents.count, count)
                // 这里只断言采样有效，缺帧和超时保留在报告中，不用波动的性能阈值制造不稳定测试。
                XCTAssertTrue(result.animationEvents.allSatisfy { !$0.isEmpty }, "每个播放器都应采集到实际帧更新")
                XCTAssertTrue(result.statuses.allSatisfy { $0 == 0 })
                XCTAssertLessThanOrEqual(result.maxBufferedFrames, 6 * count)
                // 截图在计时结束后生成，避免 PNG 编码污染播放测量。
                let screenshot = UIGraphicsImageRenderer(bounds: harness.view.bounds).image { _ in
                    harness.view.drawHierarchy(in: harness.view.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: screenshot)
                attachment.name = "WebP-\(mode.rawValue)-\(count)-players"
                attachment.lifetime = .keepAlways
                add(attachment)
                window.rootViewController = nil
                try await Task.sleep(nanoseconds: 300_000_000)
            }
        }
        let report = WebPPerformanceReport(
            environment: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion), \(ProcessInfo.processInfo.operatingSystemVersionString)",
            decode: decodeResults,
            playback: playbackResults
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let attachment = XCTAttachment(data: try encoder.encode(report), uniformTypeIdentifier: "public.json")
        attachment.name = "ImageIO-WebP-performance.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private struct WebPPerformanceReport: Codable {
    let environment: String
    let decode: [WebPDecodeMeasurement]
    let playback: [WebPPlaybackMeasurement]
}

private struct WebPDecodeMeasurement: Codable {
    let side: Int
    let sourceCreationMS: [Double]
    let decodeAndRasterMS: [Double]
    let frameBytes: Int

    static func measure(data: Data, side: Int) throws -> Self {
        var sourceTimes: [Double] = []
        var frameTimes: [Double] = []
        var frameBytes = 0
        // 每轮新建 source；不做哈希、PNG 编码或网络请求。
        for _ in 0 ..< 3 {
            let start = CACurrentMediaTime()
            let source = try WebPProbeDecoder.source(data)
            sourceTimes.append((CACurrentMediaTime() - start) * 1_000)
            for index in 0 ..< 25 {
                try autoreleasepool {
                    let start = CACurrentMediaTime()
                    let frame = try WebPProbeDecoder.frame(source, index: index, side: side)
                    frameTimes.append((CACurrentMediaTime() - start) * 1_000)
                    frameBytes = frame.bytesPerRow * frame.height
                }
            }
        }
        return Self(side: side, sourceCreationMS: sourceTimes, decodeAndRasterMS: frameTimes, frameBytes: frameBytes)
    }
}

private enum WebPProbeDecoder {
    static func source(_ data: Data) throws -> CGImageSource {
        try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary))
    }

    static func frame(_ source: CGImageSource, index: Int, side: Int) throws -> CGImage {
        let image: CGImage
        if side == 640 {
            image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, index, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary))
        } else {
            image = try XCTUnwrap(CGImageSourceCreateThumbnailAtIndex(source, index, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: side,
                kCGImageSourceShouldCacheImmediately: true,
            ] as CFDictionary))
        }
        // 强制栅格化，避免把延迟解码的成本留给后续界面显示。
        let context = try XCTUnwrap(CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return try XCTUnwrap(context.makeImage())
    }
}

private enum WebPPlaybackMode: String, CaseIterable, Codable {
    case predecoded640
    case system640
    case buffered640
    case buffered320
    case parallel640
    case parallel320

    var side: Int { self == .buffered320 || self == .parallel320 ? 320 : 640 }
    var usesBuffer: Bool { self != .predecoded640 && self != .system640 }
    var usesParallelQueue: Bool { self == .parallel640 || self == .parallel320 }
}

private struct WebPFrameEvent: Codable {
    let index: Int
    let timeMS: Double
}

private struct WebPPlaybackMeasurement: Codable {
    let mode: WebPPlaybackMode
    let playerCount: Int
    let durationSeconds: Double
    let preparationMS: Double
    let displayIntervalsMS: [Double]
    let animationEvents: [[WebPFrameEvent]]
    let skippedAnimationFrames: [Int]
    let unavailableFrameTicks: Int
    let statuses: [Int32]
    let residentSamplesMiB: [Double]
    let maxBufferedFrames: Int
}

/// source 只在串行后台队列使用；锁保护六帧窗口及取消状态。
private final class WebPFrameBuffer: @unchecked Sendable {
    private let source: CGImageSource
    private let side: Int
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var frames: [Int: CGImage] = [:]
    private var desiredSequence = 0
    private var isDecoding = false
    private var isActive = true
    private var failure: Error?
    private var peak = 0

    init(data: Data, side: Int, queue: DispatchQueue) throws {
        source = try WebPProbeDecoder.source(data)
        self.side = side
        self.queue = queue
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return frames.count
    }

    var peakCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return peak
    }

    func frame(for sequence: Int) throws -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        if let failure { throw failure }
        desiredSequence = sequence
        frames = frames.filter { $0.key >= sequence && $0.key < sequence + 6 }
        if !isDecoding && isActive {
            isDecoding = true
            queue.async { self.fill() }
        }
        return frames[sequence]
    }

    func stop() {
        lock.lock()
        isActive = false
        frames.removeAll()
        lock.unlock()
    }

    private func fill() {
        while true {
            lock.lock()
            guard isActive, failure == nil,
                  let sequence = (desiredSequence ..< desiredSequence + 6).first(where: { frames[$0] == nil }) else {
                isDecoding = false
                lock.unlock()
                return
            }
            lock.unlock()
            do {
                let image = try autoreleasepool { try WebPProbeDecoder.frame(source, index: sequence % 25, side: side) }
                lock.lock()
                if isActive && sequence >= desiredSequence && sequence < desiredSequence + 6 {
                    frames[sequence] = image
                    peak = max(peak, frames.count)
                }
                lock.unlock()
            } catch {
                lock.lock()
                failure = error
                isDecoding = false
                lock.unlock()
                return
            }
        }
    }
}

@MainActor
private final class WebPPlaybackHarness: UIViewController {
    private let data: Data
    private let mode: WebPPlaybackMode
    private let playerCount: Int
    private let scrollView = UIScrollView()
    private var imageViews: [UIImageView] = []
    private var buffers: [WebPFrameBuffer] = []
    private var predecoded: [CGImage] = []
    private var link: CADisplayLink?
    private var isRunning = false
    private var startTime = 0.0
    private var previousTick: Double?
    private var displayIntervals: [Double] = []
    private var events: [[WebPFrameEvent]]
    private var lastSequences: [Int]
    private var skipped: [Int]
    private var unavailableTicks = 0
    private var statuses: [Int32] = []
    private var residentSamples: [Double] = []
    private var preparationMS = 0.0

    init(data: Data, mode: WebPPlaybackMode, playerCount: Int) {
        self.data = data
        self.mode = mode
        self.playerCount = playerCount
        events = Array(repeating: [], count: playerCount)
        lastSequences = Array(repeating: -1, count: playerCount)
        skipped = Array(repeating: 0, count: playerCount)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scrollView)
        let title = UILabel(frame: CGRect(x: 20, y: 80, width: view.bounds.width - 40, height: 40))
        title.text = "\(mode.rawValue) · \(playerCount) 张 · 60 Hz"
        title.textColor = .label
        scrollView.addSubview(title)
        let side = min((view.bounds.width - 60) / 2, 160)
        for index in 0 ..< playerCount {
            let imageView = UIImageView(frame: CGRect(
                x: 20 + CGFloat(index % 2) * (side + 20),
                y: 140 + CGFloat(index / 2) * (side + 20), width: side, height: side
            ))
            imageView.contentMode = .scaleAspectFit
            scrollView.addSubview(imageView)
            imageViews.append(imageView)
        }
        for index in 0 ..< 20 {
            let label = UILabel(frame: CGRect(x: 20, y: 520 + index * 40, width: Int(view.bounds.width) - 40, height: 32))
            label.text = "滚动响应测量 · 第 \(index + 1) 行"
            label.textColor = .secondaryLabel
            scrollView.addSubview(label)
        }
        scrollView.contentSize = CGSize(width: view.bounds.width, height: 1_400)
    }

    func prepare() async throws {
        loadViewIfNeeded()
        residentSamples.append(Self.residentMiB())
        let start = CACurrentMediaTime()
        if mode == .predecoded640 {
            let data = data
            predecoded = try await Task.detached(priority: .userInitiated) {
                let source = try WebPProbeDecoder.source(data)
                return try (0 ..< 25).map { index in
                    try autoreleasepool { try WebPProbeDecoder.frame(source, index: index, side: 640) }
                }
            }.value
        } else if mode.usesBuffer {
            let queue = DispatchQueue(
                label: "ImageIOWebPPerformance.decode", qos: .userInitiated,
                attributes: mode.usesParallelQueue ? .concurrent : []
            )
            buffers = try (0 ..< playerCount).map { _ in try WebPFrameBuffer(data: data, side: mode.side, queue: queue) }
            for buffer in buffers { _ = try buffer.frame(for: 0) }
            while buffers.contains(where: { $0.count < 6 }) {
                for buffer in buffers { _ = try buffer.frame(for: 0) }
                guard CACurrentMediaTime() - start < 10 else { throw URLError(.timedOut) }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
        }
        preparationMS = (CACurrentMediaTime() - start) * 1_000
    }

    func run(seconds: Double) async -> WebPPlaybackMeasurement {
        isRunning = true
        startTime = CACurrentMediaTime()
        let displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink.preferredFramesPerSecond = 60
        displayLink.add(to: .main, forMode: .common)
        link = displayLink
        if mode == .system640 {
            for player in 0 ..< playerCount {
                statuses.append(CGAnimateImageDataWithBlock(data as CFData, nil) { [weak self] index, image, stop in
                    guard let self, self.isRunning else { stop.pointee = true; return }
                    self.show(image, player: player, index: index)
                })
            }
        }
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        let duration = CACurrentMediaTime() - startTime
        isRunning = false
        displayLink.invalidate()
        link = nil
        let peakFrames = buffers.reduce(0) { $0 + $1.peakCount }
        buffers.forEach { $0.stop() }
        residentSamples.append(Self.residentMiB())
        return WebPPlaybackMeasurement(
            mode: mode, playerCount: playerCount, durationSeconds: duration, preparationMS: preparationMS,
            displayIntervalsMS: displayIntervals, animationEvents: events, skippedAnimationFrames: skipped,
            unavailableFrameTicks: unavailableTicks, statuses: statuses, residentSamplesMiB: residentSamples,
            maxBufferedFrames: peakFrames
        )
    }

    @objc private func tick() {
        let now = CACurrentMediaTime()
        if let previousTick { displayIntervals.append((now - previousTick) * 1_000) }
        previousTick = now
        scrollView.contentOffset.y = 35 + 35 * sin((now - startTime) * 2)
        if displayIntervals.count % 15 == 0 { residentSamples.append(Self.residentMiB()) }
        guard mode != .system640 else { return }
        let sequence = Int((now - startTime) / 0.12)
        for player in 0 ..< playerCount where sequence != lastSequences[player] {
            do {
                let image = mode == .predecoded640 ? predecoded[sequence % 25] : try buffers[player].frame(for: sequence)
                guard let image else { unavailableTicks += 1; continue }
                if lastSequences[player] >= 0 { skipped[player] += max(0, sequence - lastSequences[player] - 1) }
                lastSequences[player] = sequence
                show(image, player: player, index: sequence % 25)
            } catch {
                XCTFail("后台帧解码失败：\(error)")
            }
        }
    }

    private func show(_ image: CGImage, player: Int, index: Int) {
        imageViews[player].image = UIImage(cgImage: image)
        events[player].append(WebPFrameEvent(index: index, timeMS: (CACurrentMediaTime() - startTime) * 1_000))
    }

    private static func residentMiB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : -1
    }
}
