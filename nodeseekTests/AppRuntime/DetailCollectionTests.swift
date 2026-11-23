import SafariServices
import UIKit
import XCTest
@testable import nodeseek

@MainActor
final class DetailCollectionTests: XCTestCase {
    func testReusedFloorActionUsesOnlyCurrentCountAndHandler() throws {
        let cell = DetailFloorListCell(frame: CGRect(x: 0, y: 0, width: 390, height: 120))
        let appearance = DetailTextAppearance(width: 358, pointSize: 16, scale: 3, dark: false)
        func bind(_ id: String) {
            cell.bind(.init(id: id, version: 1, source: .init(html: "", visibleMarkdown: id),
                            appearance: appearance, baseURL: URL(string: "https://www.nodeseek.com")!))
        }
        var calls: [String] = []
        bind("a")
        cell.addAction("like", symbol: "hand.thumbsup.fill", count: 19, selected: true) { calls.append("a") }
        let first = try XCTUnwrap(allButtons(cell.contentView).first)
        cell.prepareForReuse()
        bind("b")
        cell.addAction("like", symbol: "hand.thumbsup", count: 0) { calls.append("b") }
        let second = try XCTUnwrap(allButtons(cell.contentView).first { !$0.isHidden })
        XCTAssertTrue(first === second)
        XCTAssertNil(second.title(for: .normal))
        XCTAssertEqual(second.accessibilityValue, "0")
        second.sendActions(for: .touchUpInside)
        XCTAssertEqual(calls, ["b"])
    }

    func testFloorActionIconsKeepTextureSymbolSize() throws {
        let cell = DetailFloorListCell(frame: CGRect(x: 0, y: 0, width: 390, height: 120))
        cell.bind(.init(id: "a", version: 1, source: .init(html: "", visibleMarkdown: "a"),
                        appearance: .init(width: 358, pointSize: 16, scale: 3, dark: false), baseURL: NodeSeekSite.baseURL))
        cell.addAction("like", symbol: "hand.thumbsup", count: 2) {}
        cell.contentView.layoutIfNeeded()
        let button = try XCTUnwrap(allButtons(cell.contentView).first { !$0.isHidden })
        let imageView = try XCTUnwrap(button.imageView)
        // 旧版按 14pt 符号原样绘制；按钮不能再按自身样式放大图标。
        let config = UIImage.SymbolConfiguration(pointSize: PostDetailContentLayout.reactionSymbolPointSize, weight: .regular)
        let expected = try XCTUnwrap(UIImage(systemName: "hand.thumbsup", withConfiguration: config)).size
        XCTAssertEqual(imageView.bounds.width, expected.width, accuracy: 0.5)
        XCTAssertEqual(imageView.bounds.height, expected.height, accuracy: 0.5)
    }

