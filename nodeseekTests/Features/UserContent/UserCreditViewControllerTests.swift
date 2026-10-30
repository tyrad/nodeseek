import UIKit
import XCTest
@testable import nodeseek

@MainActor
final class UserCreditViewControllerTests: XCTestCase {
    func testCreditRendersSkeletonThemesLargeTextAndPagination() async throws {
        let client = CreditScreenClient()
        let controller = UserCreditViewController(uid: 31037, client: client)
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
        try capture(window, name: "credit-skeleton")
        client.pending?.resume(returning: Self.page)
        client.pending = nil
        let table = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UITableView }.first)
        for _ in 0..<100 where table.numberOfRows(inSection: 0) != 4 { await Task.yield() }
        XCTAssertEqual(table.numberOfRows(inSection: 0), 4)
        let owner = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UILabel }.first { $0.accessibilityIdentifier == "credit-owner" })
        XCTAssertEqual(owner.text, "缭雾")
        for (style, name) in [(UIUserInterfaceStyle.light, "light"), (.dark, "dark")] {
            window.overrideUserInterfaceStyle = style
            try await Task.sleep(nanoseconds: 150_000_000)
            window.layoutIfNeeded()
            try capture(window, name: "credit-\(name)")
            XCTAssertTrue(descendants(controller.view).compactMap { $0 as? UILabel }.contains { $0.text == "签到收益6个鸡腿" })
        }
        navigation.setOverrideTraitCollection(UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge), forChild: controller)
        table.reloadData()
        window.layoutIfNeeded()
        table.setContentOffset(CGPoint(x: 0, y: -table.adjustedContentInset.top), animated: false)
        try capture(window, name: "credit-large-text")
        navigation.setOverrideTraitCollection(nil, forChild: controller)
        table.reloadData()
        window.layoutIfNeeded()
        let more = try XCTUnwrap(descendants(table).compactMap { $0 as? UIButton }.first { $0.title(for: .normal) == "加载更多" })
        more.sendActions(for: .touchUpInside)
        for _ in 0..<100 where table.numberOfRows(inSection: 0) != 5 { await Task.yield() }
        XCTAssertEqual(table.numberOfRows(inSection: 0), 5)
        XCTAssertEqual(client.pages, [1, 2])
        XCTAssertTrue(descendants(table).compactMap { $0 as? UIButton }.contains { $0.title(for: .normal) == "没有更多记录" })
        navigation.popViewController(animated: true)
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(navigation.topViewController === root)
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

    static let page = UserCreditPage(records: [
        UserCreditRecord(diff: 1, balance: 1758, reason: "回帖奖励", createdAt: "2026-10-30T01:06:08.000Z"),
        UserCreditRecord(diff: 6, balance: 1755, reason: "签到收益6个鸡腿", createdAt: "2026-10-29T19:56:20.000Z"),
        UserCreditRecord(diff: -5, balance: 1749, reason: "扣减示例（模拟数据）", createdAt: "2026-10-29T18:56:20.000Z"),
        UserCreditRecord(diff: 1, balance: 1754, reason: "被bigbutt投喂鸡腿", createdAt: "2026-10-28T08:33:48.000Z")
    ], total: 21)
}

@MainActor
private final class CreditScreenClient: UserCreditLoading {
    var pending: CheckedContinuation<UserCreditPage, Error>?
    var pages: [Int] = []
    func loadCredits(page: Int) async throws -> UserCreditPage {
        pages.append(page)
        if page == 1 { return try await withCheckedThrowingContinuation { pending = $0 } }
        return UserCreditPage(records: [UserCreditRecord(diff: 90, balance: 90, reason: "注册奖励", createdAt: "2025-04-27T14:29:22.000Z")], total: 21)
    }
    func loadProfile(uid: Int) async throws -> UserProfileRecord {
        UserProfileRecord(uid: uid, name: "缭雾", rank: 4, coin: 1758, stardust: 11, bio: "", readme: "", createdAt: nil,
                          postCount: 19, commentCount: 550, follows: 0, fans: 2, collectionCount: nil, roleNames: [])
    }
}
