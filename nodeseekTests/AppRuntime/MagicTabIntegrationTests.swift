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

    func testActualDetailDisplaysImagesAndSwitchesTabs() async throws {
        struct Fixture: Decodable { struct Report: Decodable { let title: String; let ansi: String }; let reports: [Report] }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "post-916971-terminals", withExtension: "json"))
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        let renderer = DTCoreTextHTMLContentRenderer()
        let html = "<div class=\"nsk-magic-tabs\">" + fixture.reports.map {
            "<div class=\"nsk-magic-tab-title\">\($0.title)</div><div class=\"nsk-magic-tab-body\"><pre><code>\(renderer.escapedHTML($0.ansi).replacingOccurrences(of: "\u{1b}", with: "<span data-ansicode=\"27\"></span>").replacingOccurrences(of: "\u{8}", with: "<span data-ansicode=\"8\"></span>"))</code></pre></div>"
        }.joined() + "<div class=\"nsk-magic-tab-title\">🌐网络质量</div><div class=\"nsk-magic-tab-body\"><p>图片栏测试</p></div><div class=\"nsk-magic-tab-title\">📍回程路由</div><div class=\"nsk-magic-tab-body\"><p>路由栏测试</p></div></div>"
        let controller = PostDetailViewController(presenter: TerminalTestPresenter())
        let window = makeWindow(controller: UINavigationController(rootViewController: controller))
        defer {
            controller.tableNode.view.removeFromSuperview()
            window.rootViewController = nil
            window.isHidden = true
        }
        controller.render(detail: PostDetail(id: "916971", title: "[NQ] Netcup RS 1000 G9.5 PRO MNZ 美东翻倍", authorName: "zhizhu", avatarURL: nil, metadataText: "测评", contentHTML: html, comments: []))
        var terminal: DetailTerminalView?
        for _ in 0..<500 {
            window.layoutIfNeeded()
            terminal = findView(DetailTerminalView.self, in: controller.view)
            if terminal?.snapshot != nil { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertNotNil(terminal?.snapshot, "真实详情页应生成第一栏图片")
        XCTAssertEqual(terminal?.snapshot?.pages.count, 1)
        let row = try XCTUnwrap(controller.tableNode.nodeForRow(at: IndexPath(row: 0, section: 0)))
        let tabs = try XCTUnwrap(findNode(DetailMagicTabsNode.self, in: row))
        XCTAssertEqual(tabs.selectedIndex, 0)
        try saveScreenshot(window, name: "magic-tabs-basic-light")
        let basicURL = try XCTUnwrap(terminal?.snapshot?.pages.first?.url)
        let basicButton = try XCTUnwrap(terminal?.subviews.compactMap { $0 as? UIButton }
            .first { $0.accessibilityIdentifier == "detail-terminal-open-report" })
        basicButton.sendActions(for: .touchUpInside)
        let basicBrowser = try await waitForPhotoBrowser(in: controller)
        XCTAssertEqual(basicBrowser.initialIndex, 0)
        XCTAssertEqual(controller.photoBrowserPresenter?.numberOfItems(in: basicBrowser), 2)
        // 尚未点开 IP 分栏，也应已经可以在既有浏览器中向右翻到它。
        basicBrowser.view.layoutIfNeeded()
        basicBrowser.collectionView.scrollToItem(at: IndexPath(item: 1, section: 0), at: .centeredHorizontally, animated: false)
        basicBrowser.collectionView.layoutIfNeeded()
        basicBrowser.scrollViewDidEndDecelerating(basicBrowser.collectionView)
        XCTAssertEqual(basicBrowser.pageIndex, 1)
        for _ in 0..<100 {
            let cell = basicBrowser.collectionView.cellForItem(at: IndexPath(item: 1, section: 0)) as? JXZoomImageCell
            if cell?.imageView.image != nil, cell?.imageView.accessibilityIdentifier != basicURL.absoluteString { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let nextCell = try XCTUnwrap(basicBrowser.collectionView.cellForItem(at: IndexPath(item: 1, section: 0)) as? JXZoomImageCell)
        XCTAssertNotNil(nextCell.imageView.image)
        XCTAssertNotEqual(nextCell.imageView.accessibilityIdentifier, basicURL.absoluteString)
        try saveScreenshot(window, name: "magic-tabs-swipe-basic-to-ip")
        basicBrowser.collectionView.scrollToItem(at: IndexPath(item: 0, section: 0), at: .centeredHorizontally, animated: false)
        basicBrowser.scrollViewDidEndDecelerating(basicBrowser.collectionView)
        XCTAssertEqual(basicBrowser.pageIndex, 0)
        await withCheckedContinuation { continuation in
            controller.dismiss(animated: false) { continuation.resume() }
        }
        tabs.selectTab(1)
        for _ in 0..<500 {
            window.layoutIfNeeded()
            terminal = findView(DetailTerminalView.self, in: controller.view)
            if terminal?.snapshot?.text.contains("IP质量体检报告") == true { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(terminal?.snapshot?.text.contains("IP质量体检报告") == true)
        try saveScreenshot(window, name: "magic-tabs-ip-light")
        let reportView = try XCTUnwrap(terminal)
        let openButton = try XCTUnwrap(reportView.subviews.compactMap { $0 as? UIButton }
            .first { $0.accessibilityIdentifier == "detail-terminal-open-report" })
        XCTAssertTrue(openButton.isEnabled)
        // 整张报告都可打开既有大图，底部不再保留复制按钮或额外留白。
        XCTAssertFalse(reportView.subviews.contains { $0.accessibilityLabel == "复制报告" })
        XCTAssertEqual(findView(UIImageView.self, in: reportView)?.frame, reportView.bounds)
        XCTAssertTrue(reportView.hitTest(CGPoint(x: 20, y: 20), with: nil) === openButton)
        XCTAssertTrue(reportView.hitTest(CGPoint(x: 20, y: reportView.bounds.height - 20), with: nil) === openButton)
        openButton.sendActions(for: .touchUpInside)
        let browser = try await waitForPhotoBrowser(in: controller)
        let presenter = try XCTUnwrap(controller.photoBrowserPresenter)
        let pages = try XCTUnwrap(reportView.snapshot?.pages)
        XCTAssertEqual(pages.count, 1, "每份报告应作为一张完整长图交给既有浏览器")
        XCTAssertEqual(presenter.numberOfItems(in: browser), 2)
        XCTAssertEqual(browser.initialIndex, 1, "点开 IP 质量应定位到图库第二张")
        let cell = JXZoomImageCell(frame: .zero)
        presenter.photoBrowser(browser, willDisplay: cell, at: 1)
        for _ in 0..<100 {
            if cell.imageView.image != nil { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(cell.imageView.image?.cgImage?.height, pages.last.map { Int($0.height) })
        try await Task.sleep(nanoseconds: 300_000_000)
        try saveScreenshot(window, name: "magic-tabs-existing-browser")
        await withCheckedContinuation { continuation in
            controller.dismiss(animated: false) { continuation.resume() }
        }
        window.overrideUserInterfaceStyle = .dark
        window.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 200_000_000)
        let selectedButton = try XCTUnwrap((findNode(ASScrollNode.self, in: tabs)?.subnodes ?? [])
            .compactMap { $0 as? ASButtonNode }.first { $0.accessibilityIdentifier == "detail-magic-tab-1" })
        let selectedColor = selectedButton.attributedTitle(for: .normal)?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        XCTAssertEqual(selectedColor, UIColor.label.resolvedColor(with: window.traitCollection))
        try saveScreenshot(window, name: "magic-tabs-ip-dark")
        tabs.selectTab(0)
        XCTAssertEqual(tabs.selectedIndex, 0)
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
        imageView.image = UIImage(cgImage: try XCTUnwrap(preview.cgImage), scale: 2, orientation: .up)
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
            imageView.image = UIImage(cgImage: try XCTUnwrap(preview.cgImage), scale: 16, orientation: .up)
            node.view.frame = CGRect(x: 0, y: 0, width: 368, height: expectedHeight)
            node.view.layoutSubviews()
            XCTAssertEqual(imageView.contentMode, .scaleAspectFit)
            XCTAssertEqual(imageView.frame.width, 368)
            XCTAssertEqual(imageView.frame.height, 368 * original.height / original.width, accuracy: 0.01)
        }
        let ordinary = DetailContentBlockNodeFactory.makeNodes(from: [.image(.init(url: sources[0].0, altText: nil))],
            onImageTapped: { _, _ in }, onLinkTapped: { _ in }, onTextLayoutInvalidated: {},
            imageSizeProvider: { _ in sources[0].1 })
        XCTAssertEqual(ordinary[0].calculateSizeThatFits(range.max).height, 184, "分栏之外仍沿用普通图片展示规则")
    }

    func testActualDetailThirdTabUsesBasicHeightAndScrollsFullReport() async throws {
        // 下载自帖子 916971 的网络质量栏，离线验证真实 WebP 的加载与最终排版。
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "post-916971-network", withExtension: "webp"))
        let html = """
        <div class="nsk-magic-tabs">
        <div class="nsk-magic-tab-title">基本信息</div><div class="nsk-magic-tab-body"><p>基本信息<br>CPU<br>内存<br>硬盘<br>系统<br>网络<br>测试结果<br>报告结束</p></div>
        <div class="nsk-magic-tab-title">IP质量</div><div class="nsk-magic-tab-body"><p>IP质量</p></div>
        <div class="nsk-magic-tab-title">网络质量</div><div class="nsk-magic-tab-body"><p><img src="\(url.absoluteString)"></p></div>
        </div>
        """
        let controller = PostDetailViewController(presenter: TerminalTestPresenter())
        let window = makeWindow(controller: UINavigationController(rootViewController: controller))
        defer {
            controller.tableNode.view.removeFromSuperview()
            window.rootViewController = nil
            window.isHidden = true
        }
        controller.render(detail: PostDetail(id: "916971", title: "NQ 网络质量完整图片", authorName: "zhizhu", avatarURL: nil, metadataText: "测评", contentHTML: html, comments: []))
        var tabs: DetailMagicTabsNode?
        for _ in 0..<100 {
            window.layoutIfNeeded()
            if let row = controller.tableNode.nodeForRow(at: IndexPath(row: 0, section: 0)) {
                tabs = findNode(DetailMagicTabsNode.self, in: row)
            }
            if let tabs, tabs.bounds.height > 56 { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let tabNode = try XCTUnwrap(tabs)
        let baselineHeight = tabNode.bounds.height
        for index in [2, 0, 2] {
            tabNode.selectTab(index)
            try await Task.sleep(nanoseconds: 200_000_000)
            guard index == 2 else { continue }
            let scroll = try XCTUnwrap(tabNode.subnodes?.first { $0.accessibilityIdentifier == "detail-magic-tab-content" } as? ASScrollNode)
            var report: DetailImageBlockNode?
            var imageView: UIImageView?
            for _ in 0..<100 {
                window.layoutIfNeeded()
                report = findNode(DetailImageBlockNode.self, in: tabNode)
                imageView = report?.view.subviews.compactMap { $0 as? UIImageView }.first
                if let report, imageView?.image != nil {
                    let height = ceil(report.bounds.width * 1782 / 1312)
                    if abs(report.bounds.height - height) <= 1,
                       abs(scroll.view.contentSize.height - height) <= 1 { break }
                }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            try await Task.sleep(nanoseconds: 250_000_000)
            window.layoutIfNeeded()
            let node = try XCTUnwrap(report)
            let image = try XCTUnwrap(imageView)
            XCTAssertNotNil(image.image)
            let height = ceil(node.bounds.width * 1782 / 1312)
            XCTAssertEqual(node.bounds.height, height, accuracy: 1)
            XCTAssertEqual(image.frame.height, height, accuracy: 1)
            XCTAssertEqual(image.frame.width, node.bounds.width, accuracy: 0.01)
            XCTAssertEqual(tabNode.bounds.height, baselineHeight, accuracy: 1)
            XCTAssertEqual(scroll.bounds.height, baselineHeight - 56, accuracy: 1)
            XCTAssertGreaterThan(scroll.view.contentSize.height, scroll.bounds.height)
            scroll.view.setContentOffset(CGPoint(x: 0, y: scroll.view.contentSize.height - scroll.bounds.height), animated: false)
            XCTAssertEqual(image.convert(image.bounds, to: scroll.view).maxY, scroll.view.bounds.maxY, accuracy: 1, "固定高度内仍能滚动到报告末尾")
        }
        try saveScreenshot(window, name: "magic-tabs-fixed-height-scroll-bottom")
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
    func didTapLogin() {}
    func didApproachCommentEnd() {}
    func didTapRefreshCommentsAtEnd() {}
    func didTapSendReply(content: String) {}
    func didTapFavorite() {}
    func didTapPostLike() {}
    func didTapPostChickenLeg() {}
    func didTapPostOppose() {}
    func didTapCommentLike(_ comment: Comment) {}
    func didTapCommentChickenLeg(_ comment: Comment) {}
    func didTapCommentOppose(_ comment: Comment) {}
}
