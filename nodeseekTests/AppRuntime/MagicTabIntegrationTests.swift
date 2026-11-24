import AsyncDisplayKit
import ImageIO
import JXPhotoBrowser
import UIKit
import Vision
import WebKit
import XCTest
@testable import nodeseek

@MainActor
final class MagicTabIntegrationTests: XCTestCase {
    private let baseURL = URL(string: "https://www.nodeseek.com")!

    func testPreservesTabsAndANSIControls() throws {
        let fragment = """
        <p>before</p><div class="nsk-magic-tabs">
        <div class="nsk-magic-tab-title">基本信息</div>
        <div class="nsk-magic-tab-body"><pre><code class="language-ansi"><span data-ansicode="27"></span>[31mRED<span data-ansicode="27"></span>[0m\nbar:   <span data-ansicode="8"></span>|</code></pre></div>
        <div class="nsk-magic-tab-title">图片</div><div class="nsk-magic-tab-body"><p><img src="/report.webp"></p></div>
        </div><p>after</p>
        """
        let blocks = DTCoreTextHTMLContentRenderer().render(fragment: fragment, baseURL: baseURL)
        XCTAssertEqual(blocks.count, 3)
        guard case .tabs(let tabs) = blocks[1], case .terminal(let terminal) = tabs.sections[0].blocks[0] else {
            return XCTFail("应保留可切换分栏和终端原文")
        }
        XCTAssertEqual(tabs.sections.map(\.title), ["基本信息", "图片"])
        XCTAssertEqual(terminal.ansi, "\u{1b}[31mRED\u{1b}[0m\nbar:   \u{8}|")
        guard case .image(let image) = tabs.sections[1].blocks[0] else { return XCTFail("原图片栏应继续输出图片") }
        XCTAssertEqual(image.url.absoluteString, "https://www.nodeseek.com/report.webp")
    }

    func testCapturedSourceTakesPrecedenceOverPartialXtermRows() throws {
        let encoded = try JSONEncoder().encode(["\u{1b}[32m完整报告\nLAST-LINE"]).base64EncodedString()
        let fragment = """
        <div class="nsk-magic-tabs"><div class="nsk-magic-tab-title">终端</div>
        <div class="nsk-magic-tab-body" data-nodeseek-terminal-source="\(encoded)"><div class="xterm-rows">不完整可见行</div></div></div>
        """
        let blocks = DTCoreTextHTMLContentRenderer().render(fragment: fragment, baseURL: baseURL)
        guard case .tabs(let tabs) = blocks.first, case .terminal(let terminal) = tabs.sections[0].blocks.first else {
            return XCTFail("应读取完整原文")
        }
        XCTAssertTrue(terminal.ansi.hasSuffix("LAST-LINE"))
        XCTAssertFalse(terminal.ansi.contains("不完整"))
    }

