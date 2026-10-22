#if canImport(UIKit)
import UIKit
import XCTest
@testable import FramePlay

@MainActor
final class PerformanceTests: XCTestCase {
    func testRealWebPPlaybackMeasurements() async throws {
        guard ProcessInfo.processInfo.environment["FRAMEPLAY_PERFORMANCE"] == "1" else {
            throw XCTSkip("设置 TEST_RUNNER_FRAMEPLAY_PERFORMANCE=1 后运行独立性能采样")
        }
        let data = try TestFixtures.webP()
        var reports: [PlaybackSample] = []
        // 末场再次测单图，区分首次显示场景与稳定运行阶段的波动。
        for (run, scenario) in [(1, false), (4, false), (4, true), (1, false)].enumerated() {
            let (count, shared) = scenario
            let env = PlaybackEnvironment(maximumConcurrentDecodes: 2)
            let window = makeTestWindow()
            guard window.windowScene != nil else {
                throw XCTSkip("需要 Examples/iOSHarness 的真实 UIWindowScene 才能测界面渲染")
            }
            let scroll = UIScrollView(frame: window.rootViewController!.view.bounds)
            scroll.contentSize = CGSize(width: scroll.bounds.width, height: scroll.bounds.height + 100)
            window.rootViewController!.view.addSubview(scroll)
            window.makeKeyAndVisible()
            let sample = PlaybackSampler(count: count, scrollView: scroll, environment: env)
            let source = AnimatedImageSource(data: data)
            var players: [AnimatedImagePlayer] = []
            let started = ProcessInfo.processInfo.systemUptime
            for index in 0 ..< count {
                let view = UIImageView(frame: CGRect(x: 20 + (index % 2) * 175, y: 100 + (index / 2) * 175, width: 160, height: 160))
                view.contentMode = .scaleAspectFit
                scroll.addSubview(view)
                let player = AnimatedImagePlayer(environment: env)
                player.onFrame = { [weak player, weak view] frame in
                    view?.image = frame.map { UIImage(cgImage: $0) }
                    if let frameIndex = player?.currentFrameIndex, frame != nil { sample.record(player: index, frame: frameIndex) }
                }
                players.append(player)
                player.load(shared ? source : AnimatedImageSource(data: data),
                            configuration: PlaybackConfiguration(maximumPixelSize: 320))
            }
            defer {
                players.forEach { $0.reset() }
                window.isHidden = true
                window.rootViewController = nil
            }
            try await eventually(timeout: 10) { players.allSatisfy { $0.state == .playing } }
            let preparation = (ProcessInfo.processInfo.systemUptime - started) * 1_000
            sample.start()
            try await Task.sleep(nanoseconds: 9_000_000_000)
            sample.stop()
            XCTAssertTrue(players.allSatisfy { $0.state == .playing })
            XCTAssertTrue(sample.events.allSatisfy { $0.count > 1 })
            XCTAssertLessThanOrEqual(sample.peakBytes, 32 * 1_024 * 1_024)
            reports.append(PlaybackSample(
                run: run, players: count, sharedSource: shared, preparationMS: preparation,
                intervalsMS: sample.intervals, events: sample.events, peakCacheBytes: sample.peakBytes,
                resourceCount: env.statistics.resourceCount
            ))
            let root = window.rootViewController!.view!
            var rendered = false
            let image = UIGraphicsImageRenderer(bounds: root.bounds).image { _ in
                rendered = root.drawHierarchy(in: root.bounds, afterScreenUpdates: true)
            }
            XCTAssertTrue(rendered, "截图必须来自真实可绘制的窗口")
            XCTAssertGreaterThan(distinctColors(in: image), 8, "截图不应只有空白背景")
            let screenshot = XCTAttachment(image: image)
            screenshot.name = "FramePlay-\(count)-shared-\(shared)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let attachment = XCTAttachment(data: try encoder.encode(reports), uniformTypeIdentifier: "public.json")
        attachment.name = "FramePlay-performance.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func distinctColors(in image: UIImage) -> Int {
        guard let cgImage = image.cgImage,
              let context = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8,
                                      bytesPerRow: 128, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 32, height: 32))
        guard let bytes = context.data?.assumingMemoryBound(to: UInt32.self) else { return 0 }
        return Set(UnsafeBufferPointer(start: bytes, count: 1_024)).count
    }
}

private struct PlaybackSample: Codable {
    let run: Int
    let players: Int
    let sharedSource: Bool
    let preparationMS: Double
    let intervalsMS: [Double]
    let events: [[SampleEvent]]
    let peakCacheBytes: Int
    let resourceCount: Int
}

private struct SampleEvent: Codable {
    let frame: Int
    let timeMS: Double
}

@MainActor
private final class PlaybackSampler: NSObject {
    private let scrollView: UIScrollView
    private let environment: PlaybackEnvironment
    private var link: CADisplayLink?
    private var started: Double?
    private var lastTick: Double?
    private(set) var intervals: [Double] = []
    private(set) var events: [[SampleEvent]]
    private(set) var peakBytes = 0

    init(count: Int, scrollView: UIScrollView, environment: PlaybackEnvironment) {
        events = Array(repeating: [], count: count)
        self.scrollView = scrollView
        self.environment = environment
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
        events[player].append(SampleEvent(frame: frame, timeMS: (ProcessInfo.processInfo.systemUptime - started) * 1_000))
    }

    @objc private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        if let lastTick { intervals.append((now - lastTick) * 1_000) }
        lastTick = now
        peakBytes = max(peakBytes, environment.statistics.bufferedBytes)
        scrollView.contentOffset.y = 30 + 30 * sin((now - (started ?? now)) * 2)
    }
}
#endif
