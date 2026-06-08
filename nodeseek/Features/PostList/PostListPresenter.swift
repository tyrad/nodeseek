//
//  PostListPresenter.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation

class PostListPresenter: PostListPresenterProtocol {
    private enum NotificationUnreadRefresh {
        static let throttleInterval: TimeInterval = 10
    }

    // MARK: - Properties
    private weak var view: PostListViewProtocol?
    private let router: PostListRouterProtocol
    private let visitedStore: VisitedPostStoreProtocol
    private let categoryPreferenceStore: PostCategoryPreferenceStore
    private let notificationUnreadCountInteractor: PostListNotificationUnreadCountInteractorProtocol
    private let currentDateProvider: () -> Date
    private var categoryPreferenceObserver: NSObjectProtocol?
    private var notificationUnreadRefreshTask: Task<Void, Never>?
    private var lastNotificationUnreadRefreshDate: Date?
    private var currentCategory: PostListCategoryItem = .all

    // MARK: - Initialization
    init(
        router: PostListRouterProtocol,
        visitedStore: VisitedPostStoreProtocol = EmptyVisitedPostStore(),
        categoryPreferenceStore: PostCategoryPreferenceStore = .shared,
        notificationUnreadCountInteractor: PostListNotificationUnreadCountInteractorProtocol? = nil,
        currentDateProvider: @escaping () -> Date = Date.init
    ) {
        self.router = router
        self.visitedStore = visitedStore
        self.categoryPreferenceStore = categoryPreferenceStore
        self.notificationUnreadCountInteractor = notificationUnreadCountInteractor
            ?? PostListNotificationUnreadCountInteractor()
        self.currentDateProvider = currentDateProvider
    }

    deinit {
        if let categoryPreferenceObserver {
            NotificationCenter.default.removeObserver(categoryPreferenceObserver)
        }
        notificationUnreadRefreshTask?.cancel()
    }

    // MARK: - Setup
    func setView(_ view: PostListViewProtocol) {
        self.view = view
    }

    // MARK: - Methods
    func viewDidLoad() {
        observeCategoryPreferencesIfNeeded()
        renderCurrentCategories()
        view?.renderSortMode(.replyTime)
    }

    func viewWillAppear() {
        refreshNotificationUnreadBadge()
    }

    func didEnterForeground() {
        refreshNotificationUnreadBadge()
    }

    func didReceiveNotificationReadStateChange() {
        refreshNotificationUnreadBadge(force: true)
    }

    func didSelectCategory(_ category: PostListCategoryItem) {
        guard category != currentCategory else { return }
        guard categoryPreferenceStore.visibleCategoryItems.contains(category) else { return }
        currentCategory = category
    }

    func didReselectCategory(_ category: PostListCategoryItem) {
        guard category == currentCategory else {
            didSelectCategory(category)
            return
        }
        view?.reloadSelectedCategory()
    }

    func didTapLogin() {
        router.navigateToLogin { [weak self] in
            self?.view?.reloadSelectedCategory()
        }
    }

    func didTapAccountProfile(profileURL: URL) {
        router.navigateToUserProfile(profileURL: profileURL)
    }

    func didTapNewDiscussion() {
        AppLog.info(.postList, "Presenter 收到发帖入口点击，准备导航到发帖页")
        router.navigateToNewDiscussion()
    }

    func didTapCheckIn() {
        router.navigateToCheckIn(boardURL: NodeSeekSite.boardURL)
    }

    func didTapNotification(url: URL) {
        router.navigateToNotification(notificationURL: url)
    }

    func didTapRecentVisited() {
        router.navigateToRecentVisitedPosts(visitedStore: visitedStore)
    }

    func didTapUserDiscussions() {
        router.navigateToUserDiscussions()
    }

    func didTapUserComments() {
        router.navigateToUserComments()
    }

    func didTapUserCollections() {
        router.navigateToUserCollections()
    }

    func didTapSearch() {
        router.navigateToSearch()
    }

