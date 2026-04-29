//
//  PostListViewControllerTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/4/28.
//

import Testing
import UIKit
@testable import nodeseek

@MainActor
struct PostListViewControllerTests {
    @Test func sortToggleButtonPeeksFromRightAndExpandsOnTap() throws {
        let presenter = SpyPostListPresenter()
        let viewController = PostListViewController(presenter: presenter)
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)

        viewController.renderSortMode(.replyTime)
        viewController.view.layoutIfNeeded()

        let button = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-list-sort-toggle"))
        #expect(button.title(for: .normal) == nil)
        #expect(button.image(for: .normal) != nil)
        #expect(button.backgroundColor == .label)
        #expect(button.layer.maskedCorners == [.layerMinXMinYCorner, .layerMinXMaxYCorner])
        #expect(button.bounds.height >= 42)
        #expect(button.bounds.width >= 56)
        #expect(button.bounds.width <= 60)
        #expect(button.frame.maxX > viewController.view.bounds.maxX)
        #expect(button.frame.maxY < viewController.view.bounds.maxY - 50)
        #expect(button.titleLabel?.font.pointSize ?? 0 >= 13)
        #expect(button.titleLabel?.numberOfLines == 1)
        #expect(button.titleLabel?.lineBreakMode == .byTruncatingTail)
        #expect(button.configuration?.titleLineBreakMode == .byTruncatingTail)

        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        button.sendActions(for: .touchUpInside)
        viewController.view.layoutIfNeeded()
        UIView.setAnimationsEnabled(animationsWereEnabled)

        #expect(presenter.toggleSortCount == 1)
        #expect(button.title(for: .normal) == "按回复时间排序")
        #expect(button.bounds.width >= 140)
        #expect(abs(button.frame.maxX - viewController.view.bounds.maxX) < 0.5)

        viewController.renderSortMode(.postTime)
        #expect(button.title(for: .normal) == "按发帖时间排序")
    }

    @Test func topNavigationUsesDenseReadingTabStyle() throws {
        let presenter = SpyPostListPresenter()
        let viewController = PostListViewController(presenter: presenter)
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.renderCategories([.all, .daily, .tech, .info], selected: .all)
        viewController.view.layoutIfNeeded()

        let menuButton = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-list-menu-button"))
        #expect(menuButton.bounds.width == 40)
        #expect(menuButton.bounds.height == 40)
        #expect(menuButton.backgroundColor == .clear)
        #expect(menuButton.layer.borderWidth == 0)
        #expect(menuButton.layer.cornerRadius == 0)
        #expect(menuButton.configuration?.image != nil)
        #expect(menuButton.configuration?.image?.renderingMode == .alwaysTemplate)

        let selectedTab = try #require(viewController.view.firstButton(title: "全部"))
        let unselectedTab = try #require(viewController.view.firstButton(title: "日常"))
        #expect(selectedTab.titleLabel?.font.pointSize == 17)
        #expect(selectedTab.titleLabel?.font.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
        #expect(unselectedTab.titleLabel?.font.pointSize == 17)
        #expect(unselectedTab.titleColor(for: .normal) == .secondaryLabel)
        let selectedTabFrame = selectedTab.convert(selectedTab.bounds, to: viewController.view)
        let menuButtonFrame = menuButton.convert(menuButton.bounds, to: viewController.view)
        #expect(abs(selectedTabFrame.minY - menuButtonFrame.minY) < 1)
        #expect(abs(selectedTabFrame.height - menuButtonFrame.height) < 1)
    }

    @Test func menuButtonPresentsSideMenuWithAccountHeaderAndSettingsButton() throws {
        let presenter = SpyPostListPresenter()
        let viewController = PostListViewController(presenter: presenter)
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.layoutIfNeeded()

        let menuButton = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-list-menu-button"))
        let sideMenu = try #require(viewController.view.firstView(accessibilityIdentifier: "post-list-side-menu"))
        let backdrop = try #require(viewController.view.firstView(accessibilityIdentifier: "post-list-side-menu-backdrop"))
        let avatar = try #require(viewController.view.firstImageView(accessibilityIdentifier: "post-list-side-menu-avatar"))
        let nameLabel = try #require(viewController.view.firstLabel(accessibilityIdentifier: "post-list-side-menu-name-label"))
        let statsLabel = try #require(viewController.view.firstLabel(accessibilityIdentifier: "post-list-side-menu-stats-label"))
        let accountHeaderButton = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-list-side-menu-account-header-button"))
        let settingsButton = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-list-side-menu-settings-button"))
        let sideMenuHost = viewController.children.first {
            $0.view.firstView(accessibilityIdentifier: "post-list-side-menu") != nil
        }

        #expect(sideMenuHost != nil)
        #expect(sideMenu.frame.maxX <= 0.5)
        #expect(backdrop.isHidden == true)
        #expect(avatar.image != nil)
        #expect(nameLabel.text == "未登录")
        #expect(statsLabel.text == "登录后同步账号信息")
        #expect(viewController.view.firstButton(accessibilityIdentifier: "post-list-side-menu-login-button") == nil)
        #expect(accountHeaderButton.accessibilityLabel == "登录账号")
        #expect(settingsButton.configuration?.title == "设置")
        #expect(settingsButton.configuration?.image != nil)

        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        menuButton.sendActions(for: .touchUpInside)
        viewController.view.layoutIfNeeded()
        UIView.setAnimationsEnabled(animationsWereEnabled)

        #expect(abs(sideMenu.frame.minX) < 0.5)
        #expect(backdrop.isHidden == false)
        #expect(backdrop.alpha == 1)
        #expect(accountHeaderButton.frame.contains(avatar.frame))
        #expect(settingsButton.frame.maxY < viewController.view.bounds.maxY)

        UIView.setAnimationsEnabled(false)
        accountHeaderButton.sendActions(for: .touchUpInside)
        viewController.view.layoutIfNeeded()
        UIView.setAnimationsEnabled(animationsWereEnabled)

        #expect(presenter.didTapLoginCount == 1)
        #expect(sideMenu.frame.maxX <= 0.5)
        #expect(backdrop.isHidden == true)
    }

    @Test func renderAccountUpdatesSideMenuIdentityAndHidesLoginButton() throws {
        let presenter = SpyPostListPresenter()
        let viewController = PostListViewController(presenter: presenter)
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.layoutIfNeeded()

        viewController.renderAccount(AccountResponse(
            displayName: "缭雾",
            isLoggedIn: true,
            avatarURL: URL(string: "https://www.nodeseek.com/avatar/31037.png"),
            profileURL: URL(string: "https://www.nodeseek.com/space/31037"),
            stats: ["等级 Lv 1", "鸡腿 306"]
        ))
        viewController.view.layoutIfNeeded()

        let nameLabel = try #require(viewController.view.firstLabel(accessibilityIdentifier: "post-list-side-menu-name-label"))
        let statsLabel = try #require(viewController.view.firstLabel(accessibilityIdentifier: "post-list-side-menu-stats-label"))
        let accountHeaderButton = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-list-side-menu-account-header-button"))

        #expect(nameLabel.text == "缭雾")
        #expect(statsLabel.text == "等级 Lv 1 · 鸡腿 306")
        #expect(accountHeaderButton.accessibilityLabel == "账号信息")
    }
}

