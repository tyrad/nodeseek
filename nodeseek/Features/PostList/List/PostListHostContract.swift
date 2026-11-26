//
//  PostListHostContract.swift
//  nodeseek
//

import Foundation

// MARK: - View Protocol (Presenter -> View)
protocol PostListHostViewProtocol: AnyObject {
    func setItems(_ items: [PostListItem])
    func showLoadingSkeleton()
    func hideLoadingSkeleton()
    func showFirstPageError(message: String)
    func hideFirstPageError()
    func showTabRefreshLoading()
    func hideTabRefreshLoading(failureMessage: String?)
    func hideRefreshing()
    func showLoadingMore()
    func hideLoadingMore()
    func updateVisitedState(at index: Int, isVisited: Bool)
}

// MARK: - Presenter Delegate (Presenter -> Parent)
protocol PostListHostPresenterDelegate: AnyObject {
    func postListHostDidSelectPost(_ post: PostSummary, category: PostListCategoryItem)
    func postListHostDidChangeSortMode(_ sortMode: PostListSortMode, category: PostListCategoryItem)
    func postListHostDidLoadFirstPage(category: PostListCategoryItem)
}

// MARK: - Presenter Protocol (View -> Presenter)
protocol PostListHostPresenterProtocol: AnyObject {
    var delegate: PostListHostPresenterDelegate? { get set }
    var currentSortMode: PostListSortMode { get }

    func setView(_ view: PostListHostViewProtocol)
    func viewDidLoad()
    /// 当前排序与全局偏好不一致时，切换并从第一页重新加载；返回是否发生了切换。
    func syncSortModeWithPreference() -> Bool
    func toggleSortMode() -> PostListSortMode
    func reloadFirstPage()
    func didSelectPost(at index: Int)
    func didRequestRefresh()
    func didRequestTabReselectRefresh()
    func didRequestFirstPageRetry()
    func didApproachBottom(at index: Int, totalCount: Int)
}

// MARK: - Interactor Input (Presenter -> Interactor)
protocol PostListHostInteractorInput: AnyObject {
    var presenter: PostListHostInteractorOutput? { get set }

    func loadPosts(category: PostListCategoryItem, sortMode: PostListSortMode, generation: Int)
    func loadMorePosts(page: Int, category: PostListCategoryItem, sortMode: PostListSortMode, generation: Int)
}

// MARK: - Interactor Output (Interactor -> Presenter)
protocol PostListHostInteractorOutput: AnyObject {
    func didLoadPosts(_ posts: [PostSummary], category: PostListCategoryItem, sortMode: PostListSortMode, generation: Int)
    func didLoadMorePosts(_ posts: [PostSummary], page: Int, category: PostListCategoryItem, sortMode: PostListSortMode, generation: Int)
    func didFailLoadPosts(error: String, category: PostListCategoryItem, sortMode: PostListSortMode, generation: Int)
    func didFailLoadMorePosts(error: String, page: Int, category: PostListCategoryItem, sortMode: PostListSortMode, generation: Int)
}

// MARK: - Router Protocol (Module Assembly)
protocol PostListHostRouterProtocol: AnyObject {
    static func createModule(
        category: PostListCategoryItem,
        visitedStore: VisitedPostStoreProtocol,
        delegate: PostListHostPresenterDelegate?
    ) -> PostListHostViewController
}
