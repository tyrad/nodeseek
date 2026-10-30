import UIKit
import XCTest
@testable import nodeseek

@MainActor
final class UserConnectionsViewControllerTests: XCTestCase {
    func testTabsRetainListsAndPositionAndOpenNativeProfile() async throws {
        let client = ConnectionsScreenClient()
        let controller = UserConnectionsViewController(client: client)
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
        let table = try XCTUnwrap(tableView(in: controller, id: "connections-list-following"))
        let followers = try XCTUnwrap(tableView(in: controller, id: "connections-list-followers"))
        let pager = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "connections-pager" } as? UIScrollView)
        let tabs = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UISegmentedControl }.first)
        for _ in 0..<100 where client.pending[.following] == nil { await Task.yield() }
        XCTAssertEqual(tabs.selectedSegmentIndex, 0)
        try await Task.sleep(nanoseconds: 200_000_000)
        capture(window, name: "connections-skeleton")
        client.pending.removeValue(forKey: .following)?.resume(returning: (0..<25).map { Self.person(uid: 9 + $0) })
        for _ in 0..<100 where table.numberOfRows(inSection: 0) != 25 { await Task.yield() }
        XCTAssertEqual(table.numberOfRows(inSection: 0), 25)
        for (style, name) in [(UIUserInterfaceStyle.light, "light"), (.dark, "dark")] {
            window.overrideUserInterfaceStyle = style
            try await Task.sleep(nanoseconds: 150_000_000)
            capture(window, name: "connections-following-\(name)")
        }
        // 未关注的人直接关注，按钮变成「已关注」
        let second = try XCTUnwrap(table.cellForRow(at: IndexPath(row: 1, section: 0)))
        let follow = try XCTUnwrap(descendants(second).first { $0.accessibilityIdentifier == "connection-follow-button" } as? UIButton)
        XCTAssertEqual(follow.configuration?.title, "关注")
        follow.sendActions(for: .touchUpInside)
        for _ in 0..<100 where client.followCalls.isEmpty { await Task.yield() }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(client.followCalls.first?.0, true)
        XCTAssertEqual(client.followCalls.first?.1, 10)
        let updated = try XCTUnwrap(table.cellForRow(at: IndexPath(row: 1, section: 0)))
        XCTAssertEqual((descendants(updated).first { $0.accessibilityIdentifier == "connection-follow-button" } as? UIButton)?.configuration?.title, "已关注")
        let toast = try XCTUnwrap(descendants(window).first { $0.accessibilityIdentifier == BottomToast.accessibilityIdentifier })
        XCTAssertTrue(descendants(toast).compactMap { $0 as? UILabel }.contains { $0.text == "已关注" })
        capture(window, name: "connections-follow-toast")
        table.setContentOffset(CGPoint(x: 0, y: 240), animated: false)
        let savedOffset = table.contentOffset.y
        func page(to index: Int) {
            pager.setContentOffset(CGPoint(x: CGFloat(index) * pager.bounds.width, y: 0), animated: false)
            controller.scrollViewDidEndDecelerating(pager)
        }
        page(to: 1)
        XCTAssertEqual(tabs.selectedSegmentIndex, 1)
        for _ in 0..<100 where client.pending[.followers] == nil { await Task.yield() }
        page(to: 0)
        XCTAssertEqual(tabs.selectedSegmentIndex, 0)
        XCTAssertEqual(table.numberOfRows(inSection: 0), 25)
        XCTAssertEqual(table.contentOffset.y, savedOffset, accuracy: 1)
        XCTAssertEqual(client.calls.filter { $0 == .following }.count, 1)
        client.pending.removeValue(forKey: .followers)?.resume(returning: [Self.person(uid: 14496), Self.person(uid: 67694)])
        for _ in 0..<100 where followers.numberOfRows(inSection: 0) != 2 { await Task.yield() }
        XCTAssertEqual(table.numberOfRows(inSection: 0), 25)
        // 拖到一半时截图，确认两页内容跟手并排
        pager.setContentOffset(CGPoint(x: pager.bounds.width / 2, y: 0), animated: false)
        capture(window, name: "connections-dragging")
        tabs.selectedSegmentIndex = 1
        tabs.sendActions(for: .valueChanged)
        try await Task.sleep(nanoseconds: 500_000_000)
        window.layoutIfNeeded()
        XCTAssertEqual(pager.contentOffset.x, pager.bounds.width, accuracy: 1)
        XCTAssertEqual(followers.numberOfRows(inSection: 0), 2)
        capture(window, name: "connections-followers-dark")
        navigation.setOverrideTraitCollection(UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge), forChild: controller)
        followers.reloadData()
        window.layoutIfNeeded()
        capture(window, name: "connections-large-text")
        navigation.setOverrideTraitCollection(nil, forChild: controller)
        followers.reloadData()
        controller.tableView(followers, didSelectRowAt: IndexPath(row: 0, section: 0))
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(navigation.topViewController is UserProfileViewController)
        navigation.popViewController(animated: true)
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(navigation.topViewController === controller)
        XCTAssertEqual(tabs.selectedSegmentIndex, 1)
        XCTAssertEqual(followers.numberOfRows(inSection: 0), 2)
        XCTAssertEqual(pager.contentOffset.x, pager.bounds.width, accuracy: 1)
    }

    func testFansEntryStartsOnFollowersAndDisplaysEmptyState() async throws {
        let client = ConnectionsScreenClient()
        let controller = UserConnectionsViewController(initialKind: .followers, client: client)
        controller.loadViewIfNeeded()
        for _ in 0..<100 where client.pending[.followers] == nil { await Task.yield() }
        XCTAssertEqual(client.calls, [.followers])
        client.pending.removeValue(forKey: .followers)?.resume(returning: [])
        for _ in 0..<20 { await Task.yield() }
        let table = try XCTUnwrap(tableView(in: controller, id: "connections-list-followers"))
        XCTAssertEqual(table.numberOfRows(inSection: 0), 0)
        XCTAssertTrue(descendants(table.backgroundView!).compactMap { $0 as? UILabel }.contains { $0.text == "暂无被关注用户" })
    }

    private func capture(_ window: UIWindow, name: String) {
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { window.layer.render(in: $0.cgContext) }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tableView(in controller: UIViewController, id: String) -> UITableView? {
        descendants(controller.view).first { $0.accessibilityIdentifier == id } as? UITableView
    }

    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap { descendants($0) } }

    static func person(uid: Int) -> UserConnectionRecord {
        UserConnectionRecord(uid: uid, name: uid == 9 ? "酒神" : (uid == 14496 ? "yaoguangting" : "用户\(uid)"), rank: 5, coin: 2899, stardust: 26,
                             bio: uid == 9 ? "人生得意须尽欢，莫使金樽空对月" : nil, postCount: 39, commentCount: 1375, fans: 2,
                             followed: uid == 9 || uid == 14496)
    }
}

@MainActor
private final class ConnectionsScreenClient: UserConnectionsLoading {
    var calls: [UserConnectionKind] = []
    var pending: [UserConnectionKind: CheckedContinuation<[UserConnectionRecord], Error>] = [:]
    func loadConnections(kind: UserConnectionKind) async throws -> [UserConnectionRecord] {
        calls.append(kind)
        return try await withCheckedThrowingContinuation { pending[kind] = $0 }
    }
    var followCalls: [(Bool, Int)] = []
    func setFollowing(_ follow: Bool, uid: Int) async throws { followCalls.append((follow, uid)) }
}
