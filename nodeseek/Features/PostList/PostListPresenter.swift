//
//  PostListPresenter.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation

class PostListPresenter: PostListPresenterProtocol {
    private struct CategoryState {
        var items: [PostListItem] = []
        var loadedIDs: Set<String> = []
        var nextPage: Int = 2
        var hasMorePages: Bool = true
        var hasLoadedFirstPage: Bool = false
        var isLoadingFirstPage: Bool = false
        var isRefreshing: Bool = false
        var isLoadingMore: Bool = false
    }
    
    // MARK: - Properties
    private weak var view: PostListViewProtocol?
    private let interactor: PostListInteractorInput
    private let router: PostListRouterProtocol
    private let visitedStore: VisitedPostStoreProtocol
    private var categoryStates: [PostListCategory: CategoryState] = [:]
    private let categories = PostListCategory.allCases
    private var currentCategory: PostListCategory = .all
    private var currentSortMode: PostListSortMode = .replyTime
    
    // MARK: - Initialization
    init(
        interactor: PostListInteractorInput,
        router: PostListRouterProtocol,
        visitedStore: VisitedPostStoreProtocol = EmptyVisitedPostStore()
    ) {
        self.interactor = interactor
        self.router = router
        self.visitedStore = visitedStore
    }
    
    // MARK: - Setup
    func setView(_ view: PostListViewProtocol) {
        self.view = view
    }
    
    // MARK: - Methods
    func viewDidLoad() {
        view?.renderCategories(categories, selected: currentCategory)
        view?.renderSortMode(currentSortMode)
        presentCurrentCategory(useCache: true)
    }

    func didSelectCategory(_ category: PostListCategory) {
        guard category != currentCategory else { return }
        currentCategory = category
        view?.renderCategories(categories, selected: currentCategory)
        presentCurrentCategory(useCache: true)
    }

    func didReselectCategory(_ category: PostListCategory) {
        guard category == currentCategory else {
            didSelectCategory(category)
            return
        }
        reloadCurrentCategoryFirstPage()
    }

    func didToggleSortMode() {
        currentSortMode = currentSortMode.toggled
        categoryStates = [:]
        view?.renderSortMode(currentSortMode)
        presentCurrentCategory(useCache: false)
    }

    func didTapLogin() {
        router.navigateToLogin { [weak self] in
            self?.presentCurrentCategory(useCache: false)
        }
    }

    func didTapAccountProfile(profileURL: URL) {
        router.navigateToUserProfile(profileURL: profileURL)
    }

    func didTapNewDiscussion() {
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
                self?.presentCurrentCategory(useCache: false)
            },
            onLogFile: { [weak self] in
                self?.didTapLogFile()
            },
            onDetailTest: detailTestAction
        )
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

    private func presentCurrentCategory(useCache: Bool) {
        var state = state(for: currentCategory)
        if !useCache {
            state = CategoryState()
            categoryStates[currentCategory] = state
        }

        view?.render(items: state.items)
        if state.isLoadingFirstPage {
            view?.showLoading()
            view?.hideFirstPageError()
        } else {
            view?.hideLoading()
        }

        if state.isRefreshing {
            view?.showRefreshing()
        } else {
            view?.hideRefreshing()
        }

        if state.isLoadingMore {
            view?.showLoadingMore()
        } else {
            view?.hideLoadingMore()
        }

        if !state.hasLoadedFirstPage && !state.isLoadingFirstPage {
            loadFirstPage(for: currentCategory)
        }
    }

    private func state(for category: PostListCategory) -> CategoryState {
        categoryStates[category] ?? CategoryState()
    }

    private func loadFirstPage(for category: PostListCategory) {
        var state = state(for: category)
        guard !state.isLoadingFirstPage else { return }
        state.isLoadingFirstPage = true
        state.isRefreshing = false
        state.isLoadingMore = false
        categoryStates[category] = state

        if category == currentCategory {
            view?.showLoading()
            view?.hideFirstPageError()
            view?.hideRefreshing()
            view?.hideLoadingMore()
        }

        interactor.loadPosts(category: category, sortMode: currentSortMode)
    }

    private func reloadCurrentCategoryFirstPage() {
        var state = state(for: currentCategory)
        guard !state.isLoadingFirstPage else { return }
        state = CategoryState()
        categoryStates[currentCategory] = state
        view?.render(items: [])
        view?.hideFirstPageError()
        loadFirstPage(for: currentCategory)
    }

    func didPullToRefresh() {
        var state = state(for: currentCategory)
        guard state.hasLoadedFirstPage else { return }
        guard !state.isRefreshing else { return }
        guard !state.isLoadingFirstPage else { return }
        guard !state.isLoadingMore else { return }

        state.isRefreshing = true
        categoryStates[currentCategory] = state
        view?.showRefreshing()
        interactor.loadPosts(category: currentCategory, sortMode: currentSortMode)
    }

    func didRetryFirstPage() {
        reloadCurrentCategoryFirstPage()
    }
    
    func didSelectPost(at index: Int) {
        var state = state(for: currentCategory)
        guard state.items.indices.contains(index) else { return }
        let item = state.items[index]
        visitedStore.markVisited(post: item.post, visitedAt: Date())

        if !item.isVisited {
            state.items[index] = PostListItem(post: item.post, isVisited: true)
            categoryStates[currentCategory] = state
            view?.renderVisitedState(at: index, isVisited: true)
        }

        if let route = NodeSeekPostRouteResolver.route(for: item.post.url, baseURL: NodeSeekSite.baseURL) {
            router.navigateToPostDetail(
                post: item.post,
                page: route.page,
                initialAnchorID: route.anchorID
            )
        } else {
            router.navigateToPostDetail(post: item.post)
        }
    }

    func didApproachBottom(currentIndex: Int, totalCount: Int) {
        var state = state(for: currentCategory)
        guard totalCount > 0 else {
            AppLog.debug(.postList, "忽略帖子列表加载更多: totalCount=0")
            return
        }
        guard state.hasMorePages else {
            AppLog.debug(.postList, "忽略帖子列表加载更多: 已无更多分页 category=\(currentCategory.rawValue)")
            return
        }
        guard !state.isLoadingMore else {
            AppLog.debug(.postList, "忽略帖子列表加载更多: 正在加载更多 category=\(currentCategory.rawValue)")
            return
        }
        guard !state.isLoadingFirstPage else {
            AppLog.debug(.postList, "忽略帖子列表加载更多: 首屏仍在加载 category=\(currentCategory.rawValue)")
            return
        }

        state.isLoadingMore = true
        categoryStates[currentCategory] = state
        AppLog.info(
            .postList,
            "触发帖子列表加载更多: page=\(state.nextPage), category=\(currentCategory.rawValue), sortMode=\(currentSortMode.rawValue), currentIndex=\(currentIndex), totalCount=\(totalCount)"
        )
        view?.showLoadingMore()
        interactor.loadMorePosts(page: state.nextPage, category: currentCategory, sortMode: currentSortMode)
    }
}

