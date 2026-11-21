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
        let reply = try XCTUnwrap(cell.contentView.subviews.flatMap(allButtons).first { $0.accessibilityLabel == DetailListStrings.text("reply") })
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

        // 同一系统同一段中西混排文字的默认行距。不同 iOS 的字体回退度量有差异。
        let reference = NSTextStorage(string: text, attributes: [.font: UIFont.systemFont(ofSize: pointSize)])
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 220, height: 1_000))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        reference.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        var first = NSRange()
        let firstLine = layout.lineFragmentRect(forGlyphAt: 0, effectiveRange: &first)
        let nextLine = layout.lineFragmentRect(forGlyphAt: NSMaxRange(first), effectiveRange: nil)
        let distance = snapshot.lines[1].maxY - snapshot.lines[0].maxY
        XCTAssertEqual(distance, nextLine.maxY - firstLine.maxY + DTCoreTextHTMLContentRenderer.Layout.bodyLineSpacing, accuracy: 1)
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
}
