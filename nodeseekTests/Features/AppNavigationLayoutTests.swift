//
//  AppNavigationLayoutTests.swift
//  nodeseekTests
//

import Testing
import UIKit
@testable import nodeseek

@MainActor
struct AppNavigationLayoutTests {
    @Test func layoutDefaultsToReadingAndPersistsChange() throws {
        let settings = makeSettings()
        #expect(settings.layout == .reading)

        var notificationCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: AppNavigationLayoutSettings.didChangeNotification,
            object: settings,
            queue: nil
        ) { _ in
            notificationCount += 1
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        settings.setLayout(.tabs)
        settings.setLayout(.tabs)
        #expect(settings.layout == .tabs)
        // 相同值不重复通知，避免重复替换根界面
        #expect(notificationCount == 1)
    }

    @Test func choicePromptShowsFromPromptVersionUntilConfirmed() throws {
        let settings = makeSettings()
        #expect(settings.needsChoicePrompt(currentVersion: "1.1.1") == false)
        #expect(settings.needsChoicePrompt(currentVersion: "1.2.0"))
        #expect(settings.needsChoicePrompt(currentVersion: "1.10.0"))

        settings.markChoiceConfirmed()
        #expect(settings.needsChoicePrompt(currentVersion: "1.2.0") == false)
    }

    @Test func settingsChooserAppliesLayoutAfterConfirm() throws {
        let settings = makeSettings()
        let viewController = LayoutChooserViewController(mode: .settings, settings: settings)
        viewController.loadViewIfNeeded()

        #expect(viewController.view.layoutTestButton(identifier: "layout-chooser-start-button") == nil)
        let confirmButton = try #require(viewController.view.layoutTestButton(identifier: "layout-chooser-confirm-button"))
        let tabItemsRow = try #require(viewController.view.layoutTestView(identifier: "layout-tab-items-row"))
        let readingCard = try #require(viewController.view.layoutTestView(identifier: "layout-option-reading") as? LayoutOptionCard)
        let tabsCard = try #require(viewController.view.layoutTestView(identifier: "layout-option-tabs") as? LayoutOptionCard)
        #expect(readingCard.isSelected)
        // 当前就是阅读模式：没有确认按钮，也不显示底部栏
        #expect(confirmButton.isHidden)
        #expect(tabItemsRow.isHidden)

        tabsCard.sendActions(for: .touchUpInside)
        #expect(tabsCard.isSelected)
        #expect(settings.layout == .reading)
        #expect(confirmButton.isHidden == false)
        #expect(tabItemsRow.isHidden == false)

        // 选回当前布局，确认按钮收起
        readingCard.sendActions(for: .touchUpInside)
        #expect(confirmButton.isHidden)
        #expect(tabItemsRow.isHidden)

        tabsCard.sendActions(for: .touchUpInside)
        confirmButton.sendActions(for: .touchUpInside)
        #expect(settings.layout == .tabs)
        #expect(settings.hasConfirmedChoice)
    }

    @Test func settingsChooserConfirmButtonDoesNotCoverContentOnSmallScreen() throws {
        let settings = makeSettings()
        let viewController = LayoutChooserViewController(mode: .settings, settings: settings)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        try #require(viewController.view.layoutTestView(identifier: "layout-option-tabs") as? LayoutOptionCard).sendActions(for: .touchUpInside)
        viewController.view.layoutIfNeeded()

        let confirmButton = try #require(viewController.view.layoutTestButton(identifier: "layout-chooser-confirm-button"))
        let tabItemsRow = try #require(viewController.view.layoutTestView(identifier: "layout-tab-items-row"))
        let scrollView = try #require(tabItemsRow.superview?.superview as? UIScrollView)
        // 列表区域止于按钮上方，内容超出时可滚动到底部栏行
        #expect(scrollView.frame.maxY <= confirmButton.frame.minY)
        let rowBottom = tabItemsRow.convert(tabItemsRow.bounds, to: scrollView).maxY
        #expect(rowBottom <= scrollView.contentSize.height)
    }

    @Test func upgradeChooserWaitsForStartButton() throws {
        let settings = makeSettings()
        let viewController = LayoutChooserViewController(mode: .upgradePrompt, settings: settings)
        viewController.loadViewIfNeeded()

        #expect(viewController.isModalInPresentation)
        let tabsCard = try #require(viewController.view.layoutTestView(identifier: "layout-option-tabs") as? LayoutOptionCard)
        tabsCard.sendActions(for: .touchUpInside)
        #expect(settings.layout == .reading)

        let startButton = try #require(viewController.view.layoutTestButton(identifier: "layout-chooser-start-button"))
        startButton.sendActions(for: .touchUpInside)
        #expect(settings.layout == .tabs)
        #expect(settings.hasConfirmedChoice)
    }

