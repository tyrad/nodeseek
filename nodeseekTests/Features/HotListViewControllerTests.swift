//
//  HotListViewControllerTests.swift
//  nodeseekTests
//

import Foundation
import Testing
import UIKit
@testable import nodeseek

private final class HotListFakeLoader: @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [URL] = []
    private var _fails = false

    var requests: [URL] { lock.withLock { _requests } }
    func setFails(_ fails: Bool) { lock.withLock { _fails = fails } }

    func load(_ url: URL) throws -> Data {
        let fails = lock.withLock { () -> Bool in
            _requests.append(url)
            return _fails
        }
        if fails { throw URLError(.notConnectedToInternet) }
        let json = """
        {"updated_at": 1795508253, "posts": [
          {"post": {"id": 11, "title": "第一名", "author": "alice", "author_id": 5, "views": 10, "comments": 2, "category": "daily", "post_timestamp": 1795508000}, "score": 99.5},
          {"post": {"id": 12, "title": "第二名", "author": "bob", "author_id": 6, "views": 8, "comments": 1, "category": "trade"}, "score": 50}
        ]}
        """
        return Data(json.utf8)
    }
}

@MainActor
struct HotListViewControllerTests {
    private func makeSettings() -> HotListSourceSettings {
        HotListSourceSettings(userDefaults: UserDefaults(suiteName: "HotListViewControllerTests.\(UUID().uuidString)")!)
    }

    /// 页面在显示时才请求，需挂到窗口上触发生命周期。
    private func makeViewController(
        _ loader: HotListFakeLoader,
        settings: HotListSourceSettings? = nil
    ) -> (HotListViewController, UIWindow) {
        let settings = settings ?? makeSettings()
        let repository = HotListRepository(settings: settings, loader: { try loader.load($0) })
        let viewController = HotListViewController(repository: repository, settings: settings)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UINavigationController(rootViewController: viewController)
        window.makeKeyAndVisible()
        viewController.view.layoutIfNeeded()
        return (viewController, window)
    }

    private func table(_ viewController: HotListViewController, _ kind: HotListKind) -> UITableView? {
        viewController.page(for: kind)?.viewIfLoaded == nil ? nil : viewController.page(for: kind)?.tableView
    }

    @Test func tabsLiveInNavigationBarAndRealtimeLoadsFirst() async throws {
        let loader = HotListFakeLoader()
        let (viewController, window) = makeViewController(loader)
        var selected: PostSummary?
        viewController.onSelectPost = { selected = $0 }

        // 首次加载先显示骨架屏
        #expect(table(viewController, .realtime)?.backgroundView is HotListSkeletonView)

        let titleView = try #require(viewController.navigationItem.titleView)
        #expect(titleView.hotListFirstView(accessibilityIdentifier: "hot-list-tab-realtime") != nil)
        #expect(titleView.hotListFirstView(accessibilityIdentifier: "hot-list-tab-weekly") != nil)
        #expect(viewController.navigationItem.rightBarButtonItem?.accessibilityIdentifier == "hot-list-settings-button")

        try await waitUntil { table(viewController, .realtime)?.numberOfRows(inSection: 0) == 2 }
        // 其他榜单还没显示，不应提前请求
        #expect(loader.requests == [HotListKind.realtime.defaultURL])

        let page = try #require(viewController.page(for: .realtime))
        page.tableView(page.tableView, didSelectRowAt: IndexPath(row: 1, section: 0))
        #expect(selected?.id == "12")
        #expect(selected?.url.absoluteString == "https://www.nodeseek.com/post-12-1")
        withExtendedLifetime(window) {}
    }

    @Test func tappingTabShowsSeparateListForThatKind() async throws {
        let loader = HotListFakeLoader()
        let (viewController, window) = makeViewController(loader)
        try await waitUntil { table(viewController, .realtime)?.numberOfRows(inSection: 0) == 2 }

        let weeklyTab = try #require(viewController.navigationItem.titleView?.hotListFirstView(accessibilityIdentifier: "hot-list-tab-weekly") as? UIButton)
        weeklyTab.sendActions(for: .touchUpInside)

        try await waitUntil { table(viewController, .weekly)?.numberOfRows(inSection: 0) == 2 }
        #expect(viewController.selectedKind == .weekly)
        #expect(loader.requests.last == HotListKind.weekly.defaultURL)
        #expect(table(viewController, .weekly) !== table(viewController, .realtime))
        withExtendedLifetime(window) {}
    }

