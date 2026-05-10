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
        let viewController = makePostListViewController(presenter: presenter)
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
        #expect(button.alpha < 1)
        #expect(button.alpha >= 0.5)
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

        #expect(button.title(for: .normal) == "回复时间优先")
        #expect(button.alpha == 1)
        #expect(button.bounds.width >= 168)
        #expect(button.configuration?.titleTextAttributesTransformer != nil)
        #expect(button.intrinsicContentSize.width <= button.bounds.width)
        #expect(abs(button.frame.maxX - viewController.view.bounds.maxX) < 0.5)

        viewController.renderSortMode(.postTime)
        #expect(button.title(for: .normal) == "发帖时间优先")
        #expect(button.bounds.width >= 168)
        #expect(button.intrinsicContentSize.width <= button.bounds.width)
    }

    @Test func topNavigationUsesDenseReadingTabStyle() throws {
        let presenter = SpyPostListPresenter()
        let viewController = makePostListViewController(presenter: presenter)
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
        let selectedTitleWidth = try #require(selectedTab.titleLabel?.intrinsicContentSize.width)
        let unselectedTitleWidth = try #require(unselectedTab.titleLabel?.intrinsicContentSize.width)
        #expect(selectedTab.bounds.width <= selectedTitleWidth + 8)
        #expect(unselectedTab.bounds.width <= unselectedTitleWidth + 8)
        let selectedTabFrame = selectedTab.convert(selectedTab.bounds, to: viewController.view)
        let menuButtonFrame = menuButton.convert(menuButton.bounds, to: viewController.view)
        #expect(abs(selectedTabFrame.minY - menuButtonFrame.minY) < 1)
        #expect(abs(selectedTabFrame.height - menuButtonFrame.height) < 1)
    }

    @Test func tappingSelectedCategoryRequestsFirstPageReload() throws {
        let presenter = SpyPostListPresenter()
        let viewController = makePostListViewController(presenter: presenter)
        viewController.loadViewIfNeeded()
        viewController.renderCategories([.all], selected: .all)

        let selectedTab = try #require(viewController.view.firstButton(title: "全部"))
        selectedTab.sendActions(for: .touchUpInside)

        #expect(presenter.reselectedCategories == [.all])
        #expect(presenter.selectedCategories.isEmpty)
    }

    @Test func detailTestSubmitsProvidedURL() throws {
        let presenter = SpyPostListPresenter()
        let viewController = makePostListViewController(
            presenter: presenter,
            detailTestURLProvider: {
                "https://www.nodeseek.com/post-717963-6#52"
            }
        )

        viewController.openDetailTestURLFromPasteboard()

        #expect(presenter.submittedDetailTestURL == "https://www.nodeseek.com/post-717963-6#52")
    }

    @Test func menuButtonPresentsSideMenuWithAccountHeaderSettingsAndMovesDebugEntriesToSettings() throws {
        let presenter = SpyPostListPresenter()
        let viewController = makePostListViewController(presenter: presenter)
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
        let newDiscussionButton = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-list-side-menu-new-discussion-button"))
        let checkInButton = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-list-side-menu-check-in-button"))
        let notificationButton = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-list-side-menu-notification-button"))
        let searchButton = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-list-side-menu-search-button"))
        let recentVisitedButton = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-list-side-menu-recent-visited-button"))
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
        #expect(viewController.view.firstView(accessibilityIdentifier: "post-list-side-menu-account-debug-text-view") == nil)
        #expect(viewController.view.firstButton(accessibilityIdentifier: "post-list-side-menu-account-debug-copy-button") == nil)
        #expect(viewController.view.firstButton(accessibilityIdentifier: "post-list-side-menu-detail-test-button") == nil)
        #expect(viewController.view.firstButton(accessibilityIdentifier: "post-list-side-menu-log-file-button") == nil)
        #expect(accountHeaderButton.accessibilityLabel == "登录账号")
        #expect(newDiscussionButton.configuration?.title == "发帖")
        #expect(newDiscussionButton.configuration?.image != nil)
        #expect(checkInButton.configuration?.title == "签到")
        #expect(checkInButton.configuration?.image != nil)
        #expect(notificationButton.configuration?.title == "通知")
        #expect(notificationButton.configuration?.image != nil)
        #expect(searchButton.configuration?.title == "搜一搜")
        #expect(searchButton.configuration?.image != nil)
        #expect(recentVisitedButton.configuration?.title == "最近浏览")
        #expect(recentVisitedButton.configuration?.image != nil)
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
        #expect(recentVisitedButton.frame.maxY < settingsButton.frame.minY)
        #expect(searchButton.frame.maxY < recentVisitedButton.frame.minY)
        #expect(notificationButton.frame.maxY < searchButton.frame.minY)
        #expect(checkInButton.frame.maxY < notificationButton.frame.minY)
        #expect(newDiscussionButton.frame.maxY < checkInButton.frame.minY)
        #expect(settingsButton.frame.maxY < viewController.view.bounds.maxY)

        UIView.setAnimationsEnabled(false)
        recentVisitedButton.sendActions(for: .touchUpInside)
        viewController.view.layoutIfNeeded()
        UIView.setAnimationsEnabled(animationsWereEnabled)

        #expect(presenter.didTapRecentVisitedCount == 1)
        #expect(sideMenu.frame.maxX <= 0.5)
        #expect(backdrop.isHidden == true)

        UIView.setAnimationsEnabled(false)
        menuButton.sendActions(for: .touchUpInside)
        viewController.view.layoutIfNeeded()
        searchButton.sendActions(for: .touchUpInside)
        viewController.view.layoutIfNeeded()
        UIView.setAnimationsEnabled(animationsWereEnabled)

        #expect(presenter.didTapSearchCount == 1)
        #expect(sideMenu.frame.maxX <= 0.5)
        #expect(backdrop.isHidden == true)

        UIView.setAnimationsEnabled(false)
        menuButton.sendActions(for: .touchUpInside)
        viewController.view.layoutIfNeeded()
        newDiscussionButton.sendActions(for: .touchUpInside)
        viewController.view.layoutIfNeeded()
        UIView.setAnimationsEnabled(animationsWereEnabled)

        #expect(presenter.didTapLoginCount == 1)
        #expect(presenter.didTapNewDiscussionCount == 0)
        #expect(sideMenu.frame.maxX <= 0.5)

        UIView.setAnimationsEnabled(false)
        menuButton.sendActions(for: .touchUpInside)
        viewController.view.layoutIfNeeded()
        checkInButton.sendActions(for: .touchUpInside)
        viewController.view.layoutIfNeeded()
        UIView.setAnimationsEnabled(animationsWereEnabled)

        #expect(presenter.didTapLoginCount == 2)
        #expect(presenter.didTapCheckInCount == 0)
        #expect(sideMenu.frame.maxX <= 0.5)

        UIView.setAnimationsEnabled(false)
        menuButton.sendActions(for: .touchUpInside)
        viewController.view.layoutIfNeeded()
        settingsButton.sendActions(for: .touchUpInside)
        viewController.view.layoutIfNeeded()
        UIView.setAnimationsEnabled(animationsWereEnabled)

        #expect(presenter.didTapSettingsCount == 1)
        #expect(sideMenu.frame.maxX <= 0.5)
        #expect(backdrop.isHidden == true)

        UIView.setAnimationsEnabled(false)
        menuButton.sendActions(for: .touchUpInside)
        viewController.view.layoutIfNeeded()
        accountHeaderButton.sendActions(for: .touchUpInside)
        viewController.view.layoutIfNeeded()
        UIView.setAnimationsEnabled(animationsWereEnabled)

        #expect(presenter.didTapLoginCount == 3)
        #expect(sideMenu.frame.maxX <= 0.5)
        #expect(backdrop.isHidden == true)
    }

    @Test func loggedInSideMenuNewDiscussionRoutesToComposer() async throws {
        let defaults = try #require(UserDefaults(suiteName: "post-list-side-menu-\(UUID().uuidString)"))
        let store = CurrentAccountStore(userDefaults: defaults, storageKey: "account")
        await store.save(AccountResponse(displayName: "mistj", isLoggedIn: true))
        let viewController = PostListSideMenuViewController(
            currentAccountStore: store,
            accountRefresher: StubCurrentAccountRefresher()
        )
        var newDiscussionTapCount = 0
        var loginTapCount = 0
        viewController.onNewDiscussionTapped = {
            newDiscussionTapCount += 1
        }
        viewController.onLoginTapped = {
            loginTapCount += 1
        }

        viewController.loadViewIfNeeded()
        let nameLabel = try #require(viewController.view.firstLabel(accessibilityIdentifier: "post-list-side-menu-name-label"))
        try await waitUntil { nameLabel.text == "mistj" }
        let button = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-list-side-menu-new-discussion-button"))
        button.sendActions(for: .touchUpInside)

        #expect(newDiscussionTapCount == 1)
        #expect(loginTapCount == 0)
    }

    @Test func loggedInSideMenuCheckInRoutesToBoardInsteadOfLogin() async throws {
        let defaults = try #require(UserDefaults(suiteName: "post-list-side-menu-\(UUID().uuidString)"))
        let store = CurrentAccountStore(userDefaults: defaults, storageKey: "account")
        await store.save(AccountResponse(displayName: "mistj", isLoggedIn: true))
        let viewController = PostListSideMenuViewController(
            currentAccountStore: store,
            accountRefresher: StubCurrentAccountRefresher()
        )
        var checkInTapCount = 0
        var loginTapCount = 0
        viewController.onCheckInTapped = {
            checkInTapCount += 1
        }
        viewController.onLoginTapped = {
            loginTapCount += 1
        }

        viewController.loadViewIfNeeded()
        try await waitUntil {
            viewController.view.firstLabel(accessibilityIdentifier: "post-list-side-menu-name-label")?.text == "mistj"
        }
        let button = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-list-side-menu-check-in-button"))
        button.sendActions(for: .touchUpInside)

        #expect(checkInTapCount == 1)
        #expect(loginTapCount == 0)
    }

    @Test func loggedInSideMenuAccountHeaderRoutesToProfileInsteadOfLogin() async throws {
        let defaults = try #require(UserDefaults(suiteName: "post-list-side-menu-\(UUID().uuidString)"))
        let store = CurrentAccountStore(userDefaults: defaults, storageKey: "account")
        let profileURL = try #require(URL(string: "https://www.nodeseek.com/space/31037"))
        await store.save(
            AccountResponse(
                displayName: "mistj",
                isLoggedIn: true,
                profileURL: profileURL
            )
        )
        let viewController = PostListSideMenuViewController(
            currentAccountStore: store,
            accountRefresher: StubCurrentAccountRefresher()
        )
        var routedProfileURL: URL?
        var loginTapCount = 0
        viewController.onAccountProfileTapped = { profileURL in
            routedProfileURL = profileURL
        }
        viewController.onLoginTapped = {
            loginTapCount += 1
        }

        viewController.loadViewIfNeeded()
        try await waitUntil {
            viewController.view.firstLabel(accessibilityIdentifier: "post-list-side-menu-name-label")?.text == "mistj"
        }
        viewController.view.layoutIfNeeded()

        let accountHeaderButton = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-list-side-menu-account-header-button"))
        let nameLabel = try #require(viewController.view.firstLabel(accessibilityIdentifier: "post-list-side-menu-name-label"))
        #expect(nameLabel.text == "mistj")
        accountHeaderButton.sendActions(for: .touchUpInside)

        #expect(routedProfileURL == profileURL)
        #expect(loginTapCount == 0)
    }

    @Test func loggedInSideMenuNotificationButtonUsesUnreadIconColorAndRoutesToNotificationPage() async throws {
        let defaults = try #require(UserDefaults(suiteName: "post-list-side-menu-\(UUID().uuidString)"))
        let store = CurrentAccountStore(userDefaults: defaults, storageKey: "account")
        let notificationURL = try #require(URL(string: "https://www.nodeseek.com/notification"))
        await store.save(
            AccountResponse(
                displayName: "mistj",
                isLoggedIn: true,
                notification: AccountNotification(
                    url: notificationURL,
                    iconColorCSS: "rgb(243, 17, 17)"
                )
            )
        )
        let viewController = PostListSideMenuViewController(
            currentAccountStore: store,
            accountRefresher: StubCurrentAccountRefresher()
        )
        var routedNotificationURL: URL?
        viewController.onNotificationTapped = { url in
            routedNotificationURL = url
        }

        viewController.loadViewIfNeeded()
        try await waitUntil {
            viewController.view.firstLabel(accessibilityIdentifier: "post-list-side-menu-name-label")?.text == "mistj"
        }

        let button = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-list-side-menu-notification-button"))
        #expect(button.configuration?.title == "通知")
        #expect(button.configuration?.baseForegroundColor == .label)
        let iconColor = button.configuration?.imageColorTransformer?(UIColor.label)
        #expect(iconColor?.isClose(to: UIColor(red: 243 / 255, green: 17 / 255, blue: 17 / 255, alpha: 1)) == true)

        button.sendActions(for: .touchUpInside)

        #expect(routedNotificationURL == notificationURL)
    }
}