    func testFloorMenuAndTextSelectionHaveSeparateHitAreas() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let page = PostDetailViewController(presenter: SpyPostDetailPresenter(), usesTextKitList: true)
        window.rootViewController = page
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        let raw = "/~99423cRA5z~:/ [链](https://example.com)！"
        let visible = "/~99423cRA5z~:/ 链！"
        let comment = Comment(id: "2", anchorID: "1", authorName: "Alice", avatarURL: nil, floorText: "#1",
                              createdAtText: nil, contentHTML: "<p>\(visible)</p>", markdown: raw, hasVisibleMarkdown: true)
        page.render(detail: PostDetail(id: "1", title: "主题", authorName: "Bob", avatarURL: nil,
                                       metadataText: nil, contentHTML: "主帖", visibleMarkdown: "主帖", comments: [comment]))
        let list = try XCTUnwrap(page.collectionList?.view)
        window.layoutIfNeeded()
        let path = try XCTUnwrap(page.indexPathForCurrentPageAnchor("1"))
        let cell = try await waitForCell(list, at: path)
        for _ in 0..<100 where !cell.contentInstalled { try await Task.sleep(nanoseconds: 10_000_000) }
        window.layoutIfNeeded()
        let text = try XCTUnwrap(cell.body.arrangedSubviews.first?.subviews.first as? DetailSelectableTextView)
        let last = try XCTUnwrap(text.snapshot.characters.last)
        func hit(_ x: CGFloat) -> UIView? {
            cell.hitTest(text.convert(CGPoint(x: x, y: last.rect.midY), to: cell), with: nil)
        }
        XCTAssertTrue(hit(last.rect.maxX + 2) === text)
        let space = try XCTUnwrap(text.snapshot.characters.first { (text.snapshot.string as NSString).substring(with: $0.range) == " " })
        XCTAssertTrue(hit(space.rect.midX) === text)
        let blank = try XCTUnwrap(hit(text.bounds.maxX - 8))
        let menu = try XCTUnwrap(blank.interactions.compactMap { $0 as? UIContextMenuInteraction }.first)
        let delegate = try XCTUnwrap(menu.delegate)
        let config = try XCTUnwrap(delegate.contextMenuInteraction(menu, configurationForMenuAtLocation: .zero))
        func previews() -> [UITargetedPreview?] {
            if #available(iOS 16.0, *) {
                return [delegate.contextMenuInteraction?(menu, configuration: config, highlightPreviewForItemWithIdentifier: config.identifier) ?? nil,
                        delegate.contextMenuInteraction?(menu, configuration: config, dismissalPreviewForItemWithIdentifier: config.identifier) ?? nil]
            }
            return [delegate.contextMenuInteraction?(menu, previewForHighlightingMenuWithConfiguration: config) ?? nil,
                    delegate.contextMenuInteraction?(menu, previewForDismissingMenuWithConfiguration: config) ?? nil]
        }
        XCTAssertTrue(previews().allSatisfy { $0?.view === cell.contentView }, "展开、收起都应使用有正文的完整楼层")
        let floor = try XCTUnwrap(cell.contentView.subviews.flatMap(allLabels).first { $0.text == "#1" })
        let floorPoint = floor.convert(CGPoint(x: floor.bounds.midX, y: floor.bounds.midY), to: cell)
        XCTAssertTrue(cell.hitTest(floorPoint, with: nil) === blank)
        let copy = try XCTUnwrap(floor.accessibilityCustomActions?.first { $0.name == DetailListStrings.text("copy") })
        let reply = try XCTUnwrap(cell.contentView.subviews.flatMap(allButtons).first { $0.accessibilityLabel == DetailListStrings.text("reply-comment") })
        let replyPoint = reply.convert(CGPoint(x: reply.bounds.midX, y: reply.bounds.midY), to: cell)
        XCTAssertTrue(cell.hitTest(replyPoint, with: nil) === reply)
        let footerBlank = reply.convert(CGPoint(x: 0, y: reply.bounds.midY), to: cell)
        XCTAssertTrue(cell.hitTest(CGPoint(x: cell.stack.frame.minX + 2, y: footerBlank.y), with: nil) === blank)
        text.selectAll(nil)
        XCTAssertTrue(hit(text.bounds.maxX - 8) === text)
        XCTAssertEqual(text.text(in: try XCTUnwrap(text.selectedTextRange)), visible)
        cell.prepareForReuse()
        XCTAssertTrue(previews().allSatisfy { $0 == nil })
        XCTAssertEqual(copy.actionHandler?(copy), false)
    }

    func testFloorFooterAndMenuMatchTexture() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let page = PostDetailViewController(presenter: SpyPostDetailPresenter(), usesTextKitList: true)
        window.rootViewController = page
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        let other = Comment(id: "2", anchorID: "1", authorName: "Alice", avatarURL: nil, floorText: "#1",
                            createdAtText: nil, contentHTML: "<p>回复</p>", markdown: "回复", hasVisibleMarkdown: true)
        let own = Comment(id: "3", anchorID: "2", authorName: "Me", avatarURL: nil, floorText: "#2",
                          createdAtText: nil, contentHTML: "<p>自己</p>", isOwnComment: true, markdown: "自己", hasVisibleMarkdown: true)
        page.render(detail: PostDetail(id: "1", title: "主题", authorName: "Bob", avatarURL: nil,
                                       metadataText: nil, contentHTML: "主帖", visibleMarkdown: "主帖", comments: [other, own]))
        let list = try XCTUnwrap(page.collectionList?.view)
        window.layoutIfNeeded()
        _ = try await waitForCell(list, at: try XCTUnwrap(page.indexPathForCurrentPageAnchor("1")))
        func cell(_ anchor: String) throws -> DetailFloorListCell {
            try XCTUnwrap(list.cellForItem(at: try XCTUnwrap(page.indexPathForCurrentPageAnchor(anchor))) as? DetailFloorListCell)
        }
        func labels(_ cell: DetailFloorListCell) -> [String] {
            cell.contentView.subviews.flatMap(allButtons).filter { !$0.isHidden }.compactMap(\.accessibilityLabel)
        }
        // 与旧版一致：回复楼层底栏有回复、引用，本人楼层另有编辑。
        let otherCell = try cell("1"), ownCell = try cell("2")
        XCTAssertTrue(labels(otherCell).contains(DetailListStrings.text("reply-comment")))
        XCTAssertTrue(labels(otherCell).contains(DetailListStrings.text("quote-comment")))
        XCTAssertFalse(labels(otherCell).contains(DetailListStrings.text("edit-comment")))
        XCTAssertTrue(labels(ownCell).contains(DetailListStrings.text("edit-comment")))
        XCTAssertNotNil(otherCell.contentView.subviews.flatMap(allButtons).first { $0.accessibilityIdentifier == "post-detail-quote-comment-1-2" })
        // 长按菜单：复制、投放鸡腿（非本人）、只看 TA，本人可编辑；均带图标。
        XCTAssertEqual(otherCell.floorActions.map(\.title), ["copy", "chicken", "author-them"].map(DetailListStrings.text))
        XCTAssertEqual(ownCell.floorActions.map(\.title), ["copy", "author-them", "edit"].map(DetailListStrings.text))
        XCTAssertTrue((otherCell.floorActions + ownCell.floorActions).allSatisfy { $0.image != nil })
        let header = try cell("0")
        XCTAssertEqual(header.floorActions.last?.title, DetailListStrings.text("author-poster"))
    }

    func testCopyActionWritesThroughPageAndShowsToast() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        var copied: [String] = []
        let page = PostDetailViewController(presenter: SpyPostDetailPresenter(), usesTextKitList: true, pasteboardStringWriter: { copied.append($0) })
        window.rootViewController = page
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        let comment = Comment(id: "2", anchorID: "1", authorName: "Alice", avatarURL: nil, floorText: "#1",
                              createdAtText: nil, contentHTML: "<p>回复</p>", markdown: "回复", hasVisibleMarkdown: true)
        page.render(detail: PostDetail(id: "1", title: "主题", authorName: "Bob", avatarURL: nil,
                                       metadataText: nil, contentHTML: "主帖", visibleMarkdown: "主帖", comments: [comment]))
        window.layoutIfNeeded()
        let list = try XCTUnwrap(page.collectionList?.view)
        let cell = try await waitForCell(list, at: try XCTUnwrap(page.indexPathForCurrentPageAnchor("1")))
        XCTAssertTrue(try XCTUnwrap(cell.floorActions.first { $0.title == DetailListStrings.text("copy") }).perform())
        let sheet = try XCTUnwrap(page.presentedViewController as? CommentCopySheetViewController)
        sheet.copySelection()
        // 与旧版一致：复制后在详情页提示「已复制」。
        XCTAssertEqual(copied, ["回复"])
        XCTAssertTrue(allLabels(page.view).contains { $0.text == DetailListStrings.text("copied") })
    }

    func testAuthorNameOpensProfilePreviewLikeAvatar() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let page = PostDetailViewController(presenter: SpyPostDetailPresenter(), usesTextKitList: true)
        window.rootViewController = page
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        let comment = Comment(id: "2", anchorID: "1", authorName: "Alice", avatarURL: nil,
                              authorProfileURL: URL(string: "https://www.nodeseek.com/space/1"), floorText: "#1",
                              createdAtText: nil, contentHTML: "<p>回复</p>", markdown: "回复", hasVisibleMarkdown: true)
        page.render(detail: PostDetail(id: "1", title: "主题", authorName: "Bob", avatarURL: nil,
                                       metadataText: nil, contentHTML: "主帖", visibleMarkdown: "主帖", comments: [comment]))
        window.layoutIfNeeded()
        let list = try XCTUnwrap(page.collectionList?.view)
        let cell = try await waitForCell(list, at: try XCTUnwrap(page.indexPathForCurrentPageAnchor("1")))
        let name = try XCTUnwrap(allLabels(cell.contentView).first { $0.text == "Alice" })
        // 与旧版一致：长按名字和头像一样弹出个人页预览，读屏说明可打开主页。
        let menu = try XCTUnwrap(name.interactions.compactMap { $0 as? UIContextMenuInteraction }.first)
        XCTAssertNotNil(menu.delegate?.contextMenuInteraction(menu, configurationForMenuAtLocation: .zero))
        XCTAssertEqual(name.accessibilityLabel, String(format: DetailListStrings.text("view-profile"), "Alice"))
        XCTAssertTrue(name.accessibilityTraits.contains(.button))
        // E2E 按旧版标识定位作者名和头像。
        XCTAssertEqual(name.accessibilityIdentifier, "comment-author-name")
        XCTAssertTrue(allViews(cell.contentView).contains { $0.accessibilityIdentifier == "comment-author-avatar" })
    }

    func testPostCountsUseCompactUnitsLikeTexture() {
        let cell = DetailFloorListCell(frame: CGRect(x: 0, y: 0, width: 360, height: 200))
        // 与旧版一致：主楼计数过万显示「1.2万」，回复楼层保持原数字。
        cell.compactCounts = true
        cell.addAction("favorite", symbol: "star", count: 12_345) {}
        cell.compactCounts = false
        cell.addAction("like", symbol: "hand.thumbsup", count: 12_345) {}
        let titles = allButtons(cell.contentView).compactMap { $0.title(for: .normal) }
        XCTAssertEqual(titles, [" 1.2万", " 12345"])
    }

    func testManyAuthorBadgesWrapInsteadOfOverflowing() throws {
        let cell = DetailFloorListCell(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        let appearance = DetailTextAppearance(width: 250, pointSize: 17, scale: 2, dark: false)
        cell.bind(.init(id: "badges", version: 1, source: .init(html: "", visibleMarkdown: "正文"), appearance: appearance, baseURL: NodeSeekSite.baseURL))
        let badges = ["禁言中", "社区贡献者", "长期活跃用户", "资深测评作者"]
        cell.configureHeader(title: nil, requiredLevel: nil, name: "Alice", isPoster: true, badges: badges, time: "1 小时前", floor: "#12")
        cell.layoutIfNeeded()
        let labels = allLabels(cell.contentView).filter { $0 is AuthorBadgeLabel && !$0.isHidden && $0.window == nil && $0.superview != nil }
        XCTAssertEqual(labels.compactMap(\.text), badges)
        // 与旧版一致：放不下的标签换到下一行，每个标签完整显示且不超出楼层宽度。
        let frames = labels.map { $0.convert($0.bounds, to: cell.contentView) }
        XCTAssertGreaterThan(Set(frames.map { $0.minY.rounded() }).count, 1)
        XCTAssertTrue(frames.allSatisfy { $0.maxX <= cell.contentView.bounds.maxX + 0.5 })
        // iOS 17 的标签固有宽度带小数，按原值比较。
        XCTAssertTrue(zip(labels, frames).allSatisfy { $1.width >= $0.intrinsicContentSize.width - 0.5 })
    }

    func testMainPostBadgesWrapWithinHeaderBesideAvatar() throws {
        let inset = PostDetailContentLayout.horizontalInset
        // 主楼正文不缩进，但作者栏左侧仍有头像；逐个加标签，覆盖第一行刚好放满的情况。
        let appearance = DetailTextAppearance(width: 402 - 2 * inset, pointSize: 17, scale: 3, dark: false)
        for count in 1...12 {
            let cell = DetailFloorListCell(frame: CGRect(x: 0, y: 0, width: 402, height: 400))
            cell.bind(.init(id: "post", version: 1, source: .init(html: "", visibleMarkdown: "正文"), appearance: appearance, baseURL: NodeSeekSite.baseURL))
            let badges = (1...count).map { "标签\($0)" }
            cell.configureHeader(title: "主题", requiredLevel: nil, name: "Bob", badges: badges, time: "1 小时前", floor: nil)
            cell.layoutIfNeeded()
            let labels = allLabels(cell.contentView).filter { $0 is AuthorBadgeLabel && !$0.isHidden && $0.superview != nil }
            XCTAssertEqual(labels.compactMap(\.text), badges)
            let limit = cell.contentView.bounds.maxX - inset + 0.5
            XCTAssertTrue(labels.allSatisfy { $0.convert($0.bounds, to: cell.contentView).maxX <= limit }, "\(count) 个标签超出")
            XCTAssertTrue(labels.allSatisfy { $0.bounds.width >= $0.intrinsicContentSize.width - 0.5 }, "\(count) 个标签被压缩")
            XCTAssertGreaterThanOrEqual(cell.metadata.bounds.width, cell.metadata.intrinsicContentSize.width - 0.5, "\(count) 个标签挤压作者名")
        }
    }

    func testAuthorFilterBannerHasClearButtonLikeTexture() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let page = PostDetailViewController(presenter: SpyPostDetailPresenter(), usesTextKitList: true)
        window.rootViewController = page
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        let comment = Comment(id: "2", anchorID: "1", authorName: "Bob", avatarURL: nil, floorText: "#1",
                              createdAtText: nil, contentHTML: "<p>回复</p>", markdown: "回复", hasVisibleMarkdown: true)
        page.render(detail: PostDetail(id: "1", title: "主题", authorName: "Bob", avatarURL: nil,
                                       metadataText: nil, contentHTML: "主帖", visibleMarkdown: "主帖", comments: [comment]))
        page.toggleAuthorFilter(.poster(of: try XCTUnwrap(page.currentHeaderContent)), focusingCommentID: nil)
        window.layoutIfNeeded()
        let list = try XCTUnwrap(page.collectionList?.view)
        list.layoutIfNeeded()
        // 与旧版一致：筛选条有说明文字和独立的「查看全部」按钮。
        let banner = try await waitForCell(list, as: DetailAuthorFilterBannerCell.self)
        XCTAssertTrue(allLabels(banner).contains { $0.text == page.authorFilterBannerText })
        XCTAssertGreaterThanOrEqual(banner.bounds.height, 34 + 20 + 8 - 0.5)
        let clear = try XCTUnwrap(allButtons(banner).first { $0.accessibilityIdentifier == "detail-author-filter-clear" })
        clear.sendActions(for: .touchUpInside)
        XCTAssertNil(page.authorFilter)
    }

    /// 主楼量出高度前回复不建 cell，取回复楼层要等主楼排好的下一轮布局。
    private func waitForCell<T: UICollectionViewCell>(_ list: UICollectionView, as type: T.Type = DetailFloorListCell.self,
                                                       where match: (T) -> Bool = { _ in true }) async throws -> T {
        for _ in 0..<100 {
            list.layoutIfNeeded()
            if let cell = list.visibleCells.compactMap({ $0 as? T }).first(where: match) { return cell }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        return try XCTUnwrap(list.visibleCells.compactMap { $0 as? T }.first(where: match))
    }

    private func waitForCell(_ list: UICollectionView, at path: IndexPath) async throws -> DetailFloorListCell {
        try await waitForCell(list) { list.indexPath(for: $0) == path }
    }

    private func allButtons(_ root: UIView) -> [UIButton] {
        (root as? UIButton).map { [$0] } ?? root.subviews.flatMap(allButtons)
    }

    private func allSubviews(_ root: UIView) -> [UIView] {
        root.subviews + root.subviews.flatMap(allSubviews)
    }

    private func allLabels(_ root: UIView) -> [UILabel] {
        (root as? UILabel).map { [$0] } ?? root.subviews.flatMap(allLabels)
    }

    func testParagraphGapKeepsCopyBreaksAtLargeType() throws {
        let size: CGFloat = 25
        let appearance = DetailTextAppearance(width: 360, pointSize: size, scale: 2, dark: false)
        func layout(_ paragraphs: [String]) throws -> DetailTextSnapshot {
            try DetailTextTypesetter.layout(paragraphs.map { .init(runs: [.text($0, [], nil)], pointSize: size) },
                                           appearance: appearance, width: appearance.width)
        }
        let paragraphs = try layout(["第一段", "第二段"])
        let lines = try layout(["第一段\n第二段"])
        let gap = paragraphs.size.height - lines.size.height
        XCTAssertGreaterThan(gap, 0)
        XCTAssertLessThanOrEqual(gap, 12)
        XCTAssertEqual(paragraphs.copyText(in: NSRange(location: 0, length: paragraphs.string.utf16.count)), "第一段\n\n第二段")
    }

    func testWrappedBodyKeepsReadingLineSpacing() throws {
        let pointSize: CGFloat = 25
        let appearance = DetailTextAppearance(width: 220, pointSize: pointSize, scale: 2, dark: false)
        let text = "科技股从历史高点回撤幅度 TOP 20：CoreWeave（CRWV）"
        let segment = DetailTextSegment(runs: [.text(text, [], nil)], pointSize: pointSize)
        let snapshot = try DetailTextTypesetter.layout([segment], appearance: appearance, width: 220)

        // 旧版按 CSS line-height 1.42 排版，大字号下行距随字号放大，中西混排也保持同一行距。
        let distance = snapshot.lines[1].maxY - snapshot.lines[0].maxY
        XCTAssertEqual(distance, ceil(pointSize * 1.42), accuracy: 0.5)
    }

    func testBlockSpacingMatchesTextureStyleSheet() throws {
        let appearance = DetailTextAppearance(width: 320, pointSize: 17, scale: 2, dark: false)
        func bottom(of word: String, in snapshot: DetailTextSnapshot) throws -> CGFloat {
            let offset = (snapshot.string as NSString).range(of: word).location
            let index = try XCTUnwrap(snapshot.characters.firstIndex { $0.range.location == offset })
            return try XCTUnwrap(snapshot.lines.first { $0.characters.contains(index) }).maxY
        }
        let body = DetailTextSegment(runs: [.text("正文", [], nil)], pointSize: 17)
        let heading = DetailTextSegment(runs: [.text("标题", [.bold], nil)], pointSize: 22, isHeading: true)
        let item = DetailTextSegment(runs: [.text("• 甲", [], nil)], pointSize: 17, isListItem: true)
        var last = DetailTextSegment(runs: [.text("• 乙", [], nil)], pointSize: 17, isListItem: true)
        last.endsList = true
        let after = DetailTextSegment(runs: [.text("结尾", [], nil)], pointSize: 17)
        let snapshot = try DetailTextTypesetter.layout([body, heading, item, last, after], appearance: appearance, width: 320)
        // 行高取 ceil(字号 × 1.42)，标题 ×1.28；段后 12、标题前 18 后 8、列表项之间 6。
        let bodyLine = ceil(17 * 1.42), headingLine = ceil(22 * 1.28)
        XCTAssertEqual(try bottom(of: "标题", in: snapshot) - bottom(of: "正文", in: snapshot), 12 + 18 + headingLine, accuracy: 1)
        XCTAssertEqual(try bottom(of: "甲", in: snapshot) - bottom(of: "标题", in: snapshot), 8 + bodyLine, accuracy: 1)
        XCTAssertEqual(try bottom(of: "乙", in: snapshot) - bottom(of: "甲", in: snapshot), 6 + bodyLine, accuracy: 1)
        XCTAssertEqual(try bottom(of: "结尾", in: snapshot) - bottom(of: "乙", in: snapshot), 12 + bodyLine, accuracy: 1)
    }

    func testReuseRejectsLateFloorAndPreviousAppearance() throws {
        let cell = DetailFloorListCell(frame: CGRect(x: 0, y: 0, width: 360, height: 200))
        let appearance = DetailTextAppearance(width: 328, pointSize: 17, scale: 2, dark: false)
        func request(_ id: String, _ version: Int, _ text: String) -> DetailFloorRequest {
            .init(id: id, version: version, source: .init(html: "", visibleMarkdown: text), appearance: appearance, baseURL: NodeSeekSite.baseURL)
        }
        func result(_ text: String, _ link: String) throws -> DetailFloorLayout {
            let segment = DetailTextSegment(runs: [.text(text, [], URL(string: link))], pointSize: 17)
            return .native([.text(try DetailTextTypesetter.layout([segment], appearance: appearance, width: 328))])
        }
        let first = request("post", 1, "A"), second = request("reply", 2, "B")
        cell.bind(first)
        let late = cell.receiver.install
        cell.prepareForReuse()
        cell.bind(second)
        cell.receiver.install(second, try result("B", "https://example.com/b"))
        let text = try XCTUnwrap(cell.body.arrangedSubviews.first?.subviews.first as? DetailSelectableTextView)
        text.selectAll(nil)
        late(first, try result("A", "https://example.com/a"))
        XCTAssertTrue(cell.body.arrangedSubviews.first?.subviews.first === text)
        XCTAssertEqual(text.snapshot.characters.first?.link?.path, "/b")
        XCTAssertEqual(text.text(in: try XCTUnwrap(text.selectedTextRange)), "B")
        XCTAssertEqual(cell.copyText, "B")
        let resized = DetailFloorRequest(id: "reply", version: 3, source: second.source, appearance: .init(width: 240, pointSize: 25, scale: 2, dark: true), baseURL: second.baseURL)
        cell.bind(resized)
        late(second, try result("old", "https://example.com/old"))
        XCTAssertTrue(cell.body.arrangedSubviews.isEmpty)
        weak var released: DetailFloorListCell?
        var delivery: DetailFloorRenderer.Delivery?
        autoreleasepool {
            let transient = DetailFloorListCell(frame: .zero)
            released = transient
            transient.bind(first)
            delivery = transient.receiver.install
        }
        XCTAssertNil(released)
        delivery?(first, .native([]))
    }

    func testLeavingDetailReleasesPageWithOutstandingDelivery() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let navigation = UINavigationController(rootViewController: UIViewController())
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }

        weak var released: PostDetailViewController?
        let (request, deliver): (DetailFloorRequest, DetailFloorRenderer.Delivery) = try autoreleasepool {
            let page = PostDetailViewController(presenter: SpyPostDetailPresenter(), usesTextKitList: true)
            released = page
            navigation.pushViewController(page, animated: false)
            page.render(detail: PostDetail(id: "12", title: "退出", authorName: "Alice", avatarURL: nil,
                                           metadataText: nil, contentHTML: "正文", visibleMarkdown: "正文", comments: []))
            window.layoutIfNeeded()
            let list = try XCTUnwrap(page.collectionList?.view)
            list.layoutIfNeeded()
            let cell = try XCTUnwrap(list.cellForItem(at: IndexPath(item: 0, section: 0)) as? DetailFloorListCell)
            let request = try XCTUnwrap(cell.request)
            let deliver: DetailFloorRenderer.Delivery = cell.receiver.install
            navigation.popViewController(animated: false)
            return (request, deliver)
        }
        for _ in 0..<60 where released != nil { try await Task.sleep(nanoseconds: 16_000_000) }
        XCTAssertNil(released)
        deliver(request, .native([]))
    }

    private func makePagedDetail(_ range: ClosedRange<Int>, pageNumber: Int, next: Int?) -> PostDetail {
        let replies = range.map { number in
            Comment(id: String(number), anchorID: String(number), authorName: "Alice", avatarURL: nil,
                    floorText: "#\(number)", createdAtText: nil, contentHTML: "短回复",
                    markdown: "短回复", hasVisibleMarkdown: true)
        }
        return PostDetail(id: "10", title: "分页", authorName: "Bob", avatarURL: nil, metadataText: nil,
                          contentHTML: "主楼", visibleMarkdown: "主楼", comments: replies, page: pageNumber,
                          pagination: .init(currentPage: pageNumber, items: [], previousPage: nil, nextPage: next))
    }

    private func pagingWindow(for page: UIViewController) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = page
        window.makeKeyAndVisible()
        return window
    }

    func testPaginationRequestsNextPageWithinTwoScreensAndKeepsVisibleFloor() async throws {
        let spy = SpyPostDetailPresenter()
        let page = PostDetailViewController(presenter: spy, usesTextKitList: true)
        let window = try pagingWindow(for: page)
        defer { window.isHidden = true; window.rootViewController = nil }

        page.render(detail: makePagedDetail(1...45, pageNumber: 1, next: 2))
        let list = try XCTUnwrap(page.collectionList?.view)
        window.layoutIfNeeded()
        func scroll(remainingScreens: CGFloat) {
            let y = list.contentSize.height + list.adjustedContentInset.bottom - list.bounds.height * (1 + remainingScreens)
            list.setContentOffset(CGPoint(x: 0, y: y), animated: false)
            list.layoutIfNeeded()
        }
        scroll(remainingScreens: 3)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(spy.didApproachCommentEndCount, 0)
        scroll(remainingScreens: 1.5)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertGreaterThan(list.numberOfItems(inSection: 0) - 1 - (list.indexPathsForVisibleItems.map(\.item).max() ?? 0), 3)
        XCTAssertEqual(spy.didApproachCommentEndCount, 1)
        scroll(remainingScreens: 1.4)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(spy.didApproachCommentEndCount, 1)
        let visible = try XCTUnwrap(list.indexPathsForVisibleItems.sorted().first)
        let anchor = try XCTUnwrap(list.cellForItem(at: visible) as? DetailFloorListCell)
        let binding = try XCTUnwrap(anchor.request)
        let top = anchor.convert(anchor.bounds, to: window).minY
        page.appendCommentPage(detail: makePagedDetail(46...65, pageNumber: 2, next: nil))
        page.hideLoadingMoreComments()
        list.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(anchor.request, binding)
        XCTAssertEqual(anchor.convert(anchor.bounds, to: window).minY, top, accuracy: 1)
        XCTAssertEqual(page.comments.count, 65)
        scroll(remainingScreens: 0)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(spy.didApproachCommentEndCount, 1)
    }

    func testSlowAppendKeepsBottomBoundaryUntilBounceReturns() async throws {
        let page = PostDetailViewController(presenter: SpyPostDetailPresenter(), usesTextKitList: true)
        let window = try pagingWindow(for: page)
        defer { window.isHidden = true; window.rootViewController = nil }
        page.render(detail: makePagedDetail(1...20, pageNumber: 1, next: 2))
        let list = try XCTUnwrap(page.collectionList?.view)
        window.layoutIfNeeded()
        func bottom() -> CGFloat {
            list.contentSize.height - list.bounds.height + list.adjustedContentInset.bottom
        }
        list.setContentOffset(CGPoint(x: 0, y: bottom()), animated: false)
        try await Task.sleep(nanoseconds: 250_000_000)
        list.layoutIfNeeded()
        let oldBottom = bottom()
        let oldCount = list.numberOfItems(inSection: 0)
        list.delegate?.scrollViewWillBeginDragging?(list)
        list.contentOffset.y = oldBottom + 65
        XCTAssertGreaterThan(list.contentOffset.y, oldBottom + 60)

        page.appendCommentPage(detail: makePagedDetail(21...30, pageNumber: 2, next: nil))
        list.layoutIfNeeded()
        XCTAssertEqual(list.numberOfItems(inSection: 0), oldCount)
        XCTAssertEqual(bottom(), oldBottom, accuracy: 1)
        list.delegate?.scrollViewDidEndDragging?(list, willDecelerate: true)
        XCTAssertEqual(list.numberOfItems(inSection: 0), oldCount)

        list.contentOffset.y = oldBottom
        list.delegate?.scrollViewDidEndDecelerating?(list)
        list.layoutIfNeeded()
        XCTAssertEqual(list.numberOfItems(inSection: 0), oldCount + 10)
        XCTAssertEqual(list.contentOffset.y, oldBottom, accuracy: 1)
        XCTAssertTrue(list.bounces)
    }

    func testFailedPrefetchWaitsForNextDragBeforeRetry() async throws {
        let spy = SpyPostDetailPresenter()
        let page = PostDetailViewController(presenter: spy, usesTextKitList: true)
        let window = try pagingWindow(for: page)
        defer { window.isHidden = true; window.rootViewController = nil }
        page.render(detail: makePagedDetail(1...20, pageNumber: 1, next: 2))
        let list = try XCTUnwrap(page.collectionList?.view)
        window.layoutIfNeeded()
        list.contentOffset.y = list.contentSize.height - list.bounds.height + list.adjustedContentInset.bottom
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(spy.didApproachCommentEndCount, 1)
        page.showLoadingMoreComments()
        page.hideLoadingMoreComments()
        for _ in 0..<4 { list.delegate?.scrollViewDidScroll?(list) }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(spy.didApproachCommentEndCount, 1)
        list.delegate?.scrollViewWillBeginDragging?(list)
        list.contentOffset.y += 5
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(spy.didApproachCommentEndCount, 2)
    }

    func testMeasuredFloorKeepsItsHeightWhileSignatureReloads() async throws {
        let settings = PostSignatureDisplaySettings.shared
        let previous = settings.showsSignatures
        settings.setShowsSignatures(true)
        defer { settings.setShowsSignatures(previous) }
        let page = PostDetailViewController(presenter: SpyPostDetailPresenter(), usesTextKitList: true)
        let window = try pagingWindow(for: page)
        defer { window.isHidden = true; window.rootViewController = nil }
        let signature = "<p>签名第一行<br>第二行<br>第三行<br>第四行</p>"
        let comment = Comment(id: "9", anchorID: "9", authorName: "Alice", avatarURL: nil, floorText: "#9",
                              createdAtText: nil, contentHTML: "<p>正文</p>", signatureHTML: signature,
                              markdown: "正文", hasVisibleMarkdown: true)
        page.render(detail: PostDetail(id: "1", title: "高度", authorName: "Bob", avatarURL: nil,
                                       metadataText: nil, contentHTML: "主帖", visibleMarkdown: "主帖", comments: [comment]))
        let host = try XCTUnwrap(page.collectionList)
        let list = host.view
        window.layoutIfNeeded()
        let path = try XCTUnwrap(page.indexPathForCurrentPageAnchor("9"))
        let cell = try await waitForCell(list, at: path)
        for _ in 0..<100 where !cell.isSettled { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(cell.isSettled)
        try await Task.sleep(nanoseconds: 50_000_000)
        list.layoutIfNeeded()
        let height = cell.bounds.height

        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        host.renderer.onStep = { step, request in
            if step == .parse, request.source.html == signature { _ = gate.wait(timeout: .now() + 3) }
        }
        host.refresh(commentID: "9")
        try await Task.sleep(nanoseconds: 100_000_000)
        list.layoutIfNeeded()
        let reconfigured = try XCTUnwrap(list.cellForItem(at: path) as? DetailFloorListCell)
        XCTAssertTrue(reconfigured.contentInstalled)
        XCTAssertFalse(reconfigured.isSettled)
        XCTAssertEqual(reconfigured.bounds.height, height, accuracy: 1)
    }

    /// 签名字小、链接挨得近：沿用旧版放大点击区，点到几个链接的重叠处时弹出选择面板，只命中一个时直接打开。
    func testSignatureLinksUseEnlargedTargetsAndAskWhenAmbiguous() async throws {
        let settings = PostSignatureDisplaySettings.shared
        let previous = settings.showsSignatures
        settings.setShowsSignatures(true)
        defer { settings.setShowsSignatures(previous) }
        let page = PostDetailViewController(presenter: SpyPostDetailPresenter(), usesTextKitList: true)
        let window = try pagingWindow(for: page)
        defer { window.isHidden = true; window.rootViewController = nil }
        // 仿 703863 的签名：首行两个挨着的短链接，次行长文字后一个远处的链接。
        let signature = "<p><a href=\"https://t.me/a\">TG</a> | <a href=\"https://example.com/blog\">博客</a></p>"
            + "<p>一段比较长的签名说明文字<a href=\"https://example.com/home\">主页</a></p>"
        let comment = Comment(id: "9", anchorID: "9", authorName: "Alice", avatarURL: nil, floorText: "#9",
                              createdAtText: nil, contentHTML: "<p>正文</p>", signatureHTML: signature,
                              markdown: "正文", hasVisibleMarkdown: true)
        page.render(detail: PostDetail(id: "1", title: "签名", authorName: "Bob", avatarURL: nil,
                                       metadataText: nil, contentHTML: "主帖", visibleMarkdown: "主帖", comments: [comment]))
        let list = try XCTUnwrap(page.collectionList?.view)
        window.layoutIfNeeded()
        let path = try XCTUnwrap(page.indexPathForCurrentPageAnchor("9"))
        let cell = try await waitForCell(list, at: path)
        for _ in 0..<200 where !cell.isSettled { try await Task.sleep(nanoseconds: 10_000_000) }
        // 首屏遮盖揭开后才是用户能点到的状态。
        func covered() -> Bool { window.subviewsRecursive.contains { $0.accessibilityIdentifier == "post-detail-reveal-cover" } }
        for _ in 0..<300 where covered() { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(covered())
        window.layoutIfNeeded()
        let signatureView = try XCTUnwrap(allSubviews(cell.contentView).first { $0.accessibilityIdentifier == "detail-signature" })
        let text = try XCTUnwrap(allSubviews(signatureView).compactMap { $0 as? DetailSelectableTextView }.first, "签名没有用 TextKit 渲染")
        func center(of url: String) throws -> CGPoint {
            let boxes = text.snapshot.characters.filter { $0.link?.absoluteString == url }
            let rect = try XCTUnwrap(boxes.map(\.rect).reduce(nil) { $0?.union($1) ?? $1 })
            return CGPoint(x: rect.midX, y: rect.midY)
        }
        func presentedCandidates() -> [String]? {
            guard let sheet = page.presentedViewController as? LinkSelectionSheetViewController else { return nil }
            return sheet.candidates.map(\.url.absoluteString)
        }
        func dismiss() async throws {
            page.presentedViewController?.dismiss(animated: false)
            for _ in 0..<200 where page.presentedViewController != nil { try await Task.sleep(nanoseconds: 10_000_000) }
            XCTAssertNil(page.presentedViewController)
        }

        // 点在「TG」上：放大后的点击区与「博客」重叠，让用户选。
        let tg = try center(of: "https://t.me/a")
        XCTAssertTrue(cell.hitTest(text.convert(tg, to: cell), with: nil) === text)
        XCTAssertTrue(text.activateLink(at: tg))
        XCTAssertEqual(presentedCandidates(), ["https://t.me/a", "https://example.com/blog"])
        try await dismiss()

        // 「主页」离首行链接远，只命中它一个：直接打开，不弹选择面板。
        let home = try center(of: "https://example.com/home")
        XCTAssertEqual(text.linkCandidates(at: home).map(\.url.absoluteString), ["https://example.com/home"])
        XCTAssertTrue(text.activateLink(at: home))
        XCTAssertTrue(page.presentedViewController is SFSafariViewController)
        try await dismiss()

        // 点在签名文字下方的空白：仍落在「主页」的放大区内，由楼层转交签名处理，不会点空。
        let below = text.convert(CGPoint(x: home.x, y: text.bounds.maxY + 6), to: cell.contentView)
        XCTAssertFalse(cell.hitTest(cell.contentView.convert(below, to: cell), with: nil) is UIStackView, "签名下方的空白吞掉了点击")
        cell.openLink(near: below)
        XCTAssertTrue(page.presentedViewController is SFSafariViewController, "签名下方的空白没有打开链接")
        try await dismiss()
    }

    /// 新版列表在签名排好后还会再量高度；宽度变化重建排版时会移除链接点击层，之后必须能补回来。
    func testRichTextKeepsLinksTappableAfterWidthChange() throws {
        let host = UIViewController()
        let window = try pagingWindow(for: host)
        defer { window.isHidden = true; window.rootViewController = nil }
        let blocks = DTCoreTextHTMLContentRenderer().renderTextBlocks(
            fragment: "<p><a href=\"https://t.me/a\">TG</a></p>", baseURL: NodeSeekSite.baseURL, maxImageWidth: 320)
        guard case .text(let text) = try XCTUnwrap(blocks.first) else { return XCTFail("签名没有渲染成文字") }
        // 与签名一致：按整楼宽度创建，装进有缩进的栈后实际宽度变窄，触发重新排版。
        let rich = DetailRichTextView(frame: CGRect(x: 0, y: 0, width: 358, height: 1))
        rich.configure(text, onImageTapped: nil, onLayoutInvalidated: nil)
        let stack = UIStackView(arrangedSubviews: [rich])
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        host.view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: host.view.leadingAnchor, constant: 38),
                                     stack.topAnchor.constraint(equalTo: host.view.topAnchor, constant: 100),
                                     stack.widthAnchor.constraint(equalToConstant: 320)])
        window.layoutIfNeeded()
        XCTAssertEqual(allButtons(rich).count, 1, "排版后签名链接没有点击层")
        // 约束更新阶段会再查询固有尺寸，重建排版会移除已生成的点击层。
        rich.invalidateIntrinsicContentSize()
        _ = rich.intrinsicContentSize
        // 真实列表里这次查询发生在本视图布局之后，不会再有布局把点击层补回来。
        XCTAssertEqual(allButtons(rich).count, 1, "量高度后签名链接的点击层消失")
    }

    func testRepeatedPageDeliveryPreservesUniqueRows() throws {
        let page = PostDetailViewController(presenter: SpyPostDetailPresenter(), usesTextKitList: true)
        let window = try pagingWindow(for: page)
        defer { window.isHidden = true; window.rootViewController = nil }
        page.render(detail: makePagedDetail(1...10, pageNumber: 1, next: 2))
        let second = makePagedDetail(11...12, pageNumber: 2, next: nil)
        page.appendCommentPage(detail: second)
        page.appendCommentPage(detail: second)
        let list = try XCTUnwrap(page.collectionList?.view)
        window.layoutIfNeeded()
        XCTAssertEqual(page.comments.map(\.id), (1...12).map(String.init))
        XCTAssertEqual(list.numberOfItems(inSection: 0), 14)
    }

    func testBusyPresenterDoesNotConsumeNextPage() async throws {
        let spy = SpyPostDetailPresenter()
        spy.acceptsBatchFetch = false
        let page = PostDetailViewController(presenter: spy, usesTextKitList: true)
        let window = try pagingWindow(for: page)
        defer { window.isHidden = true; window.rootViewController = nil }
        page.render(detail: makePagedDetail(1...45, pageNumber: 1, next: 2))
        let list = try XCTUnwrap(page.collectionList?.view)
        window.layoutIfNeeded()
        let end = list.contentSize.height - list.bounds.height + list.adjustedContentInset.bottom
        var target = CGPoint(x: 0, y: end)
        func release() {
            list.delegate?.scrollViewWillEndDragging?(list, withVelocity: CGPoint(x: 0, y: 2), targetContentOffset: &target)
        }
        release()
        XCTAssertEqual(spy.didApproachCommentEndCount, 1)
        spy.acceptsBatchFetch = true
        release()
        release()
        XCTAssertEqual(spy.didApproachCommentEndCount, 2)
    }

    func testShortLastPageShowsItsNumberAtTheBottom() async throws {
        let page = PostDetailViewController(presenter: SpyPostDetailPresenter(), usesTextKitList: true)
        let window = try pagingWindow(for: page)
        defer { window.isHidden = true; window.rootViewController = nil }
        let list = try XCTUnwrap(page.collectionList?.view)
        page.render(detail: makePagedDetail(1...10, pageNumber: 1, next: 2))
        page.appendCommentPage(detail: makePagedDetail(11...12, pageNumber: 2, next: nil))
        window.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(page.visibleCommentPage, 1)

        let end = list.contentSize.height - list.bounds.height + list.adjustedContentInset.bottom
        list.setContentOffset(CGPoint(x: 0, y: end), animated: false)
        list.layoutIfNeeded()
        let visible = list.indexPathsForVisibleItems
        XCTAssertTrue(visible.contains(try XCTUnwrap(page.indexPathForCurrentPageAnchor("10"))))
        XCTAssertTrue(visible.contains(try XCTUnwrap(page.indexPathForCurrentPageAnchor("12"))))
        XCTAssertEqual(page.visibleCommentPage, 2)
        XCTAssertTrue(list.alwaysBounceVertical)

        list.setContentOffset(CGPoint(x: 0, y: -list.adjustedContentInset.top), animated: false)
        list.layoutIfNeeded()
        XCTAssertEqual(page.visibleCommentPage, 1)
    }

    func testFastFlickRequestsUpcomingPageBeforeDecelerationReachesTheEnd() async throws {
        let spy = SpyPostDetailPresenter()
        let page = PostDetailViewController(presenter: spy, usesTextKitList: true)
        let window = try pagingWindow(for: page)
        defer { window.isHidden = true; window.rootViewController = nil }

        page.render(detail: makePagedDetail(1...45, pageNumber: 1, next: 2))
        window.layoutIfNeeded()
        let list = try XCTUnwrap(page.collectionList?.view)
        let end = list.contentSize.height - list.bounds.height + list.adjustedContentInset.bottom
        let start = CGPoint(x: 0, y: end - 3 * list.bounds.height)
        list.setContentOffset(start, animated: false)
        list.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        func release(at destination: CGFloat, velocity: CGFloat) {
            var target = CGPoint(x: 0, y: destination)
            list.delegate?.scrollViewWillEndDragging?(list, withVelocity: CGPoint(x: 0, y: velocity), targetContentOffset: &target)
            XCTAssertEqual(target.y, destination)
        }
        release(at: start.y - 120, velocity: -1)
        release(at: start.y + 120, velocity: 0.3)
        XCTAssertEqual(spy.didApproachCommentEndCount, 0)
        release(at: end - 80, velocity: 3)
        XCTAssertEqual(spy.didApproachCommentEndCount, 1)
        list.setContentOffset(CGPoint(x: 0, y: end - 80), animated: false)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(spy.didApproachCommentEndCount, 1)
    }

    func testScrollDuringPageJumpDoesNotConsumeNewPagesPrefetch() async throws {
        let spy = SpyPostDetailPresenter()
        let page = PostDetailViewController(presenter: spy, usesTextKitList: true)
        let window = try pagingWindow(for: page)
        defer { window.isHidden = true; window.rootViewController = nil }

        let list = try XCTUnwrap(page.collectionList?.view)
        func scrollToEnd() {
            let y = list.contentSize.height - list.bounds.height + list.adjustedContentInset.bottom
            list.setContentOffset(CGPoint(x: 0, y: y), animated: false)
            list.layoutIfNeeded()
        }
        page.render(detail: makePagedDetail(1...30, pageNumber: 1, next: 2))
        window.layoutIfNeeded()
        page.jumpToCommentPage(5)
        page.showLoading()
        scrollToEnd()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(spy.didApproachCommentEndCount, 0, "等待跳页时旧列表仍可滑动")

        let beforeNewPage = spy.didApproachCommentEndCount
        page.render(detail: makePagedDetail(121...150, pageNumber: 5, next: 6))
        page.hideLoading()
        list.layoutIfNeeded()
        scrollToEnd()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(spy.didApproachCommentEndCount, 1)
        XCTAssertEqual(spy.didApproachCommentEndCount - beforeNewPage, 1, "新页回复数相同时也应继续分页")
        XCTAssertEqual(page.currentPage, 5)
    }

    func testFilteredRepliesCanScrollIntoTheNextPageAfterInitialMatches() async throws {
        let spy = SpyPostDetailPresenter()
        let page = PostDetailViewController(presenter: spy, usesTextKitList: true)
        let window = try pagingWindow(for: page)
        defer { window.isHidden = true; window.rootViewController = nil }

        let detail = makePagedDetail(1...45, pageNumber: 1, next: 2)
        page.render(detail: detail)
        window.layoutIfNeeded()
        page.toggleAuthorFilter(.author(of: detail.comments[0]), focusingCommentID: nil)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(spy.didApproachCommentEndCount, 0)
        let list = try XCTUnwrap(page.collectionList?.view)
        let end = list.contentSize.height - list.bounds.height + list.adjustedContentInset.bottom
        list.setContentOffset(CGPoint(x: 0, y: end), animated: false)
        list.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(spy.didApproachCommentEndCount, 1)
    }

    func testFailedAuthorFilterAutoLoadStillLetsScrollingLoadTheNextPage() async throws {
        let spy = SpyPostDetailPresenter()
        let page = PostDetailViewController(presenter: spy, usesTextKitList: true)
        let window = try pagingWindow(for: page)
        defer { window.isHidden = true; window.rootViewController = nil }
        let paged = makePagedDetail(1...45, pageNumber: 1, next: 2)
        var comments = paged.comments
        let target = Comment(id: "1", anchorID: "1", authorName: "Carol", avatarURL: nil, floorText: "#1", createdAtText: nil,
                             contentHTML: "短回复", markdown: "短回复", hasVisibleMarkdown: true)
        comments[0] = target
        page.render(detail: PostDetail(id: "10", title: "分页", authorName: "Bob", avatarURL: nil, metadataText: nil,
                                       contentHTML: "主楼", visibleMarkdown: "主楼", comments: comments, page: 1,
                                       pagination: .init(currentPage: 1, items: [], previousPage: nil, nextPage: 2)))
        window.layoutIfNeeded()
        spy.onApproachCommentEnd = { [weak page] in page?.showLoadingMoreComments() }
        // 只看 TA 后本页匹配太少，自动向后补页；这次请求失败。
        page.toggleAuthorFilter(.author(of: target), focusingCommentID: nil)
        for _ in 0..<50 where spy.didApproachCommentEndCount == 0 { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(spy.didApproachCommentEndCount, 1)
        page.hideLoadingMoreComments()
        let list = try XCTUnwrap(page.collectionList?.view)
        list.delegate?.scrollViewWillBeginDragging?(list)
        list.setContentOffset(CGPoint(x: 0, y: max(0, list.contentSize.height - list.bounds.height + list.adjustedContentInset.bottom)), animated: false)
        list.delegate?.scrollViewDidScroll?(list)
        list.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(spy.didApproachCommentEndCount, 2, "失败后用户再拖动，应能重新请求下一页")
    }

    func testMainPostReactionOnlyRefreshesTheMainPost() async throws {
        let page = PostDetailViewController(presenter: SpyPostDetailPresenter(), usesTextKitList: true)
        let window = try pagingWindow(for: page)
        defer { window.isHidden = true; window.rootViewController = nil }
        let detail = makePagedDetail(1...5, pageNumber: 1, next: nil)
        page.render(detail: detail)
        let list = try XCTUnwrap(page.collectionList?.view)
        window.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 300_000_000)
        func versions() -> [String: Int] {
            Dictionary(uniqueKeysWithValues: list.visibleCells.compactMap { ($0 as? DetailFloorListCell)?.request }.map { ($0.id, $0.version) })
        }
        let before = versions()
        XCTAssertGreaterThan(before.count, 1)
        // 主楼点赞、鸡腿、收藏和作者风险提示只改主楼，回复楼层不应清空重装（签名和网页回退正文会闪）。
        page.updatePostBody(detail: detail)
        page.updateAuthorRiskWarning(postID: detail.id, isVisible: true)
        window.layoutIfNeeded()
        let after = versions()
        XCTAssertEqual(after.filter { !$0.key.hasPrefix("post-") }, before.filter { !$0.key.hasPrefix("post-") })
        XCTAssertNotEqual(after.first { $0.key.hasPrefix("post-") }?.value, before.first { $0.key.hasPrefix("post-") }?.value)
    }

    func testDuplicateHotAndPagedReplyKeepSeparateSourcesAndTargetThePagedRow() async throws {
        func reply(_ text: String, hot: Bool) -> Comment {
            Comment(id: "150", anchorID: "21", authorName: "Alice", avatarURL: nil, floorText: "#21", createdAtText: nil,
                    contentHTML: text, isHot: hot, markdown: hot ? nil : text, hasVisibleMarkdown: !hot)
        }
        func detail(_ comments: [Comment], page: Int) -> PostDetail {
            PostDetail(id: "10", title: "主题", authorName: "Bob", avatarURL: nil, metadataText: nil,
                       contentHTML: "正文", visibleMarkdown: "正文", comments: comments, page: page)
        }
        let page = PostDetailViewController(presenter: SpyPostDetailPresenter(), usesTextKitList: true)
        page.loadViewIfNeeded()
        page.view.frame = CGRect(x: 0, y: 0, width: 390, height: 900)
        page.render(detail: detail([reply("热评", hot: true)], page: 1))
        page.appendCommentPage(detail: detail([reply("普通回复", hot: false)], page: 2))
        page.view.layoutIfNeeded()
        let list = try XCTUnwrap(page.collectionList?.view)
        XCTAssertEqual(list.numberOfItems(inSection: 0), 4)
        let target = try XCTUnwrap(page.indexPathForCurrentPageAnchor("21"))
        XCTAssertEqual(target.item, 3)
        let cell = try await waitForCell(list, at: target)
        XCTAssertEqual(cell.copyText, "普通回复")
        let hot = try await waitForCell(list, at: IndexPath(item: 2, section: 0))
        XCTAssertNotEqual(hot.request?.id, cell.request?.id)
        XCTAssertNil(hot.request?.source.visibleMarkdown)
        page.refreshCurrentCommentPage(detail: detail([reply("已编辑", hot: false)], page: 2))
        XCTAssertEqual(page.comments.map(\.contentHTML), ["热评", "已编辑"])
        page.renderLoginRequired(message: "登录后查看")
        XCTAssertNil(page.collectionList?.headerSource?.visibleMarkdown)
        XCTAssertTrue(page.comments.isEmpty)
        XCTAssertTrue(list.visibleCells.compactMap { $0 as? DetailFloorListCell }.allSatisfy { $0.copyText != "普通回复" })
    }

    func testOptInOpensCollectionAtRequestedFloor() async throws {
        let defaults = UserDefaults.standard
        let key = PostDetailViewController.textKitListKey
        let previous = defaults.object(forKey: key)
        defer { defaults.set(previous, forKey: key) }
        defaults.set(true, forKey: key)
        let routed = try XCTUnwrap(PostDetailRouter.createModule(page: 2, initialAnchorID: "21") as? PostDetailViewController)
        XCTAssertNotNil(routed.collectionList)
        defaults.set(false, forKey: key)
        XCTAssertNil((PostDetailRouter.createModule() as? PostDetailViewController)?.collectionList)
        defaults.removeObject(forKey: key)
        XCTAssertNotNil((PostDetailRouter.createModule() as? PostDetailViewController)?.collectionList, "未手动切换时默认使用 TextKit")
        // E2E 用启动参数 `-postDetail.useTextKitList NO` 切回 Texture，取到的是字符串。
        defaults.set("NO", forKey: key)
        XCTAssertNil((PostDetailRouter.createModule() as? PostDetailViewController)?.collectionList)
        defaults.removeObject(forKey: key)
        let page = PostDetailViewController(presenter: SpyPostDetailPresenter(), currentPage: 2, initialAnchorID: "21", usesTextKitList: true)
        page.loadViewIfNeeded()
        page.view.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        let comment = Comment(id: "150", anchorID: "21", authorName: "Alice", avatarURL: nil, floorText: "#21",
                              createdAtText: nil, contentHTML: "<p>回复</p>", markdown: "回复", hasVisibleMarkdown: true)
        let detail = PostDetail(id: "10", title: "正文", authorName: "Bob", avatarURL: nil, metadataText: nil,
                                contentHTML: "<p>正文</p>", visibleMarkdown: "正文", comments: [comment], page: 2)
        page.render(detail: detail)
        page.view.layoutIfNeeded()
        let list = try XCTUnwrap(page.view.subviews.compactMap { $0 as? UICollectionView }.first)
        let anchor = try XCTUnwrap(page.indexPathForCurrentPageAnchor("21"))
        // 定位在下一轮主线程执行，主楼按一屏预估时锚点不在首屏内。
        for _ in 0..<100 where !list.indexPathsForVisibleItems.contains(anchor) {
            try await Task.sleep(nanoseconds: 10_000_000)
            page.view.layoutIfNeeded()
        }
        XCTAssertTrue(list.indexPathsForVisibleItems.contains(anchor))
    }

    private func allViews(_ root: UIView) -> [UIView] {
        [root] + root.subviews.flatMap(allViews)
    }

    private func view(_ id: String, in root: UIView) -> UIView? {
        allViews(root).first { $0.accessibilityIdentifier == id }
    }

    func testInitialLoadShowsTextureSkeletonLayout() throws {
        let page = PostDetailViewController(presenter: SpyPostDetailPresenter(), usesTextKitList: true)
        let window = try pagingWindow(for: page)
        defer { window.isHidden = true; window.rootViewController = nil }
        page.showLoading()
        window.layoutIfNeeded()
        let list = try XCTUnwrap(page.collectionList?.view)
        let skeletons = list.visibleCells.filter { $0.accessibilityIdentifier?.hasPrefix("post-detail-skeleton") == true }
        // 与 Texture 一致：1 个主楼骨架 + 4 个回复骨架。
        XCTAssertEqual(skeletons.map(\.accessibilityIdentifier), ["post-detail-skeleton-header"] + Array(repeating: "post-detail-skeleton-comment", count: 4))
        XCTAssertEqual(skeletons.first?.bounds.height ?? 0, 354, accuracy: 0.5)
        XCTAssertEqual(skeletons.last?.bounds.height ?? 0, 136, accuracy: 0.5)

        page.render(detail: makePagedDetail(1...3, pageNumber: 1, next: nil))
        window.layoutIfNeeded()
        XCTAssertFalse(list.visibleCells.contains { $0.accessibilityIdentifier?.hasPrefix("post-detail-skeleton") == true })
    }

    func testReplyHeaderKeepsTexturePosterHotAndStatusBadges() async throws {
        let page = PostDetailViewController(presenter: SpyPostDetailPresenter(), usesTextKitList: true)
        let window = try pagingWindow(for: page)
        defer { window.isHidden = true; window.rootViewController = nil }
        let reply = Comment(id: "2", anchorID: "1", authorName: "Alice", isPoster: true, avatarURL: nil,
                            authorBadgeTexts: ["禁言", "Lv3"], floorText: "#1", createdAtText: "1 小时前",
                            contentHTML: "回复", isHot: true, markdown: "回复", hasVisibleMarkdown: true)
        page.render(detail: PostDetail(id: "1", title: "主题", authorName: "Bob", avatarURL: nil,
                                       metadataText: nil, contentHTML: "主帖", visibleMarkdown: "主帖", comments: [reply]))
        window.layoutIfNeeded()
        let list = try XCTUnwrap(page.collectionList?.view)
        let cell = try await waitForCell(list, at: try XCTUnwrap(page.indexPathForCurrentPageAnchor("1")))
        XCTAssertEqual(cell.metadata.text, "Alice")
        let poster = try XCTUnwrap(view("detail-poster-badge", in: cell) as? UILabel)
        XCTAssertFalse(poster.isHidden)
        XCTAssertEqual(poster.text, "楼主")
        XCTAssertEqual(poster.textColor, .systemOrange)
        let badges = allViews(cell).filter { $0.accessibilityIdentifier == "detail-author-badge" && !$0.isHidden }
        XCTAssertEqual(badges.map(\.accessibilityLabel), ["禁言", "Lv3"])
        XCTAssertEqual(badges.first?.layer.borderColor, UIColor.systemRed.cgColor)
        XCTAssertEqual(badges.last?.layer.borderColor, UIColor.separator.cgColor)
        let hot = try XCTUnwrap(view("detail-hot-badge", in: cell) as? UIImageView)
        XCTAssertFalse(hot.isHidden)
        XCTAssertEqual(hot.accessibilityLabel, "热门评论")
        XCTAssertEqual(allLabels(cell).first { $0.text == "#1" }?.isHidden, false)
        XCTAssertFalse(allLabels(cell).contains { $0.text?.contains("热评") == true })
    }

    func testPostRiskWarningIsCardInsteadOfHeaderText() throws {
        let page = PostDetailViewController(presenter: SpyPostDetailPresenter(), usesTextKitList: true)
        let window = try pagingWindow(for: page)
        defer { window.isHidden = true; window.rootViewController = nil }
        page.render(detail: PostDetail(id: "1", title: "主题", authorName: "Bob", authorBadgeTexts: ["Lv0"], avatarURL: nil,
                                       metadataText: "发布于 1 小时前", contentHTML: "主帖", visibleMarkdown: "主帖", comments: []))
        page.updateAuthorRiskWarning(postID: "1", isVisible: true)
        window.layoutIfNeeded()
        let list = try XCTUnwrap(page.collectionList?.view)
        let cell = try XCTUnwrap(list.visibleCells.compactMap { $0 as? DetailFloorListCell }.first)
        let warning = try XCTUnwrap(view("detail-risk-warning", in: cell))
        XCTAssertFalse(warning.isHidden)
        XCTAssertFalse(allLabels(cell.contentView).contains { $0 !== allLabels(warning).first && $0.text?.contains("温馨提醒") == true })
        XCTAssertEqual(allViews(cell).filter { $0.accessibilityIdentifier == "detail-author-badge" && !$0.isHidden }.map(\.accessibilityLabel), ["Lv0"])
    }

    func testRefreshingUnchangedLastPageKeepsFloorsAndPosition() async throws {
        let page = PostDetailViewController(presenter: SpyPostDetailPresenter(), usesTextKitList: true)
        let window = try pagingWindow(for: page)
        defer { window.isHidden = true; window.rootViewController = nil }
        let detail = makePagedDetail(1...20, pageNumber: 1, next: nil)
        page.render(detail: detail)
        let list = try XCTUnwrap(page.collectionList?.view)
        window.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 300_000_000)
        let end = list.contentSize.height - list.bounds.height + list.adjustedContentInset.bottom
        list.setContentOffset(CGPoint(x: 0, y: end), animated: false)
        window.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 200_000_000)
        let before = list.visibleCells.compactMap { $0 as? DetailFloorListCell }.compactMap(\.request)
        let offset = list.contentOffset.y
        XCTAssertFalse(before.isEmpty)

        // 点「加载新评论」后服务端返回同一页、无新回复：已显示的楼层不应重配，位置不变。
        page.refreshCurrentCommentPage(detail: detail)
        window.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 200_000_000)
        let after = list.visibleCells.compactMap { $0 as? DetailFloorListCell }.compactMap(\.request)
        XCTAssertEqual(Set(after.map(\.version)), Set(before.map(\.version)))
        XCTAssertEqual(list.contentOffset.y, offset, accuracy: 0.5)
    }

    func testFirstLayoutBuildsOnlyMainPostUntilItIsMeasured() async throws {
        let page = PostDetailViewController(presenter: SpyPostDetailPresenter(), usesTextKitList: true)
        let window = try pagingWindow(for: page)
        defer { window.isHidden = true; window.rootViewController = nil }
        page.render(detail: makePagedDetail(1...12, pageNumber: 1, next: nil))
        window.layoutIfNeeded()
        // 主楼量出高度前按一屏预估，首帧不为随后会被挤出屏幕的回复建 cell。
        let list = try XCTUnwrap(page.collectionList?.view)
        XCTAssertEqual(list.visibleCells.compactMap { $0 as? DetailFloorListCell }.count, 1)
        var waited = 0
        while list.visibleCells.compactMap({ $0 as? DetailFloorListCell }).count < 2, waited < 100 {
            try await Task.sleep(nanoseconds: 10_000_000)
            waited += 1
        }
        // 主楼很短时，量完后回复正常补上。
        XCTAssertGreaterThan(list.visibleCells.compactMap { $0 as? DetailFloorListCell }.count, 3)
    }

    func testShortMainPostKeepsInitialAnchorOnScreenAfterMeasuring() async throws {
        let page = PostDetailViewController(presenter: SpyPostDetailPresenter(), initialAnchorID: "2", usesTextKitList: true)
        let window = try pagingWindow(for: page)
        defer { window.isHidden = true; window.rootViewController = nil }
        page.render(detail: makePagedDetail(1...30, pageNumber: 1, next: nil))
        let list = try XCTUnwrap(page.collectionList?.view)
        let target = try XCTUnwrap(page.indexPathForCurrentPageAnchor("2"))
        for _ in 0..<50 {
            window.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        // 带锚点打开时主楼量完变短，目标楼层仍要留在屏幕内。
        let frame = try XCTUnwrap(list.layoutAttributesForItem(at: target)?.frame)
        let visible = CGRect(x: 0, y: list.contentOffset.y + list.adjustedContentInset.top, width: list.bounds.width,
                             height: list.bounds.height - list.adjustedContentInset.top - list.adjustedContentInset.bottom)
        XCTAssertTrue(visible.intersects(frame), "\(frame) \(visible)")
    }

    func testDragStartingOnFooterButtonStillScrollsList() throws {
        let page = PostDetailViewController(presenter: SpyPostDetailPresenter(), usesTextKitList: true)
        page.loadViewIfNeeded()
        let list = try XCTUnwrap(page.collectionList?.view)
        // 与旧版一致：手指在底栏按钮上停留后拖动，仍然滚动列表而不是卡在按钮上。
        XCTAssertTrue(list.touchesShouldCancel(in: UIButton(type: .system)))
        XCTAssertFalse(list.touchesShouldCancel(in: UITextField()))
    }

    func testFirstRenderKeepsSkeletonUntilVisibleFloorsInstall() async throws {
        let page = PostDetailViewController(presenter: SpyPostDetailPresenter(), usesTextKitList: true)
        let window = try pagingWindow(for: page)
        defer { window.isHidden = true; window.rootViewController = nil }
        page.showLoading()
        window.layoutIfNeeded()
        page.render(detail: makePagedDetail(1...12, pageNumber: 1, next: nil))
        window.layoutIfNeeded()
        // 与 Texture 首屏一致：内容排好前继续盖着骨架，不露出空楼层和预估高度。
        XCTAssertNotNil(view("post-detail-reveal-cover", in: page.view))
        var waited = 0
        while view("post-detail-reveal-cover", in: page.view) != nil, waited < 100 {
            try await Task.sleep(nanoseconds: 10_000_000)
            waited += 1
        }
        XCTAssertNil(view("post-detail-reveal-cover", in: page.view))
        let list = try XCTUnwrap(page.collectionList?.view)
        let floors = list.visibleCells.compactMap { $0 as? DetailFloorListCell }
        XCTAssertFalse(floors.isEmpty)
        XCTAssertTrue(floors.allSatisfy(\.contentInstalled))
    }

    func testAppSwitcherSnapshotAppearanceFlipDoesNotRebuildFloors() async throws {
        let page = PostDetailViewController(presenter: SpyPostDetailPresenter(), usesTextKitList: true)
        let window = try pagingWindow(for: page)
        defer { window.isHidden = true; window.rootViewController = nil }
        page.render(detail: makePagedDetail(1...5, pageNumber: 1, next: nil))
        let collection = try XCTUnwrap(page.collectionList)
        window.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 300_000_000)
        func versions() -> [Int] {
            collection.view.visibleCells.compactMap { ($0 as? DetailFloorListCell)?.request?.version }.sorted()
        }
        let installed = versions()
        XCTAssertFalse(installed.isEmpty)
        // 切后台时系统为任务切换器拍浅色和深色快照，外观会来回切一次，回到前台时已复原。
        var inBackground = true
        collection.isAppInBackground = { inBackground }
        for style in [UIUserInterfaceStyle.dark, .unspecified] {
            window.overrideUserInterfaceStyle = style
            window.layoutIfNeeded()
            collection.updateAppearance()
            window.layoutIfNeeded()
        }
        inBackground = false
        collection.updateAppearance()
        window.layoutIfNeeded()
        XCTAssertEqual(versions(), installed)
        // 前台真正切换外观仍要重排文字颜色。
        window.overrideUserInterfaceStyle = .dark
        window.layoutIfNeeded()
        collection.updateAppearance()
        window.layoutIfNeeded()
        XCTAssertNotEqual(versions(), installed)
    }
}

private extension UIView {
    var subviewsRecursive: [UIView] { subviews + subviews.flatMap(\.subviewsRecursive) }
}
