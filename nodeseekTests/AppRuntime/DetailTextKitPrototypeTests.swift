#if DEBUG
import Kingfisher
import SafariServices
import UIKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import nodeseek

@MainActor
final class DetailTextKitPrototypeTests: XCTestCase {
    private func descendants<T: UIView>(_ root: UIView, _ type: T.Type) -> [T] {
        (root as? T).map { [$0] } ?? root.subviews.flatMap { descendants($0, type) }
    }

    private func tabButton(_ index: Int, in root: UIView) -> UIButton? {
        descendants(root, UIButton.self).first { $0.accessibilityIdentifier == "detail-magic-tab-\(index)" }
    }

    func testTabsKeepTextureStripHeightAndOldPageUntilNewIsReady() async throws {
        let long = String(repeating: "第二页很长。", count: 400)
        let markdown = ":::: tabs\n::: tab-item 一\n首页\n:::\n::: tab-item 二\n" + long + "\n:::\n::::"
        let page = DetailMarkdownPrototypeController(id: "strip", source: .init(html: "", visibleMarkdown: markdown))
        let window = try host(page)
        defer { window.isHidden = true }
        func visibleText() -> [String] { descendants(page.view, DetailSelectableTextView.self).map { $0.snapshot.string } }
        try await waitFor { visibleText() == ["首页"] }
        // 与 Texture 一致：文字标签条，选中项加粗加下划线，不用系统分段控件。
        XCTAssertTrue(descendants(page.view, UISegmentedControl.self).isEmpty)
        let first = try XCTUnwrap(tabButton(0, in: page.view))
        let second = try XCTUnwrap(tabButton(1, in: page.view))
        func underlined(_ button: UIButton) -> Bool {
            (button.attributedTitle(for: .normal)?.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int ?? 0) != 0
        }
        XCTAssertTrue(underlined(first))
        XCTAssertFalse(underlined(second))
        func all(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(all) }
        let viewport = try XCTUnwrap(all(page.view).first { $0.accessibilityIdentifier == "detail-magic-tab-content" } as? UIScrollView)
        page.view.layoutIfNeeded()
        let height = viewport.bounds.height
        XCTAssertGreaterThan(height, 0)

        second.sendActions(for: .touchUpInside)
        // 新页排好前保留旧页，避免切换时出现空白闪烁。
        XCTAssertEqual(visibleText(), ["首页"])
        XCTAssertTrue(underlined(second))
        try await waitFor { visibleText() == [long] }
        page.view.layoutIfNeeded()
        // 高度以第一栏为准，长内容在栏内滚动，楼层高度不随切换变化。
        XCTAssertEqual(viewport.bounds.height, height, accuracy: 0.5)
        XCTAssertGreaterThan(viewport.contentSize.height, height)
    }

    func testTappingImageOpensWholeFloorGallery() async throws {
        let first = URL(string: "https://example.invalid/a.png")!
        let second = URL(string: "https://example.invalid/b.png")!
        let markdown = "文字\n\n![甲](\(first.absoluteString))\n\n> ![乙](\(second.absoluteString))"
        let page = DetailMarkdownPrototypeController(id: "gallery", source: .init(html: "", visibleMarkdown: markdown))
        let window = try host(page)
        defer { window.isHidden = true }
        try await waitFor { self.descendants(page.view, DetailImageBlockView.self).count == 2 }
        let stack = try XCTUnwrap(descendants(page.view, DetailBlockStack.self).first)
        var opened: ([URL], Int)?
        stack.onPhotos = { opened = ($0, $1) }
        // 与旧版一致：点任意一张都从整楼图片里打开，可左右翻到同楼其它图。
        descendants(page.view, DetailImageBlockView.self)[1].handleTap()
        XCTAssertEqual(opened?.0, [first, second])
        XCTAssertEqual(opened?.1, 1)
    }