    func didTapSettings() {
        #if DEBUG
        let detailTestAction: (@MainActor () -> Void)? = { [weak self] in
            self?.didTapDetailTest()
        }
        #else
        let detailTestAction: (@MainActor () -> Void)? = nil
        #endif

        router.navigateToSettings(
            onLogout: { [weak self] in
                self?.view?.reloadSelectedCategory()
            },
            onLogFile: { [weak self] in
                self?.didTapLogFile()
            },
            onDetailTest: detailTestAction
        )
    }

    func didTapCategoryPreferences() {
        router.navigateToPostCategoryPreferences()
    }

    func didTapLogFile() {
        router.navigateToLogFile()
    }

    #if DEBUG
    func didTapDetailTest() {
        guard NodeSeekDebugConfig.enablePostDetailTestEntry else { return }
        view?.openDetailTestURLFromPasteboard()
    }

    func didSubmitDetailTestURL(_ rawURL: String) {
        guard NodeSeekDebugConfig.enablePostDetailTestEntry else { return }
        guard let target = PostDetailTestTarget(rawValue: rawURL) else {
            view?.showError(message: "剪贴板里没有可打开的 NodeSeek 帖子详情链接，例如 \(NodeSeekSite.postURL(id: "705039", page: 1).absoluteString)")
            return
        }

        router.navigateToPostDetail(
            post: target.post,
            page: target.page,
            initialAnchorID: target.anchorID
        )
    }
    #endif

    func didSelectPost(_ post: PostSummary) {
        routeToPostDetail(post)
    }
}

private extension PostListPresenter {
    func observeCategoryPreferencesIfNeeded() {
        guard categoryPreferenceObserver == nil else { return }
        categoryPreferenceObserver = NotificationCenter.default.addObserver(
            forName: PostCategoryPreferenceStore.didChangeNotification,
            object: categoryPreferenceStore,
            queue: nil
        ) { [weak self] _ in
            self?.categoryPreferencesDidChange()
        }
    }

    func categoryPreferencesDidChange() {
        renderCurrentCategories()
    }

    func renderCurrentCategories() {
        let categories = categoryPreferenceStore.visibleCategoryItems
        if !categories.contains(currentCategory) {
            currentCategory = .all
        }
        view?.renderCategories(categories, selected: currentCategory)
    }

    func routeToPostDetail(_ post: PostSummary) {
        if let route = NodeSeekPostRouteResolver.route(for: post.url, baseURL: NodeSeekSite.baseURL) {
            router.navigateToPostDetail(
                post: post,
                page: route.page,
                initialAnchorID: route.anchorID
            )
        } else {
            router.navigateToPostDetail(post: post)
        }
    }

    func refreshNotificationUnreadBadge(force: Bool = false) {
        if force == false, shouldThrottleNotificationUnreadRefresh() {
            return
        }
        lastNotificationUnreadRefreshDate = currentDateProvider()
        notificationUnreadRefreshTask?.cancel()
        notificationUnreadRefreshTask = Task { [weak self, notificationUnreadCountInteractor] in
            do {
                let unreadCount = try await notificationUnreadCountInteractor.loadUnreadCount()
                guard Task.isCancelled == false else { return }
                await MainActor.run { [weak self] in
                    self?.view?.renderNotificationUnreadBadge(isVisible: unreadCount.all > 0)
                }
            } catch {
                guard Task.isCancelled == false else { return }
                await MainActor.run { [weak self] in
                    self?.view?.renderNotificationUnreadBadge(isVisible: false)
                }
                AppLog.debug(.account, "首页通知未读数加载失败: \(error.localizedDescription)")
            }
        }
    }

    func shouldThrottleNotificationUnreadRefresh() -> Bool {
        guard let lastNotificationUnreadRefreshDate else { return false }
        return currentDateProvider().timeIntervalSince(lastNotificationUnreadRefreshDate) < NotificationUnreadRefresh.throttleInterval
    }
}
