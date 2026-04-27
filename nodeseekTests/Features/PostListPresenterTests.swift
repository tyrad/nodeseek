//
//  PostListPresenterTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/4/27.
//

import Foundation
import Testing
@testable import nodeseek

@MainActor
struct PostListPresenterTests {
    @Test func selectingPostNavigatesToDetail() {
        let view = SpyPostListView()
        let interactor = SpyPostListInteractor()
        let router = SpyPostListRouter()
        let presenter = PostListPresenter(interactor: interactor, router: router)
        presenter.setView(view)
        let post = PostSummary(
            id: "1",
            title: "标题",
            url: URL(string: "https://www.nodeseek.com/post-1")!,
            authorName: "mist",
            nodeName: "开发",
            replyCount: 3,
            lastActivityText: "刚刚"
        )

        presenter.didLoadPosts([post], category: .all)
        presenter.didSelectPost(at: 0)

        #expect(router.selectedPost?.id == "1")
    }

    @Test func approachingBottomTriggersLoadMoreForNextPage() {
        let view = SpyPostListView()
        let interactor = SpyPostListInteractor()
        let router = SpyPostListRouter()
        let presenter = PostListPresenter(interactor: interactor, router: router)
        presenter.setView(view)
        let post = PostSummary(
            id: "1",
            title: "标题",
            url: URL(string: "https://www.nodeseek.com/post-1")!,
            authorName: "mist",
            nodeName: "开发",
            replyCount: 3,
            lastActivityText: "刚刚"
        )

        presenter.didLoadPosts([post], category: .all)
        presenter.didApproachBottom(currentIndex: 0, totalCount: 1)

        #expect(interactor.loadMorePages == [2])
        #expect(view.showLoadingMoreCount == 1)
        #expect(interactor.loadMoreCategories == [.all])
    }

    @Test func loadMoreAppendsUniquePosts() {
        let view = SpyPostListView()
        let interactor = SpyPostListInteractor()
        let router = SpyPostListRouter()
        let presenter = PostListPresenter(interactor: interactor, router: router)
        presenter.setView(view)
        let first = PostSummary(
            id: "1",
            title: "标题1",
            url: URL(string: "https://www.nodeseek.com/post-1")!,
            authorName: "mist",
            nodeName: "开发",
            replyCount: 3,
            lastActivityText: "刚刚"
        )
        let duplicate = PostSummary(
            id: "1",
            title: "标题1",
            url: URL(string: "https://www.nodeseek.com/post-1")!,
            authorName: "mist",
            nodeName: "开发",
            replyCount: 3,
            lastActivityText: "刚刚"
        )
        let second = PostSummary(
            id: "2",
            title: "标题2",
            url: URL(string: "https://www.nodeseek.com/post-2")!,
            authorName: "mist",
            nodeName: "开发",
            replyCount: 4,
            lastActivityText: "1 分钟前"
        )

        presenter.didLoadPosts([first], category: .all)
        presenter.didApproachBottom(currentIndex: 0, totalCount: 1)
        presenter.didLoadMorePosts([duplicate, second], page: 2, category: .all)
        presenter.didSelectPost(at: 1)

        #expect(view.renderCallCount == 2)
        #expect(view.lastRenderedPostsCount == 2)
        #expect(router.selectedPost?.id == "2")
    }

    @Test func switchingBackToLoadedCategoryUsesCachedData() {
        let view = SpyPostListView()
        let interactor = SpyPostListInteractor()
        let router = SpyPostListRouter()
        let presenter = PostListPresenter(interactor: interactor, router: router)
        presenter.setView(view)

        let allPost = PostSummary(
            id: "all-1",
            title: "全部帖子",
            url: URL(string: "https://www.nodeseek.com/post-all-1")!,
            authorName: "mist",
            nodeName: "日常",
            replyCount: 1,
            lastActivityText: "刚刚"
        )
        let techPost = PostSummary(
            id: "tech-1",
            title: "技术帖子",
            url: URL(string: "https://www.nodeseek.com/post-tech-1")!,
            authorName: "mist",
            nodeName: "技术",
            replyCount: 1,
            lastActivityText: "刚刚"
        )

        presenter.viewDidLoad()
        #expect(interactor.loadPostsCategories == [.all])

        presenter.didLoadPosts([allPost], category: .all)
        presenter.didSelectCategory(.tech)
        #expect(interactor.loadPostsCategories == [.all, .tech])

        presenter.didLoadPosts([techPost], category: .tech)
        presenter.didSelectCategory(.all)

        #expect(interactor.loadPostsCategories == [.all, .tech])
        #expect(view.lastRenderedPostIDs == ["all-1"])
        #expect(view.selectedCategory == .all)
    }

