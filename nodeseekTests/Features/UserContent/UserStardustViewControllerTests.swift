import UIKit
import XCTest
@testable import nodeseek

@MainActor
final class UserStardustViewControllerTests: XCTestCase {
    func testLedgerRendersBothThemesLargeTextAndNavigatesToMember() async throws {
        let client = LedgerScreenClient()
        let controller = UserStardustViewController(uid: 31037, isSelf: true, client: client)
        let root = UIViewController()
        root.title = "个人页"
        root.view.backgroundColor = .systemGroupedBackground
        let navigation = UINavigationController(rootViewController: root)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        navigation.pushViewController(controller, animated: false)
        controller.loadViewIfNeeded()
        for _ in 0..<100 where client.pending == nil { await Task.yield() }
        XCTAssertNotNil(client.pending)
        window.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 250_000_000)
        try capture(window, name: "stardust-skeleton")
        client.pending?.resume(returning: Self.page)
        client.pending = nil
        let table = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UITableView }.first)
        for _ in 0..<100 where table.numberOfRows(inSection: 0) != 3 { await Task.yield() }
        XCTAssertEqual(table.numberOfRows(inSection: 0), 3)
        let owner = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UILabel }.first { $0.accessibilityIdentifier == "stardust-owner" })
        XCTAssertEqual(owner.text, "缭雾")
        for (style, name) in [(UIUserInterfaceStyle.light, "light"), (.dark, "dark")] {
            window.overrideUserInterfaceStyle = style
            try await Task.sleep(nanoseconds: 150_000_000)
            window.layoutIfNeeded()
            try capture(window, name: "stardust-\(name)")
            XCTAssertTrue(descendants(controller.view).compactMap { $0 as? UILabel }.contains { $0.text == "转账" })
        }
        navigation.setOverrideTraitCollection(UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge), forChild: controller)
        table.reloadData()
        window.layoutIfNeeded()
        table.setContentOffset(CGPoint(x: 0, y: -table.adjustedContentInset.top), animated: false)
        try capture(window, name: "stardust-large-text")
        navigation.setOverrideTraitCollection(nil, forChild: controller)
        table.reloadData()
        window.layoutIfNeeded()
        let member = try XCTUnwrap(descendants(table).compactMap { $0 as? UIControl }.first { $0.accessibilityLabel == "UID 70992" })
        member.sendActions(for: .touchUpInside)
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(navigation.topViewController is UserProfileViewController)
        navigation.popViewController(animated: true)
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(navigation.topViewController === controller)
        XCTAssertEqual(table.numberOfRows(inSection: 0), 3)
    }

    private func capture(_ window: UIWindow, name: String) throws {
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { context in window.layer.render(in: context.cgContext) }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }

    static let page = UserStardustPage(records: [
        UserStardustRecord(id: 3, memberID: 31037, peerID: 70992, type: "upvote", diff: 1, result: 11, createdAt: "2026-10-28T08:33:51.000Z"),
        UserStardustRecord(id: 2, memberID: 31037, peerID: 53104, type: "transfer", diff: -2, result: 10, createdAt: "2026-10-27T08:33:51.000Z"),
        UserStardustRecord(id: 1, memberID: 31037, peerID: nil, type: "system", diff: 1, result: 12, createdAt: "2026-10-26T08:33:51.000Z")
    ], hasMore: false, cursor: 1)
}

@MainActor
private final class LedgerScreenClient: UserStardustLoading {
    var pending: CheckedContinuation<UserStardustPage, Error>?
    func loadStardust(uid: Int, beforeID: Int?) async throws -> UserStardustPage {
        try await withCheckedThrowingContinuation { pending = $0 }
    }
    func loadProfile(uid: Int) async throws -> UserProfileRecord {
        UserProfileRecord(uid: uid, name: "缭雾", rank: 4, coin: 1758, stardust: 11, bio: "", readme: "", createdAt: nil,
                          postCount: 19, commentCount: 550, follows: 0, fans: 2, collectionCount: nil, roleNames: [])
    }
}
