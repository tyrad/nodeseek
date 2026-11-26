import CryptoKit
import Darwin
import FramePlay
import UIKit
import XCTest
@testable import nodeseek

enum DetailWebPTestFixture {
    static func url(name: String = "post-881951-animated") throws -> URL {
        try XCTUnwrap(Bundle(for: DetailAnimatedImageIntegrationTests.self).url(forResource: name, withExtension: "webp"))
    }
    static func data(name: String = "post-881951-animated") throws -> Data { try Data(contentsOf: url(name: name)) }
}

@MainActor
final class DetailAnimatedImageIntegrationTests: XCTestCase {
    func testBindingSharesFramesPausesAndFallsBackWithoutAffectingOtherSource() async throws {
        let window = try makeWindow()
        defer { window.isHidden = true; window.rootViewController = nil }
        let firstView = UIImageView(frame: CGRect(x: 0, y: 0, width: 160, height: 160))
        let secondView = UIImageView(frame: firstView.frame.offsetBy(dx: 170, dy: 0))
        window.rootViewController!.view.addSubview(firstView)
        window.rootViewController!.view.addSubview(secondView)
        let environment = PlaybackEnvironment()
        let first = DetailAnimatedImageBinding(imageView: firstView, environment: environment)
        let second = DetailAnimatedImageBinding(imageView: secondView, environment: environment)
        defer { first.reset(); second.reset() }
        let data = try DetailWebPTestFixture.data()
        let asset = DetailAnimatedImageAsset(data: data)
        let poster = try XCTUnwrap(ImageRenderer.downsampledImage(data: data, maxPixelSize: 160))
        first.load(asset, poster: poster, maximumPixelSize: 160)
        second.load(asset, poster: poster, maximumPixelSize: 160)
        try await waitFor { first.state == .ready && second.state == .ready }
        XCTAssertEqual(environment.statistics.resourceCount, 1)
        first.setVisible(true)
        second.setVisible(true)
        try await waitFor { first.isPlaying && second.isPlaying }
        let initial = digest(firstView.image)
        try await waitFor { self.digest(firstView.image) != initial }
        first.setVisible(false)
        let paused = digest(firstView.image)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(digest(firstView.image), paused)
        XCTAssertTrue(second.isPlaying)
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertFalse(second.isPlaying)
        // 进入前台时恢复可见范围，模拟完整的系统通知顺序。
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertFalse(first.isPlaying)
        XCTAssertTrue(second.isPlaying)
        first.load(DetailAnimatedImageAsset(data: Data([1])), poster: poster, maximumPixelSize: 160)
        try await waitFor { first.state == .staticFallback(.invalidImageData) }
        XCTAssertNotNil(firstView.image)
        XCTAssertTrue(second.isPlaying)
        first.reset()
        second.reset()
        XCTAssertEqual(environment.statistics.resourceCount, 0)
        XCTAssertEqual(environment.statistics.bufferedBytes, 0)
    }

    func testInlineWebPLoadsOriginalSizeOnceAndRestartsAfterRemoval() async throws {
        let window = try makeWindow()
        defer { window.isHidden = true; window.rootViewController = nil }
        var sizes: [CGSize] = []
        let imageView = DetailInlineImageView(
            frame: CGRect(x: 0, y: 80, width: 160, height: 160), imageURL: try DetailWebPTestFixture.url(),
            targetPixelWidth: 160, displayScale: 1, allowsInlineAnimation: false,
            usesDetailImageOptimization: true, longImageLayoutWidth: 160,
            onImageLoaded: { _, size in sizes.append(size) }, onImageTapped: { _ in }
        )
        imageView.setPlaybackVisible(true)
        window.rootViewController!.view.addSubview(imageView)
        try await waitFor { imageView.isPlayingWebP }
        XCTAssertEqual(sizes, [CGSize(width: 640, height: 640)])
        let initial = digest(imageView.image)
        try await waitFor { self.digest(imageView.image) != initial }
        imageView.setNeedsLayout()
        imageView.layoutIfNeeded()
        XCTAssertEqual(sizes.count, 1, "切帧和普通布局不能重复通知图片尺寸")
        imageView.removeFromSuperview()
        XCTAssertFalse(imageView.isPlayingWebP)
        window.rootViewController!.view.addSubview(imageView)
        try await waitFor { imageView.isPlayingWebP && sizes.count == 2 }
        imageView.removeFromSuperview()
    }