private func makePostListViewController(
    presenter: SpyPostListPresenter,
    detailTestURLProvider: @escaping () -> String = {
        UIPasteboard.general.url?.absoluteString ?? UIPasteboard.general.string ?? ""
    }
) -> PostListViewController {
    PostListViewController(
        presenter: presenter,
        detailTestURLProvider: detailTestURLProvider
    )
}

private final class StubCurrentAccountRefresher: CurrentAccountRefreshing, @unchecked Sendable {
    func refreshIfNeeded(force: Bool, maxAge: TimeInterval) async -> AccountResponse? {
        nil
    }
}

private final class SpyPostListPresenter: PostListPresenterProtocol {
    private(set) var viewDidLoadCount = 0
    private(set) var didTapLoginCount = 0
    private(set) var didTapRecentVisitedCount = 0
    private(set) var didTapSearchCount = 0
    private(set) var didTapNewDiscussionCount = 0
    private(set) var didTapCheckInCount = 0
    private(set) var notificationURLs: [URL] = []
    private(set) var didTapSettingsCount = 0
    private(set) var accountProfileURLs: [URL] = []
    private(set) var didTapLogFileCount = 0
    private(set) var didTapDetailTestCount = 0
    private(set) var submittedDetailTestURL: String?
    private(set) var selectedCategories: [PostListCategory] = []
    private(set) var reselectedCategories: [PostListCategory] = []

