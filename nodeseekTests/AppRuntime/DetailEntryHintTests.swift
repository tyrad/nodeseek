import UIKit
import XCTest
@testable import nodeseek

@MainActor
final class DetailEntryHintTests: XCTestCase {
    func testEnteringPageSevenShowsPageAndOpenPostButton() throws {
        try checkHint(afterJump: false)
    }

    func testJumpedPageShowsReturnButtonInDarkModeAtAccessibilitySize() throws {
        try checkHint(afterJump: true)
    }

    private func checkHint(afterJump: Bool) throws {
        let presenter = SpyPostDetailPresenter()
        let page = PostDetailViewController(presenter: presenter, currentPage: afterJump ? 1 : 7)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let navigation = UINavigationController(rootViewController: page)
        window.rootViewController = navigation
        navigation.setOverrideTraitCollection(UITraitCollection(preferredContentSizeCategory: afterJump ? .accessibilityExtraExtraLarge : .large), forChild: page)
        window.overrideUserInterfaceStyle = afterJump ? .dark : .light
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        func detail(_ number: Int) -> PostDetail {
            PostDetail(id: "1071060", title: "帖子 #1071060", authorName: "", avatarURL: nil, metadataText: nil,
                       contentHTML: "", comments: [Comment(id: "61", authorName: "Alice", avatarURL: nil, floorText: "#61",
                                                           createdAtText: nil, contentHTML: "回复")], page: number)
        }
        if afterJump {
            page.render(detail: detail(1))
            page.jumpToCommentPage(7)
        }
        page.render(detail: detail(7))
        window.layoutIfNeeded()
        let host = page.collectionList
        host.scroll(to: 1, position: .top)
        host.view.layoutIfNeeded()
        let cell = try XCTUnwrap(host.view.cellForItem(at: IndexPath(item: 1, section: 0)))
        func find<T: UIView>(_ type: T.Type, in view: UIView) -> [T] {
            view.subviews.flatMap { child in (child as? T).map { [$0] } ?? find(type, in: child) }
        }
        let button = try XCTUnwrap(find(UIButton.self, in: cell).first)
        let message = String.localizedStringWithFormat(DetailListStrings.text(afterJump ? "entry-starts-at-page" : "entry-opened-on-page"), 7)
        let label = try XCTUnwrap(find(UILabel.self, in: cell).first { $0.text == message })
        XCTAssertEqual(button.configuration?.title, DetailListStrings.text(afterJump ? "entry-return-first" : "entry-open-full-post"))
        let textRect = label.convert(label.bounds, to: cell)
        let actionRect = button.convert(button.bounds, to: cell)
        XCTAssertGreaterThanOrEqual(textRect.minX, 24)
        XCTAssertFalse(textRect.intersects(actionRect))
        XCTAssertLessThanOrEqual(actionRect.maxY, cell.bounds.maxY - 8)
        XCTAssertGreaterThanOrEqual(label.bounds.height + 1, label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude)).height)
        if !afterJump { XCTAssertEqual(cell.bounds.height, 62, accuracy: 1) }
        let shot = XCTAttachment(image: UIGraphicsImageRenderer(bounds: cell.bounds).image { _ in
            cell.drawHierarchy(in: cell.bounds, afterScreenUpdates: true)
        })
        shot.name = afterJump ? "entry-jump-dark-large" : "entry-page-seven"
        shot.lifetime = .keepAlways
        add(shot)
        button.sendActions(for: .touchUpInside)
        if afterJump {
            XCTAssertEqual(presenter.selectedCommentPages, [7, 1])
        } else {
            XCTAssertEqual(page.testOpenedFullPostPage, 1)
        }
    }
}
