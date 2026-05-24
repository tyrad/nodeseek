//
//  PostTextureListHostContract.swift
//  nodeseek
//

import Foundation

// MARK: - View Protocol (Presenter -> View)
protocol PostTextureListHostViewProtocol: AnyObject {
    func setItems(_ items: [PostListItem])
    func showLoadingSkeleton()
    func hideLoadingSkeleton()
    func showFirstPageError(message: String)
    func hideFirstPageError()
    func hideRefreshing()
    func showLoadingMore()
    func hideLoadingMore()
    func updateVisitedState(at index: Int, isVisited: Bool)
}

// MARK: - Presenter Delegate (Presenter -> Parent)
protocol PostTextureListHostPresenterDelegate: AnyObject {
    func postTextureListHostDidSelectPost(_ post: PostSummary, category: PostListCategoryItem)
    func postTextureListHostDidChangeSortMode(_ sortMode: PostListSortMode, category: PostListCategoryItem)
    func postTextureListHostDidLoadFirstPage(category: PostListCategoryItem)
}

// MARK: - Presenter Protocol (View -> Presenter)
protocol PostTextureListHostPresenterProtocol: AnyObject {
    var delegate: PostTextureListHostPresenterDelegate? { get set }
    var currentSortMode: PostListSortMode { get }

    func setView(_ view: PostTextureListHostViewProtocol)
    func viewDidLoad()
    func toggleSortMode() -> PostListSortMode
    func reloadFirstPage()
    func didSelectPost(at index: Int)
    func didRequestRefresh()
    func didRequestFirstPageRetry()
    func didApproachBottom(at index: Int, totalCount: Int)
}

// MARK: - Interactor Input (Presenter -> Interactor)
protocol PostTextureListHostInteractorInput: AnyObject {
    var presenter: PostTextureListHostInteractorOutput? { get set }

    func loadPosts(category: PostListCategoryItem, sortMode: PostListSortMode)
    func loadMorePosts(page: Int, category: PostListCategoryItem, sortMode: PostListSortMode)
}

// MARK: - Interactor Output (Interactor -> Presenter)
protocol PostTextureListHostInteractorOutput: AnyObject {
    func didLoadPosts(_ posts: [PostSummary], category: PostListCategoryItem, sortMode: PostListSortMode)
    func didLoadMorePosts(_ posts: [PostSummary], page: Int, category: PostListCategoryItem, sortMode: PostListSortMode)
    func didFailLoadPosts(error: String, category: PostListCategoryItem, sortMode: PostListSortMode)
    func didFailLoadMorePosts(error: String, page: Int, category: PostListCategoryItem, sortMode: PostListSortMode)
}

// MARK: - Router Protocol (Module Assembly)
protocol PostTextureListHostRouterProtocol: AnyObject {
    static func createModule(
        category: PostListCategoryItem,
        visitedStore: VisitedPostStoreProtocol,
        delegate: PostTextureListHostPresenterDelegate?
    ) -> PostTextureListHostViewController
}