// MARK: - Interactor Output
extension PostListPresenter: PostListInteractorOutput {
    func didLoadPosts(
        _ posts: [PostSummary],
        category: PostListCategory,
        sortMode: PostListSortMode = .replyTime
    ) {
        guard sortMode == currentSortMode else { return }
        var state = state(for: category)
        state.items = items(for: posts)
        state.loadedIDs = Set(posts.map(\.id))
        state.hasMorePages = !posts.isEmpty
        state.nextPage = 2
        state.hasLoadedFirstPage = true
        state.isLoadingFirstPage = false
        state.isRefreshing = false
        state.isLoadingMore = false
        categoryStates[category] = state

        guard category == currentCategory else { return }
        view?.render(items: state.items)
        view?.hideFirstPageError()
        view?.hideLoading()
        view?.hideRefreshing()
        view?.hideLoadingMore()
    }

    func didLoadMorePosts(
        _ posts: [PostSummary],
        page: Int,
        category: PostListCategory,
        sortMode: PostListSortMode = .replyTime
    ) {
        guard sortMode == currentSortMode else { return }
        var state = state(for: category)
        state.isLoadingMore = false

        guard !posts.isEmpty else {
            state.hasMorePages = false
            categoryStates[category] = state
            AppLog.info(.postList, "帖子列表加载更多结束: 无更多分页 page=\(page), category=\(category.rawValue)")
            if category == currentCategory {
                view?.hideLoadingMore()
            }
            return
        }

        state.nextPage = page + 1
        var appended = false
        for post in posts where state.loadedIDs.insert(post.id).inserted {
            state.items.append(item(for: post))
            appended = true
        }
        categoryStates[category] = state

        guard category == currentCategory else { return }
        if appended {
            AppLog.info(.postList, "帖子列表加载更多完成: page=\(page), category=\(category.rawValue), received=\(posts.count), total=\(state.items.count)")
            // 先接上新数据，再收起底部 loading，避免 footer 高度变化带动可见列表跳动。
            view?.render(items: state.items)
        }
        view?.hideLoadingMore()
    }
    
    func didFailLoadPosts(
        error: String,
        category: PostListCategory,
        sortMode: PostListSortMode = .replyTime
    ) {
        guard sortMode == currentSortMode else { return }
        var state = state(for: category)
        state.isLoadingFirstPage = false
        state.isRefreshing = false
        state.isLoadingMore = false
        categoryStates[category] = state

        guard category == currentCategory else { return }
        view?.hideLoading()
        view?.hideRefreshing()
        view?.hideLoadingMore()
        if state.items.isEmpty {
            view?.showFirstPageError(message: error)
        } else {
            view?.showError(message: error)
        }
    }

    func didFailLoadMorePosts(
        error: String,
        page: Int,
        category: PostListCategory,
        sortMode: PostListSortMode = .replyTime
    ) {
        guard sortMode == currentSortMode else { return }
        var state = state(for: category)
        state.isLoadingMore = false
        categoryStates[category] = state
        AppLog.warning(.postList, "帖子列表加载更多失败: page=\(page), category=\(category.rawValue), error=\(error)")

        guard category == currentCategory else { return }
        view?.hideLoadingMore()
        view?.showError(message: "第 \(page) 页加载失败：\(error)")
    }
}

private extension PostListPresenter {
    func items(for posts: [PostSummary]) -> [PostListItem] {
        posts.map(item(for:))
    }

    func item(for post: PostSummary) -> PostListItem {
        PostListItem(post: post, isVisited: visitedStore.isVisited(postID: post.id))
    }
}