    func viewDidLoad() {
        viewDidLoadCount += 1
    }

    func didSelectCategory(_ category: PostListCategory) {
        selectedCategories.append(category)
    }

    func didReselectCategory(_ category: PostListCategory) {
        reselectedCategories.append(category)
    }

    func didTapLogin() {
        didTapLoginCount += 1
    }

    func didTapRecentVisited() {
        didTapRecentVisitedCount += 1
    }

    func didTapSearch() {
        didTapSearchCount += 1
    }

    func didTapSettings() {
        didTapSettingsCount += 1
    }

    func didTapNewDiscussion() {
        didTapNewDiscussionCount += 1
    }

    func didTapCheckIn() {
        didTapCheckInCount += 1
    }

    func didTapNotification(url: URL) {
        notificationURLs.append(url)
    }

    func didTapAccountProfile(profileURL: URL) {
        accountProfileURLs.append(profileURL)
    }

    func didTapLogFile() {
        didTapLogFileCount += 1
    }

    func didTapDetailTest() {
        didTapDetailTestCount += 1
    }

    func didSubmitDetailTestURL(_ rawURL: String) {
        submittedDetailTestURL = rawURL
    }

    func didSelectPost(_ post: PostSummary) {}
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

private extension UIColor {
    func isClose(to other: UIColor) -> Bool {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        var otherRed: CGFloat = 0
        var otherGreen: CGFloat = 0
        var otherBlue: CGFloat = 0
        var otherAlpha: CGFloat = 0
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha),
              other.getRed(&otherRed, green: &otherGreen, blue: &otherBlue, alpha: &otherAlpha) else {
            return false
        }
        let tolerance: CGFloat = 0.01
        return abs(red - otherRed) < tolerance
            && abs(green - otherGreen) < tolerance
            && abs(blue - otherBlue) < tolerance
            && abs(alpha - otherAlpha) < tolerance
    }
}

@MainActor
private func waitUntil(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    condition: @escaping @MainActor () -> Bool
) async throws {
    let step: UInt64 = 25_000_000
    var waited: UInt64 = 0
    while waited < timeoutNanoseconds {
        if condition() {
            return
        }
        try await Task.sleep(nanoseconds: step)
        waited += step
    }
}