    func testWebViewCapturesSourceBeforeTerminalReplacement() async throws {
        let config = WKWebViewConfiguration()
        TerminalSourceCaptureScript.install(on: config)
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 400, height: 600), configuration: config)
        web.loadHTMLString("""
        <div class="nsk-magic-tab-body"><pre><code><span data-ansicode="27"></span>[31mFULL\nLAST</code></pre></div>
        <script>document.querySelector('.nsk-magic-tab-body').innerHTML='<div class="xterm-rows">partial</div>';</script>
        """, baseURL: baseURL)
        var encoded: String?
        for _ in 0..<100 {
            encoded = try? await web.evaluateJavaScript("document.querySelector('.nsk-magic-tab-body')?.getAttribute('data-nodeseek-terminal-source')") as? String
            if encoded != nil { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let data = try XCTUnwrap(encoded.flatMap { Data(base64Encoded: $0) })
        XCTAssertEqual(try JSONDecoder().decode([String].self, from: data), ["\u{1b}[31mFULL\nLAST"])
        web.stopLoading()
    }

    func testReportViewsReusePreviewOnlyForSameContentAndSize() async throws {
        let window = makeWindow(controller: UIViewController())
        defer { window.isHidden = true; window.rootViewController = nil }
        let host = try XCTUnwrap(window.rootViewController?.view)
        func preview(_ text: String, width: CGFloat) async throws -> CGImage {
            let view = DetailTerminalView(terminal: .init(ansi: text), onImageTapped: { _, _ in }, onImageLoaded: { _ in })
            view.frame = CGRect(x: 0, y: 0, width: width, height: 120)
            host.addSubview(view)
            defer { view.removeFromSuperview() }
            for _ in 0..<400 where view.snapshot == nil { try await Task.sleep(nanoseconds: 10_000_000) }
            return try XCTUnwrap(view.detailPhotoThumbnailView.image?.cgImage)
        }
        let text = "同一份报告"
        let first = try await preview(text, width: 160)
        let repeatImage = try await preview(text, width: 160)
        let larger = try await preview(text, width: 600)
        let other = try await preview("另一份报告", width: 160)
        XCTAssertTrue(first === repeatImage)
        XCTAssertGreaterThan(larger.width, first.width)
        XCTAssertFalse(first === other)
    }

    func testMergedSnapshotContainsLastLineAndReusesDiskCache() async throws {
        let window = makeWindow(controller: UIViewController())
        defer { window.rootViewController = nil; window.isHidden = true }
        let host = try XCTUnwrap(window.rootViewController?.view)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = TerminalSnapshotCache(root: directory)
        let renderer = TerminalSnapshotRenderer(cache: cache)
        // 末行使用默认前景色，避免深红文字的 OCR 对比度影响截图完整性检查。
        let ansi = (1...159).map { "\u{1b}[31mROW-\($0)\u{1b}[0m" }.joined(separator: "\n") + "\nROW-160"
        let terminal = RenderedTerminalBlock(ansi: ansi)
        let first = try await renderer.render(terminal, in: host)
        XCTAssertEqual(first.pages.count, 1)
        XCTAssertTrue(first.text.hasSuffix("ROW-160"))
        XCTAssertTrue(first.pages.allSatisfy { $0.width * $0.height <= 16_000_000 && max($0.width, $0.height) <= 16_384 })
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        if let last = first.pages.last {
            let destination = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("magic-tabs-merged-report.png")
            try Data(contentsOf: last.url).write(to: destination)
        }
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(XCTUnwrap(first.pages.first).url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let bottom = try XCTUnwrap(image.cropping(to: CGRect(x: 0, y: image.height - 400, width: 400, height: 400)))
        try VNImageRequestHandler(cgImage: bottom).perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined()
        XCTAssertTrue(text.contains("160"), "最终图片也必须包含末行：\(text)")
        let second = try await TerminalSnapshotRenderer(cache: cache).render(terminal, in: host)
        XCTAssertEqual(first.pages.map(\.url), second.pages.map(\.url))
        XCTAssertEqual(first.text, second.text)
    }

    func testMergePreservesTileOrderAndSeamPixels() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = TerminalSnapshotCache(root: directory)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        func tile(_ colors: [UIColor]) -> UIImage {
            UIGraphicsImageRenderer(size: CGSize(width: 6, height: colors.count), format: format).image { context in
                for (row, color) in colors.enumerated() {
                    color.setFill()
                    context.fill(CGRect(x: 0, y: row, width: 6, height: 1))
                }
            }
        }
        let first = tile([.red, .green, .blue])
        let second = tile([.yellow, .magenta])
        let pages = try await [cache.save(image: first, key: "seam", index: 0), cache.save(image: second, key: "seam", index: 1)]
        let result = try await cache.finish(.init(pages: pages, text: "report"), key: "seam")
        XCTAssertEqual(result.pages.count, 1)
        let merged = try XCTUnwrap(UIImage(contentsOfFile: XCTUnwrap(result.pages.first).url.path)?.cgImage)
        XCTAssertEqual(merged.width, 6)
        XCTAssertEqual(merged.height, 5)
        // 比较解码后的像素，不依赖 PNG 编码器的元数据或压缩结果。
        func pixels(_ image: CGImage) throws -> Data {
            let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return Data(bytes: try XCTUnwrap(context.data), count: image.width * image.height * 4)
        }
        XCTAssertEqual(try pixels(XCTUnwrap(merged.cropping(to: CGRect(x: 0, y: 0, width: 6, height: 3)))), try pixels(XCTUnwrap(first.cgImage)))
        XCTAssertEqual(try pixels(XCTUnwrap(merged.cropping(to: CGRect(x: 0, y: 3, width: 6, height: 2)))), try pixels(XCTUnwrap(second.cgImage)))
        XCTAssertTrue(pages.allSatisfy { !FileManager.default.fileExists(atPath: $0.url.path) })
    }

    func testCancellingOneConsumerDoesNotCancelAnother() async throws {
        let window = makeWindow(controller: UIViewController())
        defer { window.rootViewController = nil; window.isHidden = true }
        let host = try XCTUnwrap(window.rootViewController?.view)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let renderer = TerminalSnapshotRenderer(cache: TerminalSnapshotCache(root: directory))
        let source = RenderedTerminalBlock(ansi: "\u{1b}[32mSHARED REPORT")
        let first = Task { try await renderer.render(source, in: host) }
        let second = Task { try await renderer.render(source, in: host) }
        await Task.yield()
        first.cancel()
        do { _ = try await first.value; XCTFail("取消的订阅应抛出取消错误") } catch is CancellationError {} catch { XCTFail("\(error)") }
        let shared = try await second.value
        XCTAssertEqual(shared.text, "SHARED REPORT")
    }

    func testGalleryKeepsSectionOrderAndRepeatedImagePositions() async throws {
        let first = URL(string: "https://example.com/first.png")!
        let second = URL(string: "https://example.com/second.png")!
        let tabs = RenderedMagicTabsBlock(id: "order", sections: [
            .init(title: "基本信息", blocks: [.image(.init(url: first, altText: nil))]),
            .init(title: "空栏", blocks: [.codeBlock(.init(text: "text"))]),
            .init(title: "网络质量", blocks: [.quote(.init(children: [.image(.init(url: second, altText: nil))]))]),
            .init(title: "回程路由", blocks: [.image(.init(url: first, altText: nil))])
        ])
        let images = try await DetailMagicTabGallery.images(in: tabs, host: UIView())
        XCTAssertEqual(images.map(\.url), [first, second, first])
        XCTAssertEqual(images.map(\.sectionIndex), [0, 2, 3])
    }

    func testGalleryPreparationUsesSpinnerAndCancelsOnTabChange() async throws {
        let controller = UIViewController()
        let window = makeWindow(controller: controller)
        defer { window.rootViewController = nil; window.isHidden = true }
        let url = URL(string: "https://example.com/report.png")!
        let tabs = RenderedMagicTabsBlock(id: UUID().uuidString, sections: [
            .init(title: "基本信息", blocks: [.image(.init(url: url, altText: nil))]),
            .init(title: "IP 质量", blocks: [])
        ])
        var didOpenGallery = false
        let node = DetailMagicTabsNode(tabs: tabs, makeContent: { _, _, _ in [] }, onImageTapped: { _, _ in
            didOpenGallery = true
        }, onLayoutInvalidated: {})
        node.view.frame = CGRect(x: 0, y: 100, width: 300, height: 300)
        controller.view.addSubview(node.view)
        defer { node.view.removeFromSuperview() }
        node.openGallery(sectionIndex: 0, imageURLs: [url], imageIndex: 0)
        let loading = try XCTUnwrap(node.galleryLoadingView)
        XCTAssertNotNil(loading.superview)
        XCTAssertTrue(try XCTUnwrap(findView(UIActivityIndicatorView.self, in: loading)).isAnimating)
        XCTAssertFalse(loading.isUserInteractionEnabled)
        XCTAssertNil(controller.presentedViewController, "准备图片时不应弹出 alert")
        node.selectTab(1)
        XCTAssertNil(node.galleryLoadingView)
        XCTAssertNil(loading.superview)
        XCTAssertNil(node.galleryTask)
        await Task.yield()
        XCTAssertFalse(didOpenGallery, "切换分栏后不应再打开上一次请求的图库")
    }

    func testTCPQualityFixtureKeepsFiveFullLengthImagesInOneGallery() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "post-917559-tq", withExtension: "html"))
        let html = try String(contentsOf: url, encoding: .utf8)
        let blocks = DTCoreTextHTMLContentRenderer().render(fragment: html, baseURL: baseURL)
        let tabs = try XCTUnwrap(blocks.compactMap { block -> RenderedMagicTabsBlock? in
            if case .tabs(let tabs) = block { return tabs }; return nil
        }.first)
        XCTAssertEqual(tabs.sections.map(\.title), ["IPv4回程", "IPv4大包回程", "IPv6回程", "国际互联", "单线程测速"])
        for section in tabs.sections {
            XCTAssertEqual(section.blocks.count, 1)
            guard case .image = section.blocks[0] else { return XCTFail("TQ 应直接复用原 PNG 图片") }
        }
        let images = try await DetailMagicTabGallery.images(in: tabs, host: UIView())
        XCTAssertEqual(images.map(\.sectionIndex), [0, 1, 2, 3, 4])
        XCTAssertEqual(images.map { URLComponents(url: $0.url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value }, ["ipv4", "large4", "ipv6", "intl", "speedtest"])
        XCTAssertEqual(Set(images.map(\.url)).count, 5, "section 参数不同的图片不能被合并")
        let nodes = DetailContentBlockNodeFactory.makeNodes(from: tabs.sections[0].blocks,
            onImageTapped: { _, _ in }, onLinkTapped: { _ in }, onTextLayoutInvalidated: {})
        let imageNode = try XCTUnwrap(nodes.first as? DetailImageBlockNode)
        imageNode.updateLoadedImageSize(CGSize(width: 1840, height: 2125))
        let size = imageNode.calculateSizeThatFits(CGSize(width: 368, height: CGFloat.greatestFiniteMagnitude))
        XCTAssertEqual(size.height, 425, "TQ 报告应完整等比展示，不能裁成普通图片缩略图")
        let imageView = try XCTUnwrap(imageNode.view.subviews.compactMap { $0 as? UIImageView }.first)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let preview = UIGraphicsImageRenderer(size: CGSize(width: 368, height: 425), format: format).image { _ in }
        let thumbnail = UIImage(cgImage: try XCTUnwrap(preview.cgImage), scale: 2, orientation: .up)
        let block = try XCTUnwrap(imageNode.view as? DetailImageBlockView)
        block.applyLoadedImage(.init(image: thumbnail, resolvedKind: nil, originalSize: CGSize(width: 1840, height: 2125)))
        imageNode.view.frame = CGRect(x: 0, y: 0, width: 368, height: 425)
        imageNode.view.layoutSubviews()
        XCTAssertEqual(imageView.contentMode, .scaleAspectFit, "内部 UIImageView 也应沿用报告类型")
        XCTAssertEqual(imageView.frame.height, 425)
    }

    func testThirdAndFourthTabImagesKeepFullHeightAfterThumbnailLoads() throws {
        let sources: [(URL, CGSize)] = [
            (URL(string: "https://i.111666.best/image/ZzlhGuSJ768Td5jISYhq8F.webp")!, CGSize(width: 1312, height: 1782)),
            (URL(string: "https://i.111666.best/image/eRsXlQXnz9JUsESDid2ona.webp")!, CGSize(width: 1989, height: 3766))
        ]
        let tabs = RenderedMagicTabsBlock(id: UUID().uuidString, sections: [
            .init(title: "基本信息", blocks: [.codeBlock(.init(text: "basic"))]),
            .init(title: "IP质量", blocks: [.codeBlock(.init(text: "ip"))])
        ] + sources.enumerated().map { index, source in
            .init(title: index == 0 ? "网络质量" : "回程路由", blocks: [.image(.init(url: source.0, altText: nil))])
        })
        let nodes = DetailContentBlockNodeFactory.makeNodes(from: [.tabs(tabs)],
            onImageTapped: { _, _ in }, onLinkTapped: { _ in }, onTextLayoutInvalidated: {},
            imageSizeProvider: { url in sources.first { $0.0 == url }?.1 })
        let tabNode = try XCTUnwrap(nodes.first as? DetailMagicTabsNode)
        let range = ASSizeRange(min: CGSize(width: 368, height: 0), max: CGSize(width: 368, height: CGFloat.greatestFiniteMagnitude))
        let baselineHeight = tabNode.layoutThatFits(range).size.height
        for index in [2, 3, 2] {
            tabNode.selectTab(index)
            let layout = tabNode.layoutThatFits(range)
            XCTAssertEqual(layout.size.height, baselineHeight, "各栏统一使用基本信息的高度")
            tabNode.view.frame = CGRect(origin: .zero, size: layout.size)
            tabNode.layoutIfNeeded()
            let node = try XCTUnwrap(findNode(DetailImageBlockNode.self, in: tabNode))
            let original = sources[index - 2].1
            let expectedHeight = ceil(368 * original.height / original.width)
            XCTAssertEqual(node.calculateSizeThatFits(range.max).height, expectedHeight, "分栏原图不能按普通图片裁切")
            node.updateLoadedImageSize(CGSize(width: original.width / 16, height: original.height / 16))
            XCTAssertEqual(node.calculateSizeThatFits(range.max).height, expectedHeight, "缩略图加载与切栏返回都不能压缩报告高度")
            let imageView = try XCTUnwrap(node.view.subviews.compactMap { $0 as? UIImageView }.first)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let preview = UIGraphicsImageRenderer(size: original, format: format).image { _ in }
            let thumbnail = UIImage(cgImage: try XCTUnwrap(preview.cgImage), scale: 16, orientation: .up)
            let block = try XCTUnwrap(node.view as? DetailImageBlockView)
            block.applyLoadedImage(.init(image: thumbnail, resolvedKind: nil, originalSize: original))
            node.view.frame = CGRect(x: 0, y: 0, width: 368, height: expectedHeight)
            node.view.layoutSubviews()
            XCTAssertEqual(imageView.contentMode, .scaleAspectFit)
            XCTAssertEqual(imageView.frame.width, 368)
            XCTAssertEqual(imageView.frame.height, 368 * original.height / original.width, accuracy: 0.01)
        }
        let ordinary = DetailContentBlockNodeFactory.makeNodes(from: [.image(.init(url: sources[0].0, altText: nil))],
            onImageTapped: { _, _ in }, onLinkTapped: { _ in }, onTextLayoutInvalidated: {},
            imageSizeProvider: { _ in sources[0].1 })
        XCTAssertEqual(ordinary[0].calculateSizeThatFits(range.max).height, 368, "分栏之外的普通竖图高度受栏宽限制")
    }

    private func waitForPhotoBrowser(in controller: UIViewController) async throws -> JXPhotoBrowserViewController {
        for _ in 0..<500 {
            if let browser = controller.presentedViewController as? JXPhotoBrowserViewController {
                try await Task.sleep(nanoseconds: 300_000_000)
                return browser
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        return try XCTUnwrap(controller.presentedViewController as? JXPhotoBrowserViewController)
    }

    private func makeWindow(controller: UIViewController) -> UIWindow {
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
            window.frame = scene.coordinateSpace.bounds
        } else {
            window = UIWindow(frame: UIScreen.main.bounds)
        }
        window.windowLevel = .normal + 1
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = controller
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        return window
    }

    private func findView<T: UIView>(_ type: T.Type, in view: UIView) -> T? {
        if let result = view as? T { return result }
        return view.subviews.compactMap { findView(type, in: $0) }.first
    }

    private func findNode<T: ASDisplayNode>(_ type: T.Type, in node: ASDisplayNode) -> T? {
        if let result = node as? T { return result }
        return (node.subnodes ?? []).compactMap { findNode(type, in: $0) }.first
    }

    private func saveScreenshot(_ window: UIWindow, name: String) throws {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try image.pngData()?.write(to: directory.appendingPathComponent(name + ".png"))
    }
}

private final class TerminalTestPresenter: PostDetailPresenterProtocol {
    func viewDidLoad() {}
    func refreshInitialPage() {}
    func didSelectCommentPage(_ page: Int) {}
    func didTapLogin() {}
    func didApproachCommentEnd() -> Bool { false }
    func didTapRefreshCommentsAtEnd() {}
    func didTapSendReply(content: String) {}
    func didTapFavorite() {}
    func didTapPostLike() {}
    func didTapPostChickenLeg() {}
    func didTapPostOppose() {}
    func didTapCommentLike(_ comment: Comment) {}
    func didTapCommentChickenLeg(_ comment: Comment) {}
    func didTapCommentOppose(_ comment: Comment) {}
    func didTapEditPost() {}
    func didTapEditComment(_ comment: Comment) {}
}