    @Test func mePageShowsGuestStateWithLoginButtonAndEntries() throws {
        let viewController = MeViewController()
        viewController.loadViewIfNeeded()
        let view = try #require(viewController.view)

        let loginButton = try #require(view.layoutTestButton(identifier: "me-login-button"))
        #expect(loginButton.isHidden == false)
        for identifier in ["me-discussions-row", "me-comments-row", "me-collections-row", "me-check-in-row", "me-recent-row"] {
            #expect(view.layoutTestView(identifier: identifier) != nil)
        }
        // 未签到 / 未登录时签到行显示“签到”胶囊
        #expect(view.layoutTestView(identifier: "me-check-in-row")?.accessibilityLabel == "每日签到，签到")
    }

    @Test func meProfileCardHandlesTapsAnywhereExceptLoginButton() throws {
        let viewController = MeViewController()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.layoutIfNeeded()
        let card = try #require(viewController.view.layoutTestView(identifier: "me-profile-card") as? UIControl)
        let loginButton = try #require(viewController.view.layoutTestButton(identifier: "me-login-button"))

        // 头像、文字等非按钮区域都落到整卡
        #expect(card.hitTest(CGPoint(x: 20, y: card.bounds.midY), with: nil) === card)
        let loginCenter = loginButton.convert(CGPoint(x: loginButton.bounds.midX, y: loginButton.bounds.midY), to: card)
        #expect(card.hitTest(loginCenter, with: nil)?.isDescendant(of: loginButton) == true)
    }

    @Test func tabBarShowsNotificationUnreadBadge() throws {
        let tabBarController = MainTabBarController(layoutSettings: makeSettings())
        let viewControllers = try #require(tabBarController.viewControllers)
        let items: [UITabBarItem] = viewControllers.compactMap { $0.tabBarItem }
        #expect(items.map(\.title) == ["首页", "通知", "我的"])

        tabBarController.applyNotificationUnreadCount(NodeSeekNotificationUnreadCount(message: 0, atMe: 2, reply: 1, all: 3))
        #expect(items[1].badgeValue == "3")
        tabBarController.applyNotificationUnreadCount(NodeSeekNotificationUnreadCount(message: 0, atMe: 0, reply: 120, all: 120))
        #expect(items[1].badgeValue == "99+")
        tabBarController.applyNotificationUnreadCount(.zero)
        #expect(items[1].badgeValue == nil)
    }

    @Test func tabNavigationHidesTabBarForPushedPages() {
        let root = UIViewController()
        let navigationController = TabRootNavigationController(rootViewController: root)
        let detail = UIViewController()
        navigationController.pushViewController(detail, animated: false)

        #expect(root.hidesBottomBarWhenPushed == false)
        #expect(detail.hidesBottomBarWhenPushed)
    }

    @Test func tabItemsDefaultAndNormalizeStoredValues() throws {
        let settings = makeSettings()
        #expect(settings.tabItems == [.home, .notification, .me])

        var notificationCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: AppNavigationLayoutSettings.tabItemsDidChangeNotification,
            object: settings,
            queue: nil
        ) { _ in
            notificationCount += 1
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        // 顺序错乱、重复、超出上限都会被纠正：首页在前、我的在后、最多 5 项
        settings.setTabItems([.me, .recent, .recent, .search, .home, .discussions, .collections])
        #expect(settings.tabItems == [.home, .recent, .search, .discussions, .me])
        settings.setTabItems([.home, .recent, .search, .discussions, .me])
        #expect(notificationCount == 1)

        settings.setTabItems([])
        #expect(settings.tabItems == [.home, .me])
    }

    @Test func tabBarFollowsTabItemsAndKeepsExistingStacks() throws {
        let settings = makeSettings()
        let tabBarController = MainTabBarController(layoutSettings: settings)
        let meNavigation = try #require(tabBarController.viewControllers?.last as? UINavigationController)
        meNavigation.pushViewController(UIViewController(), animated: false)
        tabBarController.applyNotificationUnreadCount(NodeSeekNotificationUnreadCount(message: 0, atMe: 0, reply: 2, all: 2))
        tabBarController.select(.me)

        settings.setTabItems([.home, .recent, .notification, .me])
        let titles = tabBarController.viewControllers?.compactMap { $0.tabBarItem.title }
        #expect(titles == ["首页", "最近浏览", "通知", "我的"])
        // “我的”里正在看的页面不被重建，选中项不变
        #expect(tabBarController.viewControllers?.last === meNavigation)
        #expect(meNavigation.viewControllers.count == 2)
        #expect(tabBarController.selectedViewController === meNavigation)
        #expect(tabBarController.viewControllers?[2].tabBarItem.badgeValue == "2")

        settings.setTabItems([.home, .me])
        #expect(tabBarController.viewControllers?.count == 2)
    }

