import UIKit
import XCTest
@testable import nodeseek

@MainActor
final class DetailFloorAnchorTests: XCTestCase {
    private final class Touch: UITouch {
        var point = CGPoint.zero
        override func location(in view: UIView?) -> CGPoint { point }
    }

    func testShortFloorLinkAcceptsNearMissButNotOrdinaryTextOrDistantBlank() throws {
        let url = try XCTUnwrap(URL(string: "https://www.nodeseek.com/post-10-1#1"))
        let appearance = DetailTextAppearance(width: 320, pointSize: 17, scale: 3, dark: false)
        let segment = DetailTextSegment(runs: [.text("正文 ", [], nil), .text("#1", [], url)], pointSize: 17)
        let snapshot = try DetailTextTypesetter.layout([segment], appearance: appearance, width: appearance.width)
        let text = DetailSelectableTextView(snapshot: snapshot, scale: 3, onLink: { _ in }, stickerSizeChanged: {})
        let tap = try XCTUnwrap(text.gestureRecognizers?.compactMap { $0 as? UITapGestureRecognizer }.last)
        let touch = Touch()
        let last = try XCTUnwrap(snapshot.characters.last).rect
        func accepts(_ x: CGFloat, _ y: CGFloat) -> Bool {
            touch.point = CGPoint(x: x, y: y)
            return text.gestureRecognizer(tap, shouldReceive: touch)
        }
        XCTAssertTrue(accepts(last.midX, last.midY))
        XCTAssertTrue(accepts(last.maxX + 9, last.midY))
        XCTAssertTrue(accepts(last.midX, last.maxY + 6))
        XCTAssertFalse(accepts(snapshot.characters[1].rect.midX, last.midY))
        XCTAssertFalse(accepts(last.maxX + 40, last.midY))
    }

    func testNeighbouringAuthorAndFloorResolveToTheirOwnLinks() throws {
        let author = try XCTUnwrap(URL(string: "https://www.nodeseek.com/member?t=Alice"))
        let floor = try XCTUnwrap(URL(string: "https://www.nodeseek.com/post-10-1#2"))
        let appearance = DetailTextAppearance(width: 150, pointSize: 20, scale: 3, dark: true)
        let segment = DetailTextSegment(runs: [.text("@Alice", [], author), .text(" ", [], nil), .text("#2", [], floor)], pointSize: 20)
        let snapshot = try DetailTextTypesetter.layout([segment], appearance: appearance, width: appearance.width)
        let text = DetailSelectableTextView(snapshot: snapshot, scale: 3, onLink: { _ in }, stickerSizeChanged: {})
        let space = try XCTUnwrap(snapshot.characters.first { $0.link == nil }).rect
        XCTAssertEqual(text.linkHit(at: CGPoint(x: space.minX + 0.25, y: space.midY))?.url, author)
        XCTAssertEqual(text.linkHit(at: CGPoint(x: space.maxX - 0.25, y: space.midY))?.url, floor)
        let last = try XCTUnwrap(snapshot.characters.last).rect
        text.selectAll(nil)
        XCTAssertNil(text.linkHit(at: CGPoint(x: last.midX, y: last.midY)))
    }