    func testBlockWebPDoesNotRestorePosterDuringLayoutAndObeysVisibility() async throws {
        let window = try makeWindow()
        defer { window.isHidden = true; window.rootViewController = nil }
        var sizes: [CGSize] = []
        let block = DetailImageBlockView(
            imageBlock: RenderedImageBlock(url: try DetailWebPTestFixture.url(), altText: nil), imageKind: .normal,
            onImageLoaded: { size, _ in sizes.append(size) }, onImageTapped: {}
        )
        block.frame = CGRect(x: 0, y: 80, width: 160, height: 160)
        window.rootViewController!.view.addSubview(block)
        block.setPlaybackVisible(true)
        block.setNeedsLayout()
        block.layoutIfNeeded()
        try await waitFor { block.isPlayingWebP }
        let imageView = try XCTUnwrap(block.subviews.compactMap { $0 as? UIImageView }.first)
        let initial = digest(imageView.image)
        try await waitFor { self.digest(imageView.image) != initial }
        let current = imageView.image?.cgImage
        block.setNeedsLayout()
        block.layoutIfNeeded()
        XCTAssertTrue(imageView.image?.cgImage === current)
        XCTAssertEqual(sizes, [CGSize(width: 640, height: 640)])
        block.setPlaybackVisible(false)
        XCTAssertFalse(block.isPlayingWebP)
        block.setPlaybackVisible(true)
        XCTAssertTrue(block.isPlayingWebP)
        block.frame.size.height = 20
        block.setNeedsLayout()
        block.layoutIfNeeded()
        XCTAssertTrue(imageView.isHidden)
        XCTAssertFalse(block.isPlayingWebP)
        block.removeFromSuperview()
        XCTAssertFalse(block.isPlayingWebP)
    }

