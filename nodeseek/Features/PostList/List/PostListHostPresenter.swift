//
//  PostListHostPresenter.swift
//  nodeseek
//

import Foundation

final class PostListHostPresenter: PostListHostPresenterProtocol {
    weak var delegate: PostListHostPresenterDelegate?

    private weak var view: PostListHostViewProtocol?
    private let category: PostListCategoryItem
    private let interactor: PostListHostInteractorInput
    private let visitedStore: VisitedPostStoreProtocol
    private let sortPreferenceStore: PostListSortPreferenceStoring
    private var requestGeneration = 0
    private var sortMode: PostListSortMode
    private var items: [PostListItem] = []
    private var loadedIDs: Set<String> = []
    private var nextPage: Int = 2
    private var hasMorePages = true
    private var hasLoadedFirstPage = false
    private var isLoadingFirstPage = false
    private var isRefreshing = false
    /// 本次刷新由再次点按 Tab 发起，结束时需要收起加载提示。
    private var isTabReselectRefreshing = false
    private var isLoadingMore = false

    init(
        category: PostListCategoryItem,
        interactor: PostListHostInteractorInput,
        visitedStore: VisitedPostStoreProtocol,
        sortPreferenceStore: PostListSortPreferenceStoring = PostListSortPreferenceStore.shared
    ) {
        self.category = category
        self.interactor = interactor
        self.visitedStore = visitedStore
        self.sortPreferenceStore = sortPreferenceStore
        self.sortMode = sortPreferenceStore.sortMode
        self.interactor.presenter = self
    }

    func setView(_ view: PostListHostViewProtocol) {
        self.view = view
    }

    var currentSortMode: PostListSortMode {
        sortMode
    }

    func viewDidLoad() {
        // 分类页面可能早于用户改排序就已创建，首次加载前对齐全局排序，避免先按旧排序请求一次。
        sortMode = sortPreferenceStore.sortMode
        loadFirstPageIfNeeded()
    }

    func syncSortModeWithPreference() -> Bool {
        let preferred = sortPreferenceStore.sortMode
        guard preferred != sortMode else { return false }
        sortMode = preferred
        resetAndLoadFirstPage()
        return true
    }

    func toggleSortMode() -> PostListSortMode {
        sortMode = sortMode.toggled
        sortPreferenceStore.sortMode = sortMode
        resetAndLoadFirstPage()
        delegate?.postListHostDidChangeSortMode(sortMode, category: category)
        return sortMode
    }

    func reloadFirstPage() {
        resetAndLoadFirstPage()
    }

    func didSelectPost(at index: Int) {
        guard items.indices.contains(index) else { return }
        let item = items[index]
        visitedStore.markVisited(post: item.post, visitedAt: Date())
        if !item.isVisited {
            items[index] = PostListItem(post: item.post, isVisited: true)
            view?.updateVisitedState(at: index, isVisited: true)
        }
        delegate?.postListHostDidSelectPost(item.post, category: category)
    }

    func didRequestRefresh() {
        refreshFirstPage()
    }

    func didRequestTabReselectRefresh() {
        // 首屏没加载成功时（例如停在错误页）重新走首屏加载，进行中则忽略
        guard hasLoadedFirstPage else {
            loadFirstPageIfNeeded()
            return
        }
        // 正在刷新或加载更多时不重复请求，也不震动
        guard !isRefreshing, !isLoadingFirstPage, !isLoadingMore else { return }
        isTabReselectRefreshing = true
        view?.showTabRefreshLoading()
        refreshFirstPage()
    }

    func didRequestFirstPageRetry() {
        resetAndLoadFirstPage()
    }

    func didApproachBottom(at index: Int, totalCount: Int) {
        loadMoreIfNeeded(currentIndex: index, totalCount: totalCount)
    }
}

extension PostListHostPresenter: PostListHostInteractorOutput {
    func didLoadPosts(
        _ posts: [PostSummary],
        category: PostListCategoryItem,
        sortMode: PostListSortMode,
        generation: Int
    ) {
        guard generation == requestGeneration else { return }
        guard category == self.category else { return }
        guard sortMode == self.sortMode else { return }
        items = postItems(for: posts)
        loadedIDs = Set(posts.map(\.id))
        hasMorePages = !posts.isEmpty
        nextPage = 2
        hasLoadedFirstPage = true
        isLoadingFirstPage = false
        isRefreshing = false
        isLoadingMore = false
        view?.setItems(items)
        view?.hideFirstPageError()
        view?.hideLoadingSkeleton()
        view?.hideRefreshing()
        view?.hideLoadingMore()
        finishTabReselectRefresh(failureMessage: nil)
        delegate?.postListHostDidLoadFirstPage(category: category)
    }

