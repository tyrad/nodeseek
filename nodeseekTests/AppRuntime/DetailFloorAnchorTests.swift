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
