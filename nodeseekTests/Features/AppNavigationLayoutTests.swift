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

    @Test func settingsChooserAppliesLayoutImmediately() throws {
        let settings = makeSettings()
        let viewController = LayoutChooserViewController(mode: .settings, settings: settings)
        viewController.loadViewIfNeeded()

        #expect(viewController.view.layoutTestButton(identifier: "layout-chooser-start-button") == nil)
        let readingCard = try #require(viewController.view.layoutTestView(identifier: "layout-option-reading") as? LayoutOptionCard)
        let tabsCard = try #require(viewController.view.layoutTestView(identifier: "layout-option-tabs") as? LayoutOptionCard)
        #expect(readingCard.isSelected)
        #expect(tabsCard.isSelected == false)

        tabsCard.sendActions(for: .touchUpInside)
        #expect(settings.layout == .tabs)
        #expect(settings.hasConfirmedChoice)
        #expect(tabsCard.isSelected)
        #expect(readingCard.isSelected == false)
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
        let tabBarController = MainTabBarController()
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