    func testTabImageOpensGalleryAcrossAllTabs() async throws {
        let first = URL(string: "https://example.invalid/tab-a.png")!
        let second = URL(string: "https://example.invalid/tab-b.png")!
        let outside = URL(string: "https://example.invalid/outside.png")!
        let markdown = "![外](\(outside.absoluteString))\n\n:::: tabs\n::: tab-item 一\n![甲](\(first.absoluteString))\n:::\n::: tab-item 二\n![乙](\(second.absoluteString))\n:::\n::::"
        let page = DetailMarkdownPrototypeController(id: "tab-gallery", source: .init(html: "", visibleMarkdown: markdown))
        let window = try host(page)
        defer { window.isHidden = true }
        try await waitFor { self.descendants(page.view, DetailImageBlockView.self).count == 2 }
        let stack = try XCTUnwrap(descendants(page.view, DetailBlockStack.self).first)
        var opened: ([URL], Int)?
        stack.onPhotos = { opened = ($0, $1) }
        let tabImage = try XCTUnwrap(descendants(page.view, DetailImageBlockView.self).first { $0.url == first })
        // 与旧版一致：标签内的图按报告图处理，图集跨所有标签，不混入标签外的图。
        XCTAssertEqual(tabImage.imageKind, .report)
        tabImage.handleTap()
        try await waitFor { opened != nil }
        XCTAssertEqual(opened?.0, [first, second])
        XCTAssertEqual(opened?.1, 0)
        opened = nil
        try XCTUnwrap(descendants(page.view, DetailImageBlockView.self).first { $0.url == outside }).handleTap()
        XCTAssertEqual(opened?.0, [outside])
    }

    func testKnownImageSizeReservesFinalHeightBeforeLoading() async throws {
        let url = URL(string: "https://example.invalid/known-\(UUID().uuidString).png")!
        DetailBlockStack.rememberImageSize(CGSize(width: 400, height: 1000), for: url)
        let page = DetailMarkdownPrototypeController(id: "known-size", source: .init(html: "", visibleMarkdown: "![图](\(url.absoluteString))"))
        let window = try host(page)
        defer { window.isHidden = true }
        try await waitFor { !self.descendants(page.view, DetailImageBlockView.self).isEmpty }
        let image = try XCTUnwrap(descendants(page.view, DetailImageBlockView.self).first)
        page.view.layoutIfNeeded()
        // 与旧版一致：已知尺寸的图直接按最终高度占位，加载完成后楼层不再撑开。
        let expected = DetailImageLayout.presentation(for: CGSize(width: 400, height: 1000), maxWidth: image.bounds.width, kind: .normal).size.height
        XCTAssertEqual(image.bounds.height, ceil(expected), accuracy: 1)
    }

    private func waitFor(_ predicate: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(12)
        while !predicate(), Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(predicate())
    }

