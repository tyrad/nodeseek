//
//  PostTextureListHostPresenter.swift
//  nodeseek
//

import Foundation

final class PostTextureListHostPresenter: PostTextureListHostPresenterProtocol {
    weak var delegate: PostTextureListHostPresenterDelegate?

    private weak var view: PostTextureListHostViewProtocol?
    private let category: PostListCategoryItem
    private let interactor: PostTextureListHostInteractorInput
    private let visitedStore: VisitedPostStoreProtocol
    private var sortMode: PostListSortMode = .replyTime
    private var items: [PostListItem] = []
    private var loadedIDs: Set<String> = []
    private var nextPage: Int = 2
    private var hasMorePages = true
    private var hasLoadedFirstPage = false
    private var isLoadingFirstPage = false
    private var isRefreshing = false
    private var isLoadingMore = false

    init(
        category: PostListCategoryItem,
        interactor: PostTextureListHostInteractorInput,
        visitedStore: VisitedPostStoreProtocol
    ) {
        self.category = category
        self.interactor = interactor
        self.visitedStore = visitedStore
        self.interactor.presenter = self
    }

    func setView(_ view: PostTextureListHostViewProtocol) {
        self.view = view
    }

    var currentSortMode: PostListSortMode {
        sortMode
    }

    func viewDidLoad() {
        loadFirstPageIfNeeded()
    }

    func toggleSortMode() -> PostListSortMode {
        sortMode = sortMode.toggled
        resetAndLoadFirstPage()
        delegate?.postTextureListHostDidChangeSortMode(sortMode, category: category)
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
        delegate?.postTextureListHostDidSelectPost(item.post, category: category)
    }

    func didRequestRefresh() {
        refreshFirstPage()
    }

    func didRequestFirstPageRetry() {
        resetAndLoadFirstPage()
    }

    func didApproachBottom(at index: Int, totalCount: Int) {
        loadMoreIfNeeded(currentIndex: index, totalCount: totalCount)
    }
}

extension PostTextureListHostPresenter: PostTextureListHostInteractorOutput {
    func didLoadPosts(
        _ posts: [PostSummary],
        category: PostListCategoryItem,
        sortMode: PostListSortMode
    ) {
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
    }

    func didLoadMorePosts(
        _ posts: [PostSummary],
        page: Int,
        category: PostListCategoryItem,
        sortMode: PostListSortMode
    ) {
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

    func didFailLoadPosts(error: String, category: PostListCategoryItem, sortMode: PostListSortMode) {
        guard category == self.category else { return }
        guard sortMode == self.sortMode else { return }
        isLoadingFirstPage = false
        isRefreshing = false
        isLoadingMore = false
        view?.hideLoadingSkeleton()
        view?.hideRefreshing()
        view?.hideLoadingMore()
        if items.isEmpty {
            view?.showFirstPageError(message: error)
        }
    }

    func didFailLoadMorePosts(error: String, page: Int, category: PostListCategoryItem, sortMode: PostListSortMode) {
        guard category == self.category else { return }
        guard sortMode == self.sortMode else { return }
        isLoadingMore = false
        AppLog.warning(.postList, "帖子列表加载更多失败: page=\(page), category=\(category.rawValue), error=\(error)")
        view?.hideLoadingMore()
    }
}

private extension PostTextureListHostPresenter {
    func resetAndLoadFirstPage() {
        items = []
        loadedIDs = []
        nextPage = 2
        hasMorePages = true
        hasLoadedFirstPage = false
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
        interactor.loadPosts(category: category, sortMode: sortMode)
    }

    func refreshFirstPage() {
        guard hasLoadedFirstPage else { return }
        guard !isRefreshing else { return }
        guard !isLoadingFirstPage else { return }
        guard !isLoadingMore else { return }
        isRefreshing = true
        interactor.loadPosts(category: category, sortMode: sortMode)
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
        interactor.loadMorePosts(page: nextPage, category: category, sortMode: sortMode)
    }

    func postItems(for posts: [PostSummary]) -> [PostListItem] {
        posts.map { post in
            PostListItem(post: post, isVisited: visitedStore.isVisited(postID: post.id))
        }
    }
}