    func testScrollViewVisibilityPausesBlockAndRichTextAttachments() async throws {
        let window = try makeWindow()
        let controller = try DetailWebPTableFixtureController(includesRichText: true)
        window.rootViewController = controller
        controller.loadViewIfNeeded()
        defer { window.isHidden = true; window.rootViewController = nil }
        defer {
            let nodes = controller.animatedViews.map { "\($0.frame)" }.joined(separator: ", ")
            let diagnostics = XCTAttachment(string: controller.inlineViews.map { image in
                "playing=\(image.isPlayingWebP), imageFrame=\(image.frame), parentBounds=\(String(describing: image.superview?.bounds)), rectInRoot=\(image.convert(image.bounds, to: controller.view)), window=\(image.window != nil), nodes=\(nodes)"
            }.joined(separator: "\n"))
            diagnostics.name = "FramePlay-inline-final-layout"
            diagnostics.lifetime = .keepAlways
            add(diagnostics)
            let snapshot = XCTAttachment(image: UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            })
            snapshot.name = "FramePlay-UIKit-final-state"
            snapshot.lifetime = .keepAlways
            add(snapshot)
        }
        try await waitFor { controller.blockViews.count == 1 && controller.inlineViews.count == 1 }
        // 初次尺寸回流会重建附件，等富文本节流完成后再检查最终视图。
        try await Task.sleep(nanoseconds: 200_000_000)
        try await waitFor { controller.blockViews.allSatisfy(\.isPlayingWebP) && controller.inlineViews.allSatisfy(\.isPlayingWebP) }
        let initial = controller.inlineViews.map { digest($0.image) }
        try await waitFor { controller.inlineViews.map { self.digest($0.image) } != initial }
        let blocks = controller.blockViews
        let inlines = controller.inlineViews
        controller.table.setContentOffset(CGPoint(x: 0, y: 1_200), animated: false)
        try await waitFor { controller.animatedViews.allSatisfy { !controller.table.bounds.intersects($0.convert($0.bounds, to: controller.table)) } }
        XCTAssertTrue(blocks.allSatisfy { !$0.isPlayingWebP })
        XCTAssertTrue(inlines.allSatisfy { !$0.isPlayingWebP })
        controller.table.setContentOffset(.zero, animated: false)
        try await waitFor { controller.blockViews.allSatisfy(\.isPlayingWebP) && controller.inlineViews.allSatisfy(\.isPlayingWebP) }
        // 富文本附件尺寸更新有 100ms 的布局节流，截图等这一轮布局完成。
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(controller.inlineViews.count, 1)
        XCTAssertEqual(controller.inlineViews.first?.bounds.size, CGSize(width: 160, height: 160))
        let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
            XCTAssertTrue(controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true))
        })
        attachment.name = "FramePlay-UIKit-block-and-inline"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testScrollViewPlaybackMeasurements() async throws {
        guard ProcessInfo.processInfo.environment["FRAMEPLAY_INTEGRATION_PERFORMANCE"] == "1" else {
            throw XCTSkip("设置 TEST_RUNNER_FRAMEPLAY_INTEGRATION_PERFORMANCE=1 启用主项目性能采样")
        }
        let window = try makeWindow()
        let controller = try DetailWebPTableFixtureController(includesRichText: false)
        window.rootViewController = controller
        controller.loadViewIfNeeded()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await waitFor { controller.blockViews.count == 4 && controller.blockViews.allSatisfy(\.isPlayingWebP) }
        // 宿主启动和首轮布局单独完成后，采样稳定播放阶段。
        try await Task.sleep(nanoseconds: 2_000_000_000)
        let images = controller.blockViews.compactMap { $0.subviews.compactMap { $0 as? UIImageView }.first }
        let sampler = DetailWebPIntegrationSampler(images: images, scroll: controller.table)
        sampler.start()
        let cpu = Self.cpuSeconds()
        let start = ProcessInfo.processInfo.systemUptime
        try await Task.sleep(nanoseconds: 9_000_000_000)
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        let cpuPercent = (Self.cpuSeconds() - cpu) / elapsed * 100
        sampler.stop()
        XCTAssertTrue(controller.blockViews.allSatisfy(\.isPlayingWebP))
        XCTAssertTrue(sampler.changes.allSatisfy { $0.count > 2 })
        XCTAssertLessThanOrEqual(sampler.peakCacheBytes, 32 * 1_024 * 1_024)
        let report: [String: Any] = [
            "cpuPercentOfOneCore": cpuPercent, "wallSeconds": elapsed,
            "displayIntervalsMS": sampler.intervals, "frameChangeTimesMS": sampler.changes,
            "loopIntervalsMS": sampler.loops, "peakCacheBytes": sampler.peakCacheBytes,
            "resourceCount": PlaybackEnvironment.shared.statistics.resourceCount,
            "targetPixels": 160 * window.screen.scale, "warmupSeconds": 2
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "FramePlay-main-project-performance.json"
        attachment.lifetime = .keepAlways
        add(attachment)
        let screenshot = XCTAttachment(image: UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
            XCTAssertTrue(controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true))
        })
        screenshot.name = "FramePlay-main-project-four-images"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        controller.table.setContentOffset(CGPoint(x: 0, y: 1_200), animated: false)
        try await waitFor { controller.animatedViews.allSatisfy { !controller.table.bounds.intersects($0.convert($0.bounds, to: controller.table)) } }
        XCTAssertTrue(controller.blockViews.allSatisfy { !$0.isPlayingWebP })
    }

    private static func cpuSeconds() -> Double {
        var usage = rusage()
        precondition(getrusage(RUSAGE_SELF, &usage) == 0)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }

    private func makeWindow() throws -> UIWindow {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = try XCTUnwrap(scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController()
        window.rootViewController!.view.backgroundColor = .systemBackground
        window.windowLevel = .normal + 1
        window.makeKeyAndVisible()
        return window
    }

    private func digest(_ image: UIImage?) -> SHA256.Digest? {
        guard let data = image?.cgImage?.dataProvider?.data else { return nil }
        return SHA256.hash(data: data as Data)
    }

    private func waitFor(file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) async throws {
        let start = ProcessInfo.processInfo.systemUptime
        while !condition() {
            if ProcessInfo.processInfo.systemUptime - start > 5 {
                XCTFail("等待展示状态超时", file: file, line: line)
                throw PlaybackFailure.bufferTimeout
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}

@MainActor
private final class DetailWebPIntegrationSampler: NSObject {
    private let images: [UIImageView]
    private let scroll: UIScrollView
    private var link: CADisplayLink?
    private var started: Double = 0
    private var previousTick: Double?
    private var previousImages: [CGImage?]
    private let firstDigests: [SHA256.Digest?]
    private var loopStarts: [[Double]]
    private(set) var intervals: [Double] = []
    private(set) var changes: [[Double]]
    private(set) var peakCacheBytes = 0

    var loops: [[Double]] { loopStarts.map { values in zip(values, values.dropFirst()).map { $1 - $0 } } }

    init(images: [UIImageView], scroll: UIScrollView) {
        self.images = images
        self.scroll = scroll
        previousImages = images.map { $0.image?.cgImage }
        firstDigests = images.map { image in
            image.image?.cgImage?.dataProvider?.data.map { SHA256.hash(data: $0 as Data) }
        }
        changes = Array(repeating: [], count: images.count)
        loopStarts = Array(repeating: [0], count: images.count)
    }

    func start() {
        started = ProcessInfo.processInfo.systemUptime
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFramesPerSecond = 60
        link.add(to: .main, forMode: .common)
        self.link = link
    }
    func stop() { link?.invalidate(); link = nil }

    @objc private func tick() {
        let time = ProcessInfo.processInfo.systemUptime
        if let previousTick { intervals.append((time - previousTick) * 1_000) }
        previousTick = time
        for index in images.indices {
            let image = images[index].image?.cgImage
            guard let image, image !== previousImages[index] else { continue }
            previousImages[index] = image
            let milliseconds = (time - started) * 1_000
            changes[index].append(milliseconds)
            if let data = image.dataProvider?.data, SHA256.hash(data: data as Data) == firstDigests[index] {
                loopStarts[index].append(milliseconds)
            }
        }
        peakCacheBytes = max(peakCacheBytes, PlaybackEnvironment.shared.statistics.bufferedBytes)
        scroll.contentOffset.y = 10 + 10 * sin((time - started) * 2)
    }
}

@MainActor
private final class DetailWebPTableFixtureController: UIViewController, UIScrollViewDelegate {
    let table = UIScrollView()
    let stack = DetailBlockStack()
    private let includesRichText: Bool
    private let url: URL
    var animatedViews: [UIView] { stack.arrangedSubviews }
    var blockViews: [DetailImageBlockView] { animatedViews.compactMap { $0 as? DetailImageBlockView } }
    var inlineViews: [DetailInlineImageView] {
        func visit(_ view: UIView) -> [DetailInlineImageView] {
            if let image = view as? DetailInlineImageView { return [image] }
            return view.subviews.flatMap(visit)
        }
        return visit(stack)
    }

    init(includesRichText: Bool) throws {
        self.includesRichText = includesRichText
        url = try DetailWebPTestFixture.url()
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.addSubview(table)
        table.delegate = self
        table.addSubview(stack)
        stack.axis = .vertical
        stack.spacing = 20
        stack.viewport = table
        stack.imageSize = { _ in CGSize(width: 640, height: 640) }
        var blocks: [RenderedContentBlock] = [.image(.init(url: url, altText: "动态 WebP"))]
        if includesRichText {
            blocks += DTCoreTextHTMLContentRenderer().renderTextBlocks(
                fragment: "<p>内联 WebP <img src='\(url.absoluteString)' width='120' height='120'></p>",
                baseURL: NodeSeekSite.baseURL, maxImageWidth: 160)
        } else {
            blocks = Array(repeating: blocks[0], count: 4)
        }
        stack.appendLegacy(blocks, to: stack, width: 160)
        stack.onSizeChange = { [weak self] in self?.view.setNeedsLayout() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        table.frame = CGRect(x: 0, y: view.safeAreaInsets.top, width: view.bounds.width,
                             height: includesRichText ? 480 : view.bounds.height - view.safeAreaInsets.top)
        let height = stack.systemLayoutSizeFitting(CGSize(width: 160, height: 0),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        stack.frame = CGRect(x: 16, y: 10, width: 160, height: height)
        table.contentSize = CGSize(width: table.bounds.width, height: height + 2000)
        stack.layoutIfNeeded()
        stack.refreshPlayback()
    }
    func scrollViewDidScroll(_ scrollView: UIScrollView) { stack.refreshPlayback() }
}