private final class SpyPostListPresenter: PostListPresenterProtocol {
    private(set) var viewDidLoadCount = 0
    private(set) var toggleSortCount = 0
    private(set) var didTapLoginCount = 0

    func viewDidLoad() {
        viewDidLoadCount += 1
    }

    func didSelectCategory(_ category: PostListCategory) {}

    func didToggleSortMode() {
        toggleSortCount += 1
    }

    func didTapLogin() {
        didTapLoginCount += 1
    }

    func didPullToRefresh() {}

    func didSelectPost(at index: Int) {}

    func didApproachBottom(currentIndex: Int, totalCount: Int) {}
}

private extension UIView {
    func firstButton(accessibilityIdentifier: String) -> UIButton? {
        if let button = self as? UIButton, button.accessibilityIdentifier == accessibilityIdentifier {
            return button
        }

        for subview in subviews {
            if let matched = subview.firstButton(accessibilityIdentifier: accessibilityIdentifier) {
                return matched
            }
        }

        return nil
    }

    func firstButton(title: String) -> UIButton? {
        if let button = self as? UIButton, button.title(for: .normal) == title {
            return button
        }

        for subview in subviews {
            if let matched = subview.firstButton(title: title) {
                return matched
            }
        }

        return nil
    }

    func firstView(accessibilityIdentifier: String) -> UIView? {
        if self.accessibilityIdentifier == accessibilityIdentifier {
            return self
        }

        for subview in subviews {
            if let matched = subview.firstView(accessibilityIdentifier: accessibilityIdentifier) {
                return matched
            }
        }

        return nil
    }

    func firstImageView(accessibilityIdentifier: String) -> UIImageView? {
        if let imageView = self as? UIImageView, imageView.accessibilityIdentifier == accessibilityIdentifier {
            return imageView
        }

        for subview in subviews {
            if let matched = subview.firstImageView(accessibilityIdentifier: accessibilityIdentifier) {
                return matched
            }
        }

        return nil
    }

    func firstLabel(accessibilityIdentifier: String) -> UILabel? {
        if let label = self as? UILabel, label.accessibilityIdentifier == accessibilityIdentifier {
            return label
        }

        for subview in subviews {
            if let matched = subview.firstLabel(accessibilityIdentifier: accessibilityIdentifier) {
                return matched
            }
        }

        return nil
    }
}