    private func host(_ page: DetailMarkdownPrototypeController) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UINavigationController(rootViewController: page)
        window.windowLevel = .normal + 1
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        return window
    }

    func testBackgroundWorkAndMainActorDeliveryThroughController() async throws {
        let cases: [(String, DetailFloorSource)] = [
            ("post-97", .init(html: "<p>旧正文</p>", visibleMarkdown: "正文 **主帖**")),
            ("reply-37", .init(html: "<p>旧回复</p>", visibleMarkdown: "回复 [站点](/member?t=test)")),
            ("web-92", .init(html: "<blockquote>网页提示</blockquote>", visibleMarkdown: nil))
        ]
        for (id, source) in cases {
            let parsed = expectation(description: "后台解析 " + id)
            let laidOut = expectation(description: "后台布局 " + id)
            // 让请求确实跨越挂起边界，再检查安装端收到的 ID、正文、宽度和版本。
            let release = DispatchSemaphore(value: 0)
            let renderer = DetailFloorRenderer { step, request in
                XCTAssertFalse(Thread.isMainThread)
                XCTAssertEqual(request.id, id)
                XCTAssertEqual(request.source, source)
                XCTAssertGreaterThan(request.appearance.width, 100)
                XCTAssertEqual(request.version, 1)
                switch step {
                case .parse:
                    parsed.fulfill()
                    XCTAssertEqual(release.wait(timeout: .now() + 8), .success)
                case .layout: laidOut.fulfill()
                }
            }
            let page = DetailMarkdownPrototypeController(id: id, source: source, renderer: renderer)
            let window = try host(page)
            await fulfillment(of: [parsed], timeout: 10)
            XCTAssertNil(page.installedRequest)
            release.signal()
            await fulfillment(of: [laidOut], timeout: 10)
            try await waitFor { page.installedRequest != nil }
            let request = try XCTUnwrap(page.installedRequest)
            XCTAssertEqual(request.id, id)
            XCTAssertEqual(request.source, source)
            XCTAssertEqual(request.version, 1)
            XCTAssertEqual(request.appearance.width, page.view.safeAreaLayoutGuide.layoutFrame.width - 32, accuracy: 1)
            if source.visibleMarkdown == nil {
                XCTAssertFalse(descendants(page.view, DetailRichTextView.self).isEmpty)
                XCTAssertTrue(descendants(page.view, DetailSelectableTextView.self).isEmpty)
                XCTAssertEqual(page.copyText, "网页提示")
            } else {
                XCTAssertEqual(page.copyText, source.visibleMarkdown)
                XCTAssertFalse(descendants(page.view, DetailSelectableTextView.self).isEmpty)
            }
            window.isHidden = true
        }
    }

    func testFallbackCopyPanelUsesVisibleMarkdownOrWebContent() async throws {
        let raw = "<iframe title='Markdown'></iframe>"
        for (markdown, expected) in [(Optional(raw), raw), (nil, "可见 :xhj003:")] {
            let html = "<p>可见 <img src='/static/image/sticker/xhj/003.png'></p>"
            let page = DetailMarkdownPrototypeController(id: "fallback", source: .init(html: html, visibleMarkdown: markdown))
            let window = try host(page)
            try await waitFor { page.installedRequest != nil }
            XCTAssertTrue(descendants(page.view, DetailSelectableTextView.self).isEmpty)
            XCTAssertFalse(descendants(page.view, DetailRichTextView.self).isEmpty)
            XCTAssertEqual(page.copyText, expected)
            let item = try XCTUnwrap(page.navigationItem.rightBarButtonItem)
            XCTAssertTrue(UIApplication.shared.sendAction(try XCTUnwrap(item.action), to: item.target, from: item, for: nil))
            let sheet = try XCTUnwrap(page.presentedViewController as? CommentCopySheetViewController)
            XCTAssertEqual(descendants(sheet.view, UITextView.self).first?.text, expected)
            window.isHidden = true
        }
    }

    func testSelectionAcrossTilesCopyStickerAndAccessibleLink() async throws {
        let url = try XCTUnwrap(NodeSeekStickerLibrary.urlsByToken["xhj003"])
        let emoji = "👨‍👩‍👧‍👦"
        let sample = String(repeating: "长中文段落与组合字符 e\u{301}。", count: 200)
        let raw = sample + "\n\n" + emoji + " :xhj003: [站点](https://www.nodeseek.com) שלום"
        let page = DetailMarkdownPrototypeController(id: "long", source: .init(html: "", visibleMarkdown: raw))
        let window = try host(page)
        defer { window.isHidden = true }
        try await waitFor { page.installedRequest != nil }
        let text = try XCTUnwrap(descendants(page.view, DetailSelectableTextView.self).first)
        XCTAssertTrue(text.interactions.contains { $0 is UITextInteraction })
        XCTAssertGreaterThan(text.snapshot.tiles.count, 1)
        let sticker = try XCTUnwrap(text.snapshot.stickers.first)
        XCTAssertEqual(sticker.url, url)
        XCTAssertEqual(sticker.rect.height, 65, accuracy: 0.01)
        let image = try XCTUnwrap(descendants(text, DetailInlineImageView.self).first)
        XCTAssertEqual(image.frame, sticker.rect)
        let cluster = try XCTUnwrap(text.snapshot.characters.first { (text.snapshot.string as NSString).substring(with: $0.range) == emoji })
        let emojiRange = try XCTUnwrap(text.characterRange(at: CGPoint(x: cluster.rect.midX, y: cluster.rect.midY)))
        XCTAssertEqual(text.text(in: emojiRange), emoji)
        text.selectAll(nil)
        let range = try XCTUnwrap(text.selectedTextRange)
        let rects = text.selectionRects(for: range)
        XCTAssertTrue(rects.contains { $0.writingDirection == .rightToLeft })
        XCTAssertGreaterThan(try XCTUnwrap(rects.last).rect.maxY - (rects.first?.rect.minY ?? 0), 384)
        text.copy(nil)
        XCTAssertEqual(UIPasteboard.general.string, sample + "\n\n" + emoji + " :xhj003: 站点 שלום")
        let accessibility = try XCTUnwrap(text.superview?.accessibilityElements as? [UIAccessibilityElement])
        XCTAssertTrue(accessibility.contains { $0.accessibilityLabel == "站点" && $0.accessibilityTraits.contains(.link) })
        XCTAssertEqual(text.snapshot.copyText(in: sticker.range), ":xhj003:")
        add(XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }).keeping("TextKit-long-selection"))

        window.overrideUserInterfaceStyle = .dark
        page.navigationController?.setOverrideTraitCollection(UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge), forChild: page)
        page.view.setNeedsLayout()
        page.view.layoutIfNeeded()
        try await waitFor { (page.installedRequest?.version ?? 0) >= 2 && page.installedRequest?.appearance.dark == true }
        let larger = try XCTUnwrap(descendants(page.view, DetailSelectableTextView.self).first)
        XCTAssertGreaterThan(larger.snapshot.size.height, text.snapshot.size.height)
        add(XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }).keeping("TextKit-dark-accessibility"))
    }

    func testActivatingRenderedLinkDeliversEncodedDestination() async throws {
        let raw = "https://example.invalid/a%2Fb中文?q=%23）"
        let page = DetailMarkdownPrototypeController(id: "link", source: .init(html: "", visibleMarkdown: raw))
        let window = try host(page)
        defer { window.isHidden = true }
        try await waitFor { page.installedRequest != nil }
        let rendered = try XCTUnwrap(descendants(page.view, DetailSelectableTextView.self).first)
        var destination: URL?
        let text = DetailSelectableTextView(snapshot: rendered.snapshot, scale: 2, onLink: { destination = $0 }, stickerSizeChanged: {})
        let container = text.accessibleContainer()
        let elements = try XCTUnwrap(container.accessibilityElements as? [UIAccessibilityElement])
        let link = try XCTUnwrap(elements.first { $0.accessibilityTraits.contains(.link) })
        XCTAssertEqual(link.accessibilityLabel, raw)
        XCTAssertTrue(link.accessibilityActivate())
        XCTAssertEqual(destination?.absoluteString, "https://example.invalid/a%2Fb%E4%B8%AD%E6%96%87?q=%23%EF%BC%89")

        let installed = try XCTUnwrap(rendered.superview?.accessibilityElements as? [UIAccessibilityElement])
        let installedLink = try XCTUnwrap(installed.first { $0.accessibilityTraits.contains(.link) })
        XCTAssertTrue(installedLink.accessibilityActivate())
        XCTAssertTrue(page.presentedViewController is SFSafariViewController)
    }

    func testTouchAtBottomOfTextBesideLeadingSticker() async throws {
        let raw = ":xhj003:链接\n下一行"
        let page = DetailMarkdownPrototypeController(id: "hit", source: .init(html: "", visibleMarkdown: raw))
        let window = try host(page)
        defer { window.isHidden = true }
        try await waitFor { page.installedRequest != nil }
        let view = try XCTUnwrap(descendants(page.view, DetailSelectableTextView.self).first)
        let snapshot = view.snapshot
        let box = try XCTUnwrap(snapshot.characters.first { (snapshot.string as NSString).substring(with: $0.range) == "链" })
        let sticker = try XCTUnwrap(snapshot.stickers.first)
        for y in [sticker.rect.maxY + 1, box.rect.maxY - 0.5] {
            let hit = try XCTUnwrap(view.characterRange(at: CGPoint(x: box.rect.midX, y: y)))
            XCTAssertEqual(view.text(in: hit), "链")
        }
        let next = try XCTUnwrap(snapshot.characters.first { (snapshot.string as NSString).substring(with: $0.range) == "下" })
        XCTAssertLessThanOrEqual(box.rect.maxY, next.rect.minY + 0.01)
        let hit = try XCTUnwrap(view.characterRange(at: CGPoint(x: next.rect.midX, y: next.rect.minY + 0.5)))
        XCTAssertEqual(view.text(in: hit), "下")
    }

    func testUnopenedTabDoesNotAllocateTextBitmaps() async throws {
        func residentBytes(_ blocks: [DetailLayoutBlock]) -> Int {
            blocks.reduce(0) { sum, block in
                switch block {
                case .text(let text): return sum + text.tiles.reduce(0) { $0 + $1.image.bytesPerRow * $1.image.height }
                case .quote(let nested): return sum + residentBytes(nested)
                case .tabs(_, let firstPage): return sum + residentBytes(firstPage)
                case .widget: return sum
                }
            }
        }
        func bytes(hidden: String) async throws -> Int {
            let markdown = ":::: tabs\n::: tab-item 一\n首页\n:::\n::: tab-item 二\n" + hidden + "\n:::\n::::"
            let request = DetailFloorRequest(id: "tabs", version: 1, source: .init(html: "", visibleMarkdown: markdown),
                appearance: .init(width: 280, pointSize: 17, scale: 2, dark: false), baseURL: NodeSeekSite.baseURL)
            var bytes: Int?
            await DetailFloorRenderer().start(request) { _, layout in
                if case .native(let blocks) = layout { bytes = residentBytes(blocks) }
            }.value
            return try XCTUnwrap(bytes)
        }
        let short = try await bytes(hidden: "短")
        let long = try await bytes(hidden: String(repeating: "很长的测评正文。", count: 300))
        XCTAssertGreaterThan(short, 0)
        XCTAssertEqual(long, short)
    }

    func testOnlyLastSelectedTabInstallsText() async throws {
        let long = String(repeating: "第二页很长。", count: 400)
        let markdown = ":::: tabs\n::: tab-item 一\n首页\n:::\n::: tab-item 二\n" + long + "\n:::\n::: tab-item 三\n末页\n:::\n::::"
        let page = DetailMarkdownPrototypeController(id: "switch", source: .init(html: "", visibleMarkdown: markdown))
        let window = try host(page)
        defer { window.isHidden = true }
        func visibleText() -> [String] { descendants(page.view, DetailSelectableTextView.self).map { $0.snapshot.string } }
        try await waitFor { visibleText() == ["首页"] }
        func select(_ index: Int) { tabButton(index, in: page.view)?.sendActions(for: .touchUpInside) }
        select(1)
        select(2)
        try await waitFor { visibleText() == ["末页"] }
        select(1)
        try await waitFor { visibleText() == [long] }
        select(0)
        try await waitFor { visibleText() == ["首页"] }
    }

    func testInlineGIFUsesMeasuredSizeAndPausesOutsideViewport() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gif")
        defer { try? FileManager.default.removeItem(at: url) }
        let output = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 2, nil))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        for color in [UIColor.systemBlue, .systemGreen] {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 20), format: format).image { context in
                color.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
            }
            CGImageDestinationAddImage(output, try XCTUnwrap(image.cgImage), [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(output))
        StickerAspectRatioCache.shared.recordLoadedSize(.init(width: 40, height: 20), for: url)
        let appearance = DetailTextAppearance(width: 300, pointSize: 17, scale: 2, dark: false)
        let segment = DetailTextSegment(runs: [.text("左", [], nil), .sticker(token: ":demo:", url: url), .text("右", [], nil)], pointSize: 17)
        let snapshot = try await Task.detached {
            try DetailTextTypesetter.layout([segment], appearance: appearance, width: 300)
        }.value
        let sticker = try XCTUnwrap(snapshot.stickers.first)
        XCTAssertEqual(sticker.rect.size, CGSize(width: 130, height: 65))
        XCTAssertGreaterThan(sticker.rect.minX, 0)
        XCTAssertLessThanOrEqual(sticker.rect.maxY, snapshot.size.height)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let viewport = UIView(frame: CGRect(x: 0, y: 100, width: 300, height: 100))
        host.view.addSubview(viewport)
        let text = DetailSelectableTextView(snapshot: snapshot, scale: 2, onLink: { _ in }, stickerSizeChanged: {})
        viewport.addSubview(text)
        text.updatePlayback(in: viewport)
        let image = try XCTUnwrap(descendants(text, DetailInlineImageView.self).first)
        try await waitFor { image.isAnimating }
        text.frame.origin.y = 110
        text.updatePlayback(in: viewport)
        XCTAssertFalse(image.isAnimating)
        text.frame.origin.y = 0
        text.updatePlayback(in: viewport)
        XCTAssertTrue(image.isAnimating)
    }

    func testReviewTabsAndCapturedVoteState() async throws {
        struct Page: Decodable {
            struct Item: Decodable { let main: Bool; let markdown: String }
            let path: String
            let items: [Item]
        }
        func fixture(_ name: String) throws -> Data {
            try Data(contentsOf: XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json")))
        }
        let pages = try JSONDecoder().decode([Page].self, from: fixture("post-markdown-pages"))
        let raw = try XCTUnwrap(pages.first { $0.path == "/post-1067722-1" }?.items.first { $0.main }?.markdown)
        let review = DetailMarkdownPrototypeController(id: "review", source: .init(html: "", visibleMarkdown: raw))
        let window = try host(review)
        defer { window.isHidden = true }
        try await waitFor { review.installedRequest != nil }
        XCTAssertEqual((0..<4).compactMap { tabButton($0, in: review.view)?.accessibilityLabel }, ["💻基本信息", "🎬IP质量", "🌐网络质量", "📍回程路由"])
        var terminalPages = 0
        for index in 0..<4 {
            tabButton(index, in: review.view)?.sendActions(for: .touchUpInside)
            // 切换后旧页留到新页排好再替换；等待当前页的终端出现。
            try await waitFor { self.descendants(review.view, DetailTerminalView.self).count <= 1 }
            if index < 2 {
                try await waitFor { !self.descendants(review.view, DetailTerminalView.self).isEmpty }
                let terminal = try XCTUnwrap(descendants(review.view, DetailTerminalView.self).first)
                review.view.layoutIfNeeded()
                try await waitFor { terminal.snapshot != nil }
                let pages = try XCTUnwrap(terminal.snapshot?.pages)
                XCTAssertFalse(pages.isEmpty)
                XCTAssertTrue(pages.allSatisfy { $0.width > 0 && $0.height > 0 && FileManager.default.fileExists(atPath: $0.url.path) })
                terminalPages += 1
            }
        }
        XCTAssertEqual(terminalPages, 2)

        struct Response: Decodable { let vote: NodeSeekVote }
        let service = VoteTestService()
        service.vote = try JSONDecoder().decode(Response.self, from: fixture("detail-replay-vote")).vote
        let vote = DetailMarkdownPrototypeController(id: "vote", source: .init(html: "", visibleMarkdown: "> 前\n> nsapp://vote?id=3108\n> 后"), voteService: service)
        window.rootViewController = vote
        window.layoutIfNeeded()
        try await waitFor { self.descendants(vote.view, DetailVoteView.self).first?.model.vote != nil }
        XCTAssertEqual(descendants(vote.view, DetailVoteView.self).first?.model.vote?.items, service.vote.items)
        XCTAssertEqual(descendants(vote.view, DetailSelectableTextView.self).map { $0.snapshot.string.trimmingCharacters(in: .whitespacesAndNewlines) }, ["前", "后"])
        XCTAssertTrue(service.submitted.isEmpty)
    }
}

private extension XCTAttachment {
    func keeping(_ name: String) -> XCTAttachment {
        self.name = name
        lifetime = .keepAlways
        return self
    }
}
#endif