    @Test func customizePageInSettingsAppliesChangesImmediately() throws {
        let settings = makeSettings()
        let viewController = TabBarCustomizeViewController(mode: .settings, settings: settings)
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.layoutIfNeeded()

        #expect(viewController.view.layoutTestButton(identifier: "tab-customize-start-button") == nil)
        #expect(viewController.view.layoutTestButton(identifier: "tab-customize-remove-home") == nil)
        #expect(viewController.view.layoutTestButton(identifier: "tab-customize-remove-me") == nil)

        try #require(viewController.view.layoutTestButton(identifier: "tab-customize-add-recent")).sendActions(for: .touchUpInside)
        #expect(settings.tabItems == [.home, .notification, .recent, .me])

        try #require(viewController.view.layoutTestButton(identifier: "tab-customize-remove-notification")).sendActions(for: .touchUpInside)
        #expect(settings.tabItems == [.home, .recent, .me])
    }

    @Test func customizePageStopsAtFiveItems() throws {
        let settings = makeSettings()
        settings.setTabItems([.home, .notification, .recent, .search, .me])
        let viewController = TabBarCustomizeViewController(mode: .settings, settings: settings)
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.layoutIfNeeded()

        let addButton = try #require(viewController.view.layoutTestButton(identifier: "tab-customize-add-discussions"))
        #expect(addButton.tintColor == .tertiaryLabel)
        addButton.sendActions(for: .touchUpInside)
        #expect(settings.tabItems == [.home, .notification, .recent, .search, .me])
    }

    @Test func upgradeChooserGoesToCustomizeStepForTabs() throws {
        let settings = makeSettings()
        let chooser = LayoutChooserViewController(mode: .upgradePrompt, settings: settings)
        let navigationController = UINavigationController(rootViewController: chooser)
        chooser.loadViewIfNeeded()

        let startButton = try #require(chooser.view.layoutTestButton(identifier: "layout-chooser-start-button"))
        #expect(startButton.configuration?.title == "开始使用")
        try #require(chooser.view.layoutTestView(identifier: "layout-option-tabs") as? LayoutOptionCard).sendActions(for: .touchUpInside)
        #expect(startButton.configuration?.title == "下一步")

        startButton.sendActions(for: .touchUpInside)
        let customize = try #require(navigationController.viewControllers.last as? TabBarCustomizeViewController)
        // 进入第 2 步还没生效
        #expect(settings.layout == .reading)

        customize.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        customize.view.layoutIfNeeded()
        try #require(customize.view.layoutTestButton(identifier: "tab-customize-add-collections")).sendActions(for: .touchUpInside)
        try #require(customize.view.layoutTestButton(identifier: "tab-customize-start-button")).sendActions(for: .touchUpInside)
        #expect(settings.layout == .tabs)
        #expect(settings.hasConfirmedChoice)
        #expect(settings.tabItems == [.home, .notification, .collections, .me])
    }

    @Test func customizeSkipUsesDefaultItems() throws {
        let settings = makeSettings()
        settings.setTabItems([.home, .search, .me])
        var finished: [MainTabItem]?
        let viewController = TabBarCustomizeViewController(mode: .onboarding, settings: settings)
        viewController.onFinish = { finished = $0 }
        viewController.loadViewIfNeeded()

        let skipItem = try #require(viewController.navigationItem.rightBarButtonItem)
        #expect(skipItem.title == "跳过")
        _ = skipItem.target?.perform(skipItem.action)
        #expect(finished == MainTabItem.defaultItems)
    }

    @Test func settingsChooserShowsTabItemsSummary() throws {
        let settings = makeSettings()
        settings.setTabItems([.home, .notification, .recent, .me])
        settings.setLayout(.tabs)
        let viewController = LayoutChooserViewController(mode: .settings, settings: settings)
        viewController.loadViewIfNeeded()
        viewController.beginAppearanceTransition(true, animated: false)
        viewController.endAppearanceTransition()

        let row = try #require(viewController.view.layoutTestView(identifier: "layout-tab-items-row"))
        #expect(row.accessibilityLabel == "底部栏，首页、通知、最近浏览、我的")
    }

    private func makeSettings() -> AppNavigationLayoutSettings {
        let defaults = UserDefaults(suiteName: "app-navigation-layout-\(UUID().uuidString)")!
        return AppNavigationLayoutSettings(userDefaults: defaults)
    }
}

private extension UIView {
    func layoutTestView(identifier: String) -> UIView? {
        if accessibilityIdentifier == identifier { return self }
        for subview in subviews {
            if let match = subview.layoutTestView(identifier: identifier) { return match }
        }
        return nil
    }

    func layoutTestButton(identifier: String) -> UIButton? {
        layoutTestView(identifier: identifier) as? UIButton
    }
}
