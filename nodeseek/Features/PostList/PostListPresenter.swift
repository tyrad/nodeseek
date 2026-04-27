//
//  PostListPresenter.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation

class PostListPresenter: PostListPresenterProtocol {
    private struct CategoryState {
        var posts: [PostSummary] = []
        var loadedIDs: Set<String> = []
        var nextPage: Int = 2
        var hasMorePages: Bool = true
        var hasLoadedFirstPage: Bool = false
        var isLoadingFirstPage: Bool = false
        var isLoadingMore: Bool = false
    }
    
    // MARK: - Properties
    private weak var view: PostListViewProtocol?
    private let interactor: PostListInteractorInput
    private let router: PostListRouterProtocol
    private var categoryStates: [PostListCategory: CategoryState] = [:]
    private let categories = PostListCategory.allCases
    private var currentCategory: PostListCategory = .all
    
    // MARK: - Initialization
    init(
        interactor: PostListInteractorInput,
        router: PostListRouterProtocol
    ) {
        self.interactor = interactor
        self.router = router
    }
    
    // MARK: - Setup
    func setView(_ view: PostListViewProtocol) {
        self.view = view
    }
    
    // MARK: - Methods
    func viewDidLoad() {
        view?.renderCategories(categories, selected: currentCategory)
        presentCurrentCategory(useCache: true)
    }

    func didSelectCategory(_ category: PostListCategory) {
        guard category != currentCategory else { return }
        currentCategory = category
        view?.renderCategories(categories, selected: currentCategory)
        presentCurrentCategory(useCache: true)
    }

    private func presentCurrentCategory(useCache: Bool) {
        var state = state(for: currentCategory)
        if !useCache {
            state = CategoryState()
            categoryStates[currentCategory] = state
        }

        view?.render(posts: state.posts)
        if state.isLoadingFirstPage {
            view?.showLoading()
        } else {
            view?.hideLoading()
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
        state.isLoadingMore = false
        categoryStates[category] = state

        if category == currentCategory {
            view?.showLoading()
            view?.hideLoadingMore()
        }

        interactor.loadPosts(category: category)
    }
    
    func didSelectPost(at index: Int) {
        let posts = state(for: currentCategory).posts
        guard posts.indices.contains(index) else { return }
        router.navigateToPostDetail(post: posts[index])
    }

    func didApproachBottom(currentIndex: Int, totalCount: Int) {
        var state = state(for: currentCategory)
        guard totalCount > 0 else { return }
        guard state.hasMorePages else { return }
        guard !state.isLoadingMore else { return }
        guard !state.isLoadingFirstPage else { return }
        guard currentIndex >= max(totalCount - 3, 0) else { return }

        state.isLoadingMore = true
        categoryStates[currentCategory] = state
        view?.showLoadingMore()
        interactor.loadMorePosts(page: state.nextPage, category: currentCategory)
    }
}

// MARK: - Interactor Output
extension PostListPresenter: PostListInteractorOutput {
    
    func didLoadPosts(_ posts: [PostSummary], category: PostListCategory) {
        var state = state(for: category)
        state.posts = posts
        state.loadedIDs = Set(posts.map(\.id))
        state.hasMorePages = !posts.isEmpty
        state.nextPage = 2
        state.hasLoadedFirstPage = true
        state.isLoadingFirstPage = false
        state.isLoadingMore = false
        categoryStates[category] = state

        guard category == currentCategory else { return }
        view?.hideLoading()
        view?.hideLoadingMore()
        view?.render(posts: state.posts)
    }

    func didLoadMorePosts(_ posts: [PostSummary], page: Int, category: PostListCategory) {
        var state = state(for: category)
        state.isLoadingMore = false

        guard !posts.isEmpty else {
            state.hasMorePages = false
            categoryStates[category] = state
            if category == currentCategory {
                view?.hideLoadingMore()
            }
            return
        }

        state.nextPage = page + 1
        var appended = false
        for post in posts where state.loadedIDs.insert(post.id).inserted {
            state.posts.append(post)
            appended = true
        }
        categoryStates[category] = state

        guard category == currentCategory else { return }
        view?.hideLoadingMore()
        if appended {
            view?.render(posts: state.posts)
        }
    }
    
    func didFailLoadPosts(error: String, category: PostListCategory) {
        var state = state(for: category)
        state.isLoadingFirstPage = false
        state.isLoadingMore = false
        categoryStates[category] = state

        guard category == currentCategory else { return }
        view?.hideLoading()
        view?.hideLoadingMore()
        view?.showError(message: error)
    }

    func didFailLoadMorePosts(error: String, page: Int, category: PostListCategory) {
        var state = state(for: category)
        state.isLoadingMore = false
        categoryStates[category] = state

        guard category == currentCategory else { return }
        view?.hideLoadingMore()
        view?.showError(message: "第 \(page) 页加载失败：\(error)")
    }
}
