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
        #expect(button.titleLabel?.font.pointSize ?? 0 >= 13)
        #expect(button.titleLabel?.numberOfLines == 1)
        #expect(button.titleLabel?.lineBreakMode == .byTruncatingTail)
        #expect(button.configuration?.titleLineBreakMode == .byTruncatingTail)
        var buttonFrame = button.convert(button.bounds, to: viewController.view)

        #expect(buttonFrame.maxX > viewController.view.bounds.maxX)
        #expect(buttonFrame.maxY <= viewController.view.bounds.maxY - 200)

        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        button.sendActions(for: .touchUpInside)
        viewController.view.layoutIfNeeded()
        UIView.setAnimationsEnabled(animationsWereEnabled)
        buttonFrame = button.convert(button.bounds, to: viewController.view)

        #expect(button.title(for: .normal) == "回复时间优先")
        #expect(button.alpha == 1)
        #expect(button.bounds.width >= 168)
        #expect(button.configuration?.titleTextAttributesTransformer != nil)
        #expect(button.intrinsicContentSize.width <= button.bounds.width)
        #expect(abs(buttonFrame.maxX - viewController.view.bounds.maxX) < 0.5)

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
        let categoryEditButton = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-list-category-edit-button"))
        #expect(menuButton.bounds.width == 40)
        #expect(menuButton.bounds.height == 40)
        #expect(menuButton.backgroundColor == .clear)
        #expect(menuButton.layer.borderWidth == 0)
        #expect(menuButton.layer.cornerRadius == 0)
        #expect(menuButton.configuration?.image != nil)
        #expect(menuButton.configuration?.image?.renderingMode == .alwaysTemplate)
        #expect(categoryEditButton.bounds.width == 40)
        #expect(categoryEditButton.bounds.height == 40)
        #expect(categoryEditButton.configuration?.image != nil)
        #expect(categoryEditButton.accessibilityLabel == "编辑首页分类")

        let selectedTab = try #require(viewController.view.firstButton(title: "全部"))
        let unselectedTab = try #require(viewController.view.firstButton(title: "日常"))
        #expect(PostListTopBarStyle.Menu.symbolPointSize == 16)
        #expect(PostListTopBarStyle.Menu.symbolWeight == .regular)
        #expect(PostListTopBarStyle.Tab.selectedWeight == .medium)
        #expect(PostListTopBarStyle.Tab.normalWeight == .regular)
        #expect(selectedTab.titleLabel?.font.pointSize == 17)
        #expect(selectedTab.titleLabel?.font.fontDescriptor.symbolicTraits.contains(.traitBold) == false)
        #expect(unselectedTab.titleLabel?.font.pointSize == 17)
        #expect(unselectedTab.titleColor(for: .normal) == .secondaryLabel)
        let selectedTitleWidth = try #require(selectedTab.titleLabel?.intrinsicContentSize.width)
        let unselectedTitleWidth = try #require(unselectedTab.titleLabel?.intrinsicContentSize.width)
        #expect(selectedTab.bounds.width <= selectedTitleWidth + 8)
        #expect(unselectedTab.bounds.width <= unselectedTitleWidth + 8)
        let selectedTabFrame = selectedTab.convert(selectedTab.bounds, to: viewController.view)
        let menuButtonFrame = menuButton.convert(menuButton.bounds, to: viewController.view)
        let categoryEditButtonFrame = categoryEditButton.convert(categoryEditButton.bounds, to: viewController.view)
        #expect(abs(selectedTabFrame.minY - menuButtonFrame.minY) < 1)
        #expect(abs(selectedTabFrame.height - menuButtonFrame.height) < 1)
        #expect(abs(menuButtonFrame.minY - (viewController.view.safeAreaInsets.top - 4)) < 1)
        #expect(categoryEditButton.superview is UIStackView)
        #expect(abs(categoryEditButtonFrame.minY - selectedTabFrame.minY) < 1)
        #expect(selectedTabFrame.maxX < categoryEditButtonFrame.minX)
        let lastTab = try #require(viewController.view.firstButton(title: "情报"))
        let lastTabFrame = lastTab.convert(lastTab.bounds, to: viewController.view)
        #expect(lastTabFrame.maxX < categoryEditButtonFrame.minX)
        #expect(abs(viewController.pageContainerViewController.view.frame.minY - selectedTabFrame.maxY - 2) < 1)

        categoryEditButton.sendActions(for: .touchUpInside)

        #expect(presenter.didTapCategoryPreferencesCount == 1)
    }

    @Test func sortToggleButtonIsHostedInDraggableFloatingContainer() throws {
        let presenter = SpyPostListPresenter()
        let viewController = makePostListViewController(presenter: presenter)
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.layoutIfNeeded()

        let floatingContainer = try #require(
            viewController.view.firstView(accessibilityIdentifier: "post-list-floating-sort-toggle") as? FloatingControlContainerView
        )
        let sortToggleButton = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-list-sort-toggle"))
        let panGesture = try #require(sortToggleButton.gestureRecognizers?.first { $0 is UIPanGestureRecognizer })

        #expect(panGesture.view === sortToggleButton)
        #expect(panGesture.cancelsTouchesInView)
        #expect(sortToggleButton.superview === floatingContainer)
        #expect(floatingContainer.translatesAutoresizingMaskIntoConstraints == true)
        #expect(
            viewController.view.constraints.contains {
                let referencesFloatingContainer = ($0.firstItem as? UIView) === floatingContainer
                    || ($0.secondItem as? UIView) === floatingContainer
                let isAutoresizingMaskConstraint = String(describing: type(of: $0)).contains("NSAutoresizingMaskLayoutConstraint")
                return referencesFloatingContainer && !isAutoresizingMaskConstraint
            } == false
        )
        #expect(sortToggleButton.bounds.height >= 42)
        #expect(sortToggleButton.bounds.width >= 56)
        let sortToggleFrame = sortToggleButton.convert(sortToggleButton.bounds, to: viewController.view)
        #expect(sortToggleFrame.maxX > viewController.view.bounds.maxX)
        #expect(abs(floatingContainer.floatingEdgeInsets.top - viewController.pageContainerViewController.view.frame.minY) < 1)
        #expect(floatingContainer.floatingEdgeInsets.bottom >= viewController.view.safeAreaInsets.bottom)
        #expect(floatingContainer.floatingEdgeInsets.right < 0)

        floatingContainer.frame.origin.y = 0
        floatingContainer.updateFloatingEdgeInsets(
            in: viewController.view,
            topBoundary: viewController.pageContainerViewController.view.frame.minY
        )
        #expect(floatingContainer.frame.minY >= viewController.pageContainerViewController.view.frame.minY)

        floatingContainer.frame.origin.y = viewController.view.bounds.maxY
        floatingContainer.updateFloatingEdgeInsets(
            in: viewController.view,
            topBoundary: viewController.pageContainerViewController.view.frame.minY
        )
        #expect(floatingContainer.frame.maxY <= viewController.view.safeAreaLayoutGuide.layoutFrame.maxY)

        floatingContainer.frame.origin.x = 0
        floatingContainer.floatingViewDidEndDragging(panGestureRecognizer: UIPanGestureRecognizer())
        #expect(sortToggleButton.layer.maskedCorners == [.layerMaxXMinYCorner, .layerMaxXMaxYCorner])
    }

    @Test func sortToggleButtonRestoresLastDraggedPosition() throws {
        let positionStore = InMemoryFloatingControlPositionStore()
        let firstViewController = makePostListViewController(
            presenter: SpyPostListPresenter(),
            floatingPositionStore: positionStore
        )
        firstViewController.loadViewIfNeeded()
        firstViewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        firstViewController.view.layoutIfNeeded()

        let firstContainer = try #require(
            firstViewController.view.firstView(accessibilityIdentifier: "post-list-floating-sort-toggle") as? FloatingControlContainerView
        )
        let topBoundary = firstViewController.pageContainerViewController.view.frame.minY
        firstContainer.frame.origin.x = 0
        firstContainer.frame.origin.y = topBoundary + 96
        firstContainer.floatingViewDidEndDragging(panGestureRecognizer: UIPanGestureRecognizer())

        let secondViewController = makePostListViewController(
            presenter: SpyPostListPresenter(),
            floatingPositionStore: positionStore
        )
        secondViewController.loadViewIfNeeded()
        secondViewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        secondViewController.view.layoutIfNeeded()

        let restoredContainer = try #require(
            secondViewController.view.firstView(accessibilityIdentifier: "post-list-floating-sort-toggle") as? FloatingControlContainerView
        )
        let restoredButton = try #require(secondViewController.view.firstButton(accessibilityIdentifier: "post-list-sort-toggle"))

        #expect(abs(restoredContainer.frame.minX) < 0.5)
        #expect(abs(restoredContainer.frame.minY - firstContainer.frame.minY) < 1)
        #expect(restoredButton.layer.maskedCorners == [.layerMaxXMinYCorner, .layerMaxXMaxYCorner])
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

    @Test func allTabFirstPageSuccessTriggersAutoCheckIn() async throws {
        let presenter = SpyPostListPresenter()
        let capturedContexts = AutoCheckInPresentationContexts()
        let viewController = makePostListViewController(
            presenter: presenter,
            autoCheckInRunner: { context in
                capturedContexts.append(context)
            }
        )
        viewController.loadViewIfNeeded()

        viewController.postPageContainerViewController(
            viewController.pageContainerViewController,
            didLoadFirstPageFor: .all
        )

        try await waitUntil {
            capturedContexts.values.count == 1
        }
        let capturedContext = try #require(capturedContexts.values.first ?? nil)
        #expect(capturedContext === viewController)
    }

    @Test func nonAllTabFirstPageSuccessDoesNotTriggerAutoCheckIn() async throws {
        let presenter = SpyPostListPresenter()
        let capturedContexts = AutoCheckInPresentationContexts()
        let viewController = makePostListViewController(
            presenter: presenter,
            autoCheckInRunner: { context in
                capturedContexts.append(context)
            }
        )
        viewController.loadViewIfNeeded()

        viewController.postPageContainerViewController(
            viewController.pageContainerViewController,
            didLoadFirstPageFor: .tech
        )
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(capturedContexts.values.isEmpty)
    }

    @Test func categoryPreferenceFallbackRemovesHiddenTabAndSelectsAllPage() throws {
        let presenter = SpyPostListPresenter()
        let viewController = makePostListViewController(presenter: presenter)
        viewController.loadViewIfNeeded()

        viewController.renderCategories([.all, .daily, .tech], selected: .tech)
        #expect(viewController.selectedCategory == .tech)
        #expect(viewController.pageContainerViewController.currentCategory == .tech)
        #expect(viewController.pageContainerViewController.hostViewControllers[.tech] != nil)

        viewController.renderCategories([.all, .daily], selected: .all)

        #expect(viewController.view.firstButton(title: "技术") == nil)
        #expect(viewController.selectedCategory == .all)
        #expect(viewController.pageContainerViewController.currentCategory == .all)
        #expect(viewController.pageContainerViewController.hostViewControllers[.tech] == nil)
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
        let postsEntryButton = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-list-side-menu-extension-posts-button"))
        let commentsEntryButton = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-list-side-menu-extension-comments-button"))
        let favoritesEntryButton = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-list-side-menu-extension-favorites-button"))
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
        #expect(postsEntryButton.isHidden == true)
        #expect(commentsEntryButton.isHidden == true)
        #expect(favoritesEntryButton.isHidden == true)
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

    @Test func loggedInSideMenuShowsCompactExtensionEntryButtonsBelowAccountStats() async throws {
        let defaults = try #require(UserDefaults(suiteName: "post-list-side-menu-\(UUID().uuidString)"))
        let store = CurrentAccountStore(userDefaults: defaults, storageKey: "account")
        await store.save(AccountResponse(displayName: "mistj", isLoggedIn: true))
        let viewController = PostListSideMenuViewController(
            currentAccountStore: store,
            accountRefresher: StubCurrentAccountRefresher()
        )

        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        try await waitUntil {
            viewController.view.firstLabel(accessibilityIdentifier: "post-list-side-menu-name-label")?.text == "mistj"
        }
        viewController.show(animated: false)
        viewController.view.layoutIfNeeded()

        let nameLabel = try #require(viewController.view.firstLabel(accessibilityIdentifier: "post-list-side-menu-name-label"))
        let statsLabel = try #require(viewController.view.firstLabel(accessibilityIdentifier: "post-list-side-menu-stats-label"))
        let extensionEntryStack = try #require(viewController.view.firstView(accessibilityIdentifier: "post-list-side-menu-extension-entry-stack"))
        let postsEntryButton = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-list-side-menu-extension-posts-button"))
        let commentsEntryButton = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-list-side-menu-extension-comments-button"))
        let favoritesEntryButton = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-list-side-menu-extension-favorites-button"))
        let newDiscussionButton = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-list-side-menu-new-discussion-button"))

        #expect(extensionEntryStack.isHidden == false)
        #expect(postsEntryButton.isHidden == false)
        #expect(postsEntryButton.accessibilityLabel == "帖子")
        #expect(postsEntryButton.configuration?.image != nil)
        #expect(postsEntryButton.configuration?.title == "帖子")
        #expect(postsEntryButton.configuration?.imagePlacement == .leading)
        #expect(postsEntryButton.configuration?.baseForegroundColor == .secondaryLabel)
        #expect((postsEntryButton.configuration?.background.backgroundColor?.cgColor.alpha ?? 0) == 0)
        #expect(commentsEntryButton.isHidden == false)
        #expect(commentsEntryButton.accessibilityLabel == "评论")
        #expect(commentsEntryButton.configuration?.image != nil)
        #expect(commentsEntryButton.configuration?.title == "评论")
        #expect(commentsEntryButton.configuration?.imagePlacement == .leading)
        #expect(commentsEntryButton.configuration?.baseForegroundColor == .secondaryLabel)
        #expect((commentsEntryButton.configuration?.background.backgroundColor?.cgColor.alpha ?? 0) == 0)
        #expect(favoritesEntryButton.isHidden == false)
        #expect(favoritesEntryButton.accessibilityLabel == "收藏")
        #expect(favoritesEntryButton.configuration?.image != nil)
        #expect(favoritesEntryButton.configuration?.title == "收藏")
        #expect(favoritesEntryButton.configuration?.imagePlacement == .leading)
        #expect(favoritesEntryButton.configuration?.baseForegroundColor == .secondaryLabel)
        #expect((favoritesEntryButton.configuration?.background.backgroundColor?.cgColor.alpha ?? 0) == 0)
        let nameFrame = nameLabel.convert(nameLabel.bounds, to: viewController.view)
        let statsFrame = statsLabel.convert(statsLabel.bounds, to: viewController.view)
        let extensionEntryStackFrame = extensionEntryStack.convert(extensionEntryStack.bounds, to: viewController.view)
        let postsEntryFrame = postsEntryButton.convert(postsEntryButton.bounds, to: viewController.view)
        let commentsEntryFrame = commentsEntryButton.convert(commentsEntryButton.bounds, to: viewController.view)
        let favoritesEntryFrame = favoritesEntryButton.convert(favoritesEntryButton.bounds, to: viewController.view)
        let newDiscussionFrame = newDiscussionButton.convert(newDiscussionButton.bounds, to: viewController.view)
        #expect(extensionEntryStackFrame.width < 150)
        #expect(abs(extensionEntryStackFrame.minX - nameFrame.minX) < 1)
        #expect(abs(postsEntryFrame.minY - statsFrame.maxY - 4) < 1)
        #expect(commentsEntryFrame.minY == postsEntryFrame.minY)
        #expect(favoritesEntryFrame.minY == postsEntryFrame.minY)
        #expect(postsEntryFrame.height == 24)
        #expect(commentsEntryFrame.height == 24)
        #expect(favoritesEntryFrame.height == 24)
        #expect(postsEntryFrame.maxX < commentsEntryFrame.minX)
        #expect(commentsEntryFrame.maxX < favoritesEntryFrame.minX)
        #expect(favoritesEntryFrame.maxY < newDiscussionFrame.minY)
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

    @Test func loggedInSideMenuExtensionEntriesRouteToUserContent() async throws {
        let defaults = try #require(UserDefaults(suiteName: "post-list-side-menu-\(UUID().uuidString)"))
        let store = CurrentAccountStore(userDefaults: defaults, storageKey: "account")
        await store.save(AccountResponse(displayName: "mistj", isLoggedIn: true))
        let viewController = PostListSideMenuViewController(
            currentAccountStore: store,
            accountRefresher: StubCurrentAccountRefresher()
        )
        var postsTapCount = 0
        var commentsTapCount = 0
        var favoritesTapCount = 0
        viewController.onUserDiscussionsTapped = {
            postsTapCount += 1
        }
        viewController.onUserCommentsTapped = {
            commentsTapCount += 1
        }
        viewController.onUserCollectionsTapped = {
            favoritesTapCount += 1
        }

        viewController.loadViewIfNeeded()
        try await waitUntil {
            viewController.view.firstLabel(accessibilityIdentifier: "post-list-side-menu-name-label")?.text == "mistj"
        }

        try #require(viewController.view.firstButton(accessibilityIdentifier: "post-list-side-menu-extension-posts-button"))
            .sendActions(for: .touchUpInside)
        try #require(viewController.view.firstButton(accessibilityIdentifier: "post-list-side-menu-extension-comments-button"))
            .sendActions(for: .touchUpInside)
        try #require(viewController.view.firstButton(accessibilityIdentifier: "post-list-side-menu-extension-favorites-button"))
            .sendActions(for: .touchUpInside)

        #expect(postsTapCount == 1)
        #expect(commentsTapCount == 1)
        #expect(favoritesTapCount == 1)
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
    floatingPositionStore: FloatingControlPositionStoring = InMemoryFloatingControlPositionStore(),
    autoCheckInRunner: @escaping @MainActor (UIViewController?) async -> Void = { _ in },
    detailTestURLProvider: @escaping () -> String = {
        UIPasteboard.general.url?.absoluteString ?? UIPasteboard.general.string ?? ""
    }
) -> PostListViewController {
    PostListViewController(
        presenter: presenter,
        floatingPositionStore: floatingPositionStore,
        autoCheckInRunner: autoCheckInRunner,
        detailTestURLProvider: detailTestURLProvider
    )
}

@MainActor
private final class AutoCheckInPresentationContexts {
    private(set) var values: [UIViewController?] = []

    func append(_ value: UIViewController?) {
        values.append(value)
    }
}

private final class InMemoryFloatingControlPositionStore: FloatingControlPositionStoring {
    private var positions: [String: FloatingControlPosition] = [:]

    func position(forKey key: String) -> FloatingControlPosition? {
        positions[key]
    }

    func save(_ position: FloatingControlPosition, forKey key: String) {
        positions[key] = position
    }
}

private final class StubCurrentAccountRefresher: CurrentAccountRefreshing, @unchecked Sendable {
    func cachedAccount() async -> AccountResponse? {
        nil
    }

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
    private(set) var didTapUserDiscussionsCount = 0
    private(set) var didTapUserCommentsCount = 0
    private(set) var didTapUserCollectionsCount = 0
    private(set) var notificationURLs: [URL] = []
    private(set) var didTapSettingsCount = 0
    private(set) var didTapCategoryPreferencesCount = 0
    private(set) var accountProfileURLs: [URL] = []
    private(set) var didTapLogFileCount = 0
    private(set) var didTapDetailTestCount = 0
    private(set) var submittedDetailTestURL: String?
    private(set) var selectedCategories: [PostListCategoryItem] = []
    private(set) var reselectedCategories: [PostListCategoryItem] = []

    func viewDidLoad() {
        viewDidLoadCount += 1
    }

    func didSelectCategory(_ category: PostListCategoryItem) {
        selectedCategories.append(category)
    }

    func didReselectCategory(_ category: PostListCategoryItem) {
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

    func didTapCategoryPreferences() {
        didTapCategoryPreferencesCount += 1
    }

    func didTapNewDiscussion() {
        didTapNewDiscussionCount += 1
    }

    func didTapCheckIn() {
        didTapCheckInCount += 1
    }

    func didTapUserDiscussions() {
        didTapUserDiscussionsCount += 1
    }

    func didTapUserComments() {
        didTapUserCommentsCount += 1
    }

    func didTapUserCollections() {
        didTapUserCollectionsCount += 1
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