    @Test func pullToRefreshReloadsCurrentCategoryWithoutResettingListState() {
        let view = SpyPostListView()
        let interactor = SpyPostListInteractor()
        let router = SpyPostListRouter()
        let presenter = PostListPresenter(interactor: interactor, router: router)
        presenter.setView(view)

        let initialPost = PostSummary(
            id: "all-1",
            title: "全部帖子",
            url: URL(string: "https://www.nodeseek.com/post-all-1")!,
            authorName: "mist",
            nodeName: "日常",
            replyCount: 1,
            lastActivityText: "刚刚"
        )
        let refreshedPost = PostSummary(
            id: "all-2",
            title: "全部帖子-刷新后",
            url: URL(string: "https://www.nodeseek.com/post-all-2")!,
            authorName: "mist",
            nodeName: "日常",
            replyCount: 2,
            lastActivityText: "1 分钟前"
        )

        presenter.viewDidLoad()
        presenter.didLoadPosts([initialPost], category: .all)

        let showRefreshingBefore = view.showRefreshingCount
        let hideRefreshingBefore = view.hideRefreshingCount
        presenter.didPullToRefresh()

        #expect(interactor.loadPostsCategories == [.all, .all])
        #expect(view.showRefreshingCount == showRefreshingBefore + 1)

        presenter.didLoadPosts([refreshedPost], category: .all)
        #expect(view.hideRefreshingCount == hideRefreshingBefore + 1)
        #expect(view.lastRenderedPostIDs == ["all-2"])
    }
}

@MainActor
private final class SpyPostListView: PostListViewProtocol {
    var showLoadingCount = 0
    var hideLoadingCount = 0
    var showRefreshingCount = 0
    var hideRefreshingCount = 0
    var showLoadingMoreCount = 0
    var hideLoadingMoreCount = 0
    var renderCallCount = 0
    var lastRenderedPostsCount = 0
    var lastRenderedPostIDs: [String] = []
    var lastErrorMessage: String?
    var renderedCategories: [PostListCategory] = []
    var selectedCategory: PostListCategory = .all

    func showLoading() {
        showLoadingCount += 1
    }

    func hideLoading() {
        hideLoadingCount += 1
    }

    func showRefreshing() {
        showRefreshingCount += 1
    }

    func hideRefreshing() {
        hideRefreshingCount += 1
    }

    func showLoadingMore() {
        showLoadingMoreCount += 1
    }

    func hideLoadingMore() {
        hideLoadingMoreCount += 1
    }

    func showError(message: String) {
        lastErrorMessage = message
    }

    func renderCategories(_ categories: [PostListCategory], selected: PostListCategory) {
        renderedCategories = categories
        selectedCategory = selected
    }

    func render(posts: [PostSummary]) {
        renderCallCount += 1
        lastRenderedPostsCount = posts.count
        lastRenderedPostIDs = posts.map(\.id)
    }
}

@MainActor
private final class SpyPostListInteractor: PostListInteractorInput {
    var loadPostsCallCount = 0
    var loadPostsCategories: [PostListCategory] = []
    var loadMorePages: [Int] = []
    var loadMoreCategories: [PostListCategory] = []

    func loadPosts(category: PostListCategory) {
        loadPostsCallCount += 1
        loadPostsCategories.append(category)
    }

    func loadMorePosts(page: Int, category: PostListCategory) {
        loadMorePages.append(page)
        loadMoreCategories.append(category)
    }
}

@MainActor
private final class SpyPostListRouter: PostListRouterProtocol {
    var selectedPost: PostSummary?

    func navigateToPostDetail(post: PostSummary) {
        selectedPost = post
    }
}
