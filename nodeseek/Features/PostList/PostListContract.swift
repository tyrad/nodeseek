//
//  PostListContract.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation

// MARK: - View Protocol (Presenter -> View)
protocol PostListViewProtocol: AnyObject {
    func showLoading()
    func hideLoading()
    func showRefreshing()
    func hideRefreshing()
    func showLoadingMore()
    func hideLoadingMore()
    func showError(message: String)
    #if DEBUG
    func showDetailTestInput()
    #endif
    func renderCategories(_ categories: [PostListCategory], selected: PostListCategory)
    func renderSortMode(_ sortMode: PostListSortMode)
    func render(posts: [PostSummary])
}

// MARK: - Presenter Protocol (View -> Presenter)
protocol PostListPresenterProtocol: AnyObject {
    func viewDidLoad()
    func didSelectCategory(_ category: PostListCategory)
    func didToggleSortMode()
    func didTapLogin()
    #if DEBUG
    func didTapDetailTest()
    func didSubmitDetailTestURL(_ rawURL: String)
    #endif
    func didPullToRefresh()
    func didSelectPost(at index: Int)
    func didApproachBottom(currentIndex: Int, totalCount: Int)
}

// MARK: - Interactor Input (Presenter -> Interactor)
protocol PostListInteractorInput: AnyObject {
    func loadPosts(category: PostListCategory, sortMode: PostListSortMode)
    func loadMorePosts(page: Int, category: PostListCategory, sortMode: PostListSortMode)
}

// MARK: - Interactor Output (Interactor -> Presenter)
protocol PostListInteractorOutput: AnyObject {
    func didLoadPosts(_ posts: [PostSummary], category: PostListCategory, sortMode: PostListSortMode)
    func didLoadMorePosts(_ posts: [PostSummary], page: Int, category: PostListCategory, sortMode: PostListSortMode)
    func didFailLoadPosts(error: String, category: PostListCategory, sortMode: PostListSortMode)
    func didFailLoadMorePosts(error: String, page: Int, category: PostListCategory, sortMode: PostListSortMode)
}

// MARK: - Router Protocol (Presenter -> Router)
protocol PostListRouterProtocol: AnyObject {
    func navigateToPostDetail(post: PostSummary)
    func navigateToPostDetail(post: PostSummary, page: Int)
    func navigateToLogin(onClose: @escaping @MainActor () -> Void)
}
