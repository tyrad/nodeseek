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
        let cell = try XCTUnwrap(list.cellForItem(at: path) as? DetailFloorListCell)
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
        let cell = try XCTUnwrap(list.cellForItem(at: try XCTUnwrap(page.indexPathForCurrentPageAnchor("1"))) as? DetailFloorListCell)
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
        let cell = try XCTUnwrap(list.cellForItem(at: try XCTUnwrap(page.indexPathForCurrentPageAnchor("1"))) as? DetailFloorListCell)
        let name = try XCTUnwrap(allLabels(cell.contentView).first { $0.text == "Alice" })
        // 与旧版一致：长按名字和头像一样弹出个人页预览，读屏说明可打开主页。
        let menu = try XCTUnwrap(name.interactions.compactMap { $0 as? UIContextMenuInteraction }.first)
        XCTAssertNotNil(menu.delegate?.contextMenuInteraction(menu, configurationForMenuAtLocation: .zero))
        XCTAssertEqual(name.accessibilityLabel, String(format: DetailListStrings.text("view-profile"), "Alice"))
        XCTAssertTrue(name.accessibilityTraits.contains(.button))
    }

    private func allButtons(_ root: UIView) -> [UIButton] {
        (root as? UIButton).map { [$0] } ?? root.subviews.flatMap(allButtons)
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

    private func pagingWindow(for page: PostDetailViewController) throws -> UIWindow {
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
        let cell = try XCTUnwrap(list.cellForItem(at: path) as? DetailFloorListCell)
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

    func testDuplicateHotAndPagedReplyKeepSeparateSourcesAndTargetThePagedRow() throws {
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
        let cell = try XCTUnwrap(list.cellForItem(at: target) as? DetailFloorListCell)
        XCTAssertEqual(cell.copyText, "普通回复")
        let hot = try XCTUnwrap(list.cellForItem(at: IndexPath(item: 2, section: 0)) as? DetailFloorListCell)
        XCTAssertNotEqual(hot.request?.id, cell.request?.id)
        XCTAssertNil(hot.request?.source.visibleMarkdown)
        page.refreshCurrentCommentPage(detail: detail([reply("已编辑", hot: false)], page: 2))
        XCTAssertEqual(page.comments.map(\.contentHTML), ["热评", "已编辑"])
        page.renderLoginRequired(message: "登录后查看")
        XCTAssertNil(page.collectionList?.headerSource?.visibleMarkdown)
        XCTAssertTrue(page.comments.isEmpty)
        XCTAssertTrue(list.visibleCells.compactMap { $0 as? DetailFloorListCell }.allSatisfy { $0.copyText != "普通回复" })
    }

    func testOptInOpensCollectionAtRequestedFloor() throws {
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
        XCTAssertTrue(list.indexPathsForVisibleItems.contains(try XCTUnwrap(page.indexPathForCurrentPageAnchor("21"))))
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
        let cell = try XCTUnwrap(list.cellForItem(at: try XCTUnwrap(page.indexPathForCurrentPageAnchor("1"))) as? DetailFloorListCell)
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
}
