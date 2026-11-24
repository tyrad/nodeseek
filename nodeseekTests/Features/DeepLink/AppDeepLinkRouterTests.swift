import Testing
import UIKit
@testable import nodeseek

@MainActor
struct AppDeepLinkRouterTests {
    @Test func startupKeepsLatestLinkUntilNavigationIsReady() throws {
        let app = AppRouter()
        let router = AppDeepLinkRouter()
        for uid in [1, 2] {
            let url = try #require(URL(string: "nsconnect://user/\(uid)"))
            router.open(.user(uid), url: url, in: app)
        }
        let nav = try #require(app.makeRootViewController() as? UINavigationController)
        #expect(router.openPending(in: app))
        #expect(nav.topViewController is UserProfileViewController)
        #expect(!router.openPending(in: app))
        #expect(nav.viewControllers.count == 2)
    }

    @Test func activeLoginKeepsItsNavigationStack() throws {
        let app = AppRouter()
        let nav = try #require(app.makeRootViewController() as? UINavigationController)
        let source = try #require(nav.topViewController)
        LoginWebViewController.open(from: source)
        let url = try #require(URL(string: "nsconnect://user/1"))
        AppDeepLinkRouter().open(.user(1), url: url, in: app)
        #expect(nav.topViewController is LoginWebViewController)
        #expect(nav.viewControllers.count == 2)
    }

    @Test(arguments: [false, true])
    func searchInTabsReusesTheDestination(hasSearchTab: Bool) throws {
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppNavigationLayoutSettings(userDefaults: defaults)
        settings.setLayout(.tabs)
        if hasSearchTab { settings.setTabItems([.home, .search, .me]) }
        let app = AppRouter(layoutSettings: settings)
        let nav = try #require(app.makeRootViewController() as? UINavigationController)
        let tabs = try #require(nav.topViewController as? MainTabBarController)
        let router = AppDeepLinkRouter()
        let url = try #require(URL(string: "nsconnect://search?q=Swift&scope=user"))
        let route = try #require(AppDeepLink.route(for: url))

        router.open(route, url: url, in: app)
        let target = try #require((hasSearchTab ? tabs.selectedViewController : nav.topViewController) as? SearchViewController)
        #expect(target.isShowingDeepLinkSearch(query: "Swift", scope: .user))
        router.open(route, url: url, in: app)
        #expect(nav.viewControllers.count == (hasSearchTab ? 1 : 2))
        #expect((hasSearchTab ? tabs.selectedViewController : nav.topViewController) === target)

        // 用户在搜索页改搜其他关键词后，再次打开同一深链应重新提交，不能被防重吞掉。
        target.submitDeepLinkSearch(query: "Rust", scope: .post)
        #expect(target.isShowingDeepLinkSearch(query: "Rust", scope: .post))
        #expect(!target.isShowingDeepLinkSearch(query: "Swift", scope: .user))
        router.open(route, url: url, in: app)
        #expect(nav.viewControllers.count == (hasSearchTab ? 1 : 2))
        #expect((hasSearchTab ? tabs.selectedViewController : nav.topViewController) === target)
        #expect(target.isShowingDeepLinkSearch(query: "Swift", scope: .user))
    }
}
