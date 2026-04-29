//
//  AccountViewControllerTests.swift
//  nodeseekTests
//

import Testing
import UIKit
@testable import nodeseek

@MainActor
struct AccountViewControllerTests {
    @Test func loginButtonHiddenBeforeAccountStateLoads() throws {
        let presenter = SpyAccountPresenter()
        let viewController = AccountViewController(presenter: presenter)

        viewController.loadViewIfNeeded()

        let button = try #require(viewController.view.firstButton(accessibilityIdentifier: "account-login-button"))
        #expect(button.isHidden)
    }

    @Test func showsLoginButtonAndSendsTapToPresenter() throws {
        let presenter = SpyAccountPresenter()
        let viewController = AccountViewController(presenter: presenter)

        viewController.loadViewIfNeeded()
        viewController.render(AccountResponse(displayName: "游客", isLoggedIn: false))

        let button = try #require(viewController.view.firstButton(accessibilityIdentifier: "account-login-button"))
        #expect(button.configuration?.title == "登录")

        button.sendActions(for: .touchUpInside)

        #expect(presenter.didTapLoginCount == 1)
    }

    @Test func renderLoggedInHidesLoginButton() throws {
        let presenter = SpyAccountPresenter()
        let viewController = AccountViewController(presenter: presenter)

        viewController.loadViewIfNeeded()
        viewController.render(AccountResponse(displayName: "mistj", isLoggedIn: true))

        let button = try #require(viewController.view.firstButton(accessibilityIdentifier: "account-login-button"))
        #expect(button.isHidden)
    }

    @Test func renderLoggedInShowsAvatarNameAndStats() throws {
        let presenter = SpyAccountPresenter()
        let viewController = AccountViewController(presenter: presenter)

        viewController.loadViewIfNeeded()
        viewController.render(AccountResponse(
            displayName: "缭雾",
            isLoggedIn: true,
            avatarURL: URL(string: "https://www.nodeseek.com/avatar/31037.png"),
            profileURL: URL(string: "https://www.nodeseek.com/space/31037"),
            stats: ["等级 Lv 1", "鸡腿 306"]
        ))

        let statusLabel = try #require(viewController.view.firstLabel(accessibilityIdentifier: "account-status-label"))
        let statsLabel = try #require(viewController.view.firstLabel(accessibilityIdentifier: "account-stats-label"))
        let avatarView = try #require(viewController.view.firstImageView(accessibilityIdentifier: "account-avatar-image"))
        #expect(statusLabel.text == "缭雾 · 已登录")
        #expect(statsLabel.text == "等级 Lv 1 · 鸡腿 306")
        #expect(avatarView.isHidden == false)
    }
}

private final class SpyAccountPresenter: AccountPresenterProtocol {
    private(set) var viewDidLoadCount = 0
    private(set) var didTapLoginCount = 0

    func viewDidLoad() {
        viewDidLoadCount += 1
    }

    func didTapLogin() {
        didTapLoginCount += 1
    }
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
}