    @Test func savedOrderPutsWeeklyFirstAndOpensIt() async throws {
        let loader = HotListFakeLoader()
        let settings = makeSettings()
        settings.setKindOrder([.weekly, .realtime, .daily])
        let (viewController, window) = makeViewController(loader, settings: settings)

        #expect(viewController.selectedKind == .weekly)
        let stack = try #require(viewController.navigationItem.titleView as? UIStackView)
        #expect(stack.arrangedSubviews.map(\.accessibilityIdentifier) == ["hot-list-tab-weekly", "hot-list-tab-realtime", "hot-list-tab-daily"])
        try await waitUntil { table(viewController, .weekly)?.numberOfRows(inSection: 0) == 2 }
        #expect(loader.requests == [HotListKind.weekly.defaultURL])

        // 设置页改顺序后标签立即重排，当前榜单不变
        settings.setKindOrder([.daily, .weekly, .realtime])
        #expect(stack.arrangedSubviews.map(\.accessibilityIdentifier) == ["hot-list-tab-daily", "hot-list-tab-weekly", "hot-list-tab-realtime"])
        #expect(viewController.selectedKind == .weekly)
        withExtendedLifetime(window) {}
    }

    @Test func failureWithoutCacheShowsRetryAndRecovers() async throws {
        let loader = HotListFakeLoader()
        loader.setFails(true)
        let (viewController, window) = makeViewController(loader)

        try await waitUntil { table(viewController, .realtime)?.backgroundView?.accessibilityIdentifier == "hot-list-error" }
        let tableView = try #require(table(viewController, .realtime))
        let retry = try #require(tableView.backgroundView?.hotListFirstView(accessibilityIdentifier: "hot-list-retry-button") as? UIButton)

        loader.setFails(false)
        retry.sendActions(for: .primaryActionTriggered)
        try await waitUntil { tableView.numberOfRows(inSection: 0) == 2 }
        #expect(tableView.backgroundView == nil)
        withExtendedLifetime(window) {}
    }

    @Test func settingsScreenListsSourceAndThreeEditableURLs() {
        let repository = HotListRepository(settings: makeSettings(), loader: { _ in Data() })
        let viewController = HotListSettingsViewController(repository: repository, settings: makeSettings())
        viewController.loadViewIfNeeded()

        #expect(viewController.tableView.numberOfSections == 4)
        #expect(viewController.tableView.numberOfRows(inSection: 0) == 3)
        #expect(viewController.tableView.numberOfRows(inSection: 1) == 3)
        #expect(viewController.tableView.numberOfRows(inSection: 2) == 3)
        let cell = viewController.tableView(viewController.tableView, cellForRowAt: IndexPath(row: 2, section: 2))
        let field = (cell as? HotListURLFieldCell)?.textField
        #expect(field?.text == HotListKind.weekly.defaultURL.absoluteString)
        #expect(field?.keyboardType == .URL)
    }

    @Test func movingOrderRowSavesNewOrder() {
        let settings = makeSettings()
        let repository = HotListRepository(settings: settings, loader: { _ in Data() })
        let viewController = HotListSettingsViewController(repository: repository, settings: settings)
        viewController.loadViewIfNeeded()

        #expect(viewController.tableView.isEditing)
        #expect(viewController.tableView(viewController.tableView, canMoveRowAt: IndexPath(row: 0, section: 0)))
        #expect(!viewController.tableView(viewController.tableView, canMoveRowAt: IndexPath(row: 0, section: 2)))
        viewController.tableView(viewController.tableView, moveRowAt: IndexPath(row: 2, section: 0), to: IndexPath(row: 0, section: 0))

        #expect(settings.kindOrder == [.weekly, .realtime, .daily])
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        let step: UInt64 = 25_000_000
        var waited: UInt64 = 0
        while waited < 2_000_000_000 {
            if condition() { return }
            try await Task.sleep(nanoseconds: step)
            waited += step
        }
        Issue.record("waitUntil timed out")
    }
}

private extension UIView {
    func hotListFirstView(accessibilityIdentifier: String) -> UIView? {
        if self.accessibilityIdentifier == accessibilityIdentifier { return self }
        for subview in subviews {
            if let matched = subview.hotListFirstView(accessibilityIdentifier: accessibilityIdentifier) {
                return matched
            }
        }
        return nil
    }
}