    func didLoadMorePosts(
        _ posts: [PostSummary],
        page: Int,
        category: PostListCategoryItem,
        sortMode: PostListSortMode,
        generation: Int
    ) {
        guard generation == requestGeneration else { return }
        guard category == self.category else { return }
        guard sortMode == self.sortMode else { return }
        isLoadingMore = false

        guard !posts.isEmpty else {
            hasMorePages = false
            AppLog.info(.postList, "帖子列表加载更多结束: 无更多分页 page=\(page), category=\(category.rawValue)")
            view?.hideLoadingMore()
            return
        }

        nextPage = page + 1
        var appended = false
        for post in posts where loadedIDs.insert(post.id).inserted {
            items.append(PostListItem(post: post, isVisited: visitedStore.isVisited(postID: post.id)))
            appended = true
        }

        if appended {
            AppLog.info(.postList, "帖子列表加载更多完成: page=\(page), category=\(category.rawValue), received=\(posts.count), total=\(items.count)")
            view?.setItems(items)
        }
        view?.hideLoadingMore()
    }

    func didFailLoadPosts(error: String, category: PostListCategoryItem, sortMode: PostListSortMode, generation: Int) {
        guard generation == requestGeneration else { return }
        guard category == self.category else { return }
        guard sortMode == self.sortMode else { return }
        isLoadingFirstPage = false
        isRefreshing = false
        isLoadingMore = false
        view?.hideLoadingSkeleton()
        view?.hideRefreshing()
        view?.hideLoadingMore()
        finishTabReselectRefresh(failureMessage: error)
        if items.isEmpty {
            view?.showFirstPageError(message: error)
        }
    }

    func didFailLoadMorePosts(error: String, page: Int, category: PostListCategoryItem, sortMode: PostListSortMode, generation: Int) {
        guard generation == requestGeneration else { return }
        guard category == self.category else { return }
        guard sortMode == self.sortMode else { return }
        isLoadingMore = false
        AppLog.warning(.postList, "帖子列表加载更多失败: page=\(page), category=\(category.rawValue), error=\(error)")
        view?.hideLoadingMore()
    }
}

private extension PostListHostPresenter {
    func finishTabReselectRefresh(failureMessage: String?) {
        guard isTabReselectRefreshing else { return }
        isTabReselectRefreshing = false
        view?.hideTabRefreshLoading(failureMessage: failureMessage)
    }

    func resetAndLoadFirstPage() {
        // 排序切回原值时也必须丢弃之前的首页、分页及失败回调。
        requestGeneration += 1
        // 切换排序等会丢弃进行中的刷新结果，加载提示要一起收起
        finishTabReselectRefresh(failureMessage: nil)
        items = []
        loadedIDs = []
        nextPage = 2
        hasMorePages = true
        hasLoadedFirstPage = false
        // 新批次独立维护加载状态，不等待旧请求结束。
        isLoadingFirstPage = false
        isRefreshing = false
        isLoadingMore = false
        view?.setItems([])
        view?.hideFirstPageError()
        loadFirstPageIfNeeded()
    }

    func loadFirstPageIfNeeded() {
        guard !hasLoadedFirstPage else { return }
        guard !isLoadingFirstPage else { return }
        isLoadingFirstPage = true
        isRefreshing = false
        isLoadingMore = false
        view?.showLoadingSkeleton()
        view?.hideFirstPageError()
        view?.hideRefreshing()
        view?.hideLoadingMore()
        interactor.loadPosts(category: category, sortMode: sortMode, generation: requestGeneration)
    }

    func refreshFirstPage() {
        guard hasLoadedFirstPage else { return }
        guard !isRefreshing else { return }
        guard !isLoadingFirstPage else { return }
        guard !isLoadingMore else { return }
        requestGeneration += 1
        isRefreshing = true
        interactor.loadPosts(category: category, sortMode: sortMode, generation: requestGeneration)
    }

    func loadMoreIfNeeded(currentIndex: Int, totalCount: Int) {
        guard totalCount > 0 else {
            AppLog.debug(.postList, "忽略帖子列表加载更多: totalCount=0")
            return
        }
        guard hasMorePages else {
            AppLog.debug(.postList, "忽略帖子列表加载更多: 已无更多分页 category=\(category.rawValue)")
            return
        }
        guard !isLoadingMore else {
            AppLog.debug(.postList, "忽略帖子列表加载更多: 正在加载更多 category=\(category.rawValue)")
            return
        }
        guard !isLoadingFirstPage else {
            AppLog.debug(.postList, "忽略帖子列表加载更多: 首屏仍在加载 category=\(category.rawValue)")
            return
        }

        isLoadingMore = true
        AppLog.info(
            .postList,
            "触发帖子列表加载更多: page=\(nextPage), category=\(category.rawValue), sortMode=\(sortMode.rawValue), currentIndex=\(currentIndex), totalCount=\(totalCount)"
        )
        view?.showLoadingMore()
        interactor.loadMorePosts(page: nextPage, category: category, sortMode: sortMode, generation: requestGeneration)
    }

    func postItems(for posts: [PostSummary]) -> [PostListItem] {
        posts.map { post in
            PostListItem(post: post, isVisited: visitedStore.isVisited(postID: post.id))
        }
    }
}
