import UIKit
import XCTest
@testable import nodeseek

@MainActor
final class DetailCollectionTests: XCTestCase {
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