    func testPageTwoLinkInFloor21PrefersOriginalFloor20OverPinnedCopy() async throws {
        func detail(_ floors: [Int], page: Int, hot: Set<Int> = []) -> PostDetail {
            let comments = floors.map { floor in
                Comment(id: String(floor), anchorID: String(floor), authorName: "A", avatarURL: nil,
                        floorText: "#\(floor)", createdAtText: nil, contentHTML: "回复", isHot: hot.contains(floor))
            }
            return PostDetail(id: "1067259", title: "帖子", authorName: "B", avatarURL: nil,
                              metadataText: nil, contentHTML: "", comments: comments, page: page)
        }
        let controller = PostDetailViewController(presenter: SpyPostDetailPresenter(), usesTextKitList: true)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        controller.render(detail: detail([20, 18, 21, 70, 19] + Array(1...10), page: 1, hot: [18, 21, 70, 19]))
        func targetIndex(_ floor: String) throws -> Int {
            let path = try XCTUnwrap(controller.indexPathForCurrentPageAnchor(floor))
            guard case .comment(let index) = controller.detailRows[path.row] else {
                XCTFail("楼层定位到了非回复行")
                return -1
            }
            return index
        }
        // 首页只有置顶和热评副本时，引用仍可定位它们。
        XCTAssertEqual(try targetIndex("20"), 0)
        XCTAssertEqual(try targetIndex("21"), 2)
        controller.appendCommentPage(detail: detail(Array(11...20), page: 2))
        controller.appendCommentPage(detail: detail(Array(21...30), page: 3))
        XCTAssertEqual(try targetIndex("20"), 24)
        XCTAssertEqual(try targetIndex("21"), 25)
        let list = try XCTUnwrap(controller.collectionList)
        let originalRow = try XCTUnwrap(controller.indexPathForCurrentPageAnchor("20"))
        window.layoutIfNeeded()
        for _ in 0..<30 {
            list.scroll(to: originalRow.item, position: .centeredVertically)
            try await Task.sleep(nanoseconds: 20_000_000)
            if list.view.indexPathsForVisibleItems.contains(originalRow) { break }
        }
        XCTAssertTrue(list.view.indexPathsForVisibleItems.contains(originalRow))
        controller.handleContentLinkTap(try XCTUnwrap(URL(string: "https://www.nodeseek.com/post-1067259-2#20")))
        XCTAssertEqual(controller.testHighlightedAnchorID, "20")
        XCTAssertTrue(list.view.indexPathsForVisibleItems.contains(originalRow))
        XCTAssertNil(controller.testPresentedLoadedCommentID)
        let direct = PostDetailViewController(presenter: SpyPostDetailPresenter(), currentPage: 3, usesTextKitList: true)
        direct.loadViewIfNeeded()
        direct.render(detail: detail(Array(21...30), page: 3))
        XCTAssertNil(direct.indexPathForCurrentPageAnchor("20"))
        XCTAssertEqual(direct.entryHintPage, 3)
    }

    func testTappingVisibleFloorHighlightsOnlyTheTargetAndReuseClearsIt() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let page = PostDetailViewController(presenter: SpyPostDetailPresenter(), usesTextKitList: true)
        window.rootViewController = page
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        let comments = (1...2).map { n in
            Comment(id: String(n + 100), anchorID: String(n), authorName: "Alice", avatarURL: nil,
                    floorText: "#\(n)", createdAtText: nil, contentHTML: "正文", markdown: "正文", hasVisibleMarkdown: true)
        }
        page.render(detail: PostDetail(id: "10", title: "标题", authorName: "Bob", avatarURL: nil,
                                      metadataText: nil, contentHTML: "主帖", visibleMarkdown: "主帖", comments: comments))
        window.layoutIfNeeded()
        let list = try XCTUnwrap(page.collectionList?.view)
        page.handleContentLinkTap(try XCTUnwrap(URL(string: "https://www.nodeseek.com/post-10-1#2")))
        let path = try XCTUnwrap(page.indexPathForCurrentPageAnchor("2"))
        let target = try XCTUnwrap(list.cellForItem(at: path) as? DetailFloorListCell)
        func overlay(_ cell: UICollectionViewCell) -> UIView? {
            cell.contentView.subviews.first { $0.accessibilityIdentifier == "detail-anchor-highlight" }
        }
        for _ in 0..<100 where overlay(target) == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let flash = try XCTUnwrap(overlay(target))
        XCTAssertFalse(flash.isUserInteractionEnabled)
        XCTAssertTrue(list.visibleCells.filter { $0 !== target }.allSatisfy { overlay($0) == nil })
        target.prepareForReuse()
        XCTAssertNil(overlay(target))
    }
}
