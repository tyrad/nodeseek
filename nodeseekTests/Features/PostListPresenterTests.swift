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

    @Test func loadingPostsComposesVisitedStateBeforeRendering() {
        let view = SpyPostListView()
        let interactor = SpyPostListInteractor()
        let router = SpyPostListRouter()
        let visitedStore = FakeVisitedPostStore()
        visitedStore.visitedIDs = ["2"]
        let presenter = PostListPresenter(interactor: interactor, router: router, visitedStore: visitedStore)
        presenter.setView(view)
        let first = makePost(id: "1", title: "未访问")
        let second = makePost(id: "2", title: "已访问")

        presenter.didLoadPosts([first, second], category: .all)

        #expect(view.lastRenderedPostIDs == ["1", "2"])
        #expect(view.lastRenderedVisitedFlags == [false, true])
    }

    @Test func selectingUnvisitedPostMarksVisitedAndReloadsOnlySelectedRowBeforeNavigation() {
        let view = SpyPostListView()
        let interactor = SpyPostListInteractor()
        let router = SpyPostListRouter()
        let visitedStore = FakeVisitedPostStore()
        let presenter = PostListPresenter(interactor: interactor, router: router, visitedStore: visitedStore)
        presenter.setView(view)
        let post = makePost(id: "1", title: "标题")

        presenter.didLoadPosts([post], category: .all)
        presenter.didSelectPost(at: 0)

        #expect(visitedStore.markedPosts.map(\.id) == ["1"])
        #expect(view.updatedVisitedRows == [0])
        #expect(view.updatedVisitedFlags == [true])
        #expect(router.selectedPost?.id == "1")
    }

    @Test func selectingAlreadyVisitedPostDoesNotReloadRowAgain() {
        let view = SpyPostListView()
        let interactor = SpyPostListInteractor()
        let router = SpyPostListRouter()
        let visitedStore = FakeVisitedPostStore()
        visitedStore.visitedIDs = ["1"]
        let presenter = PostListPresenter(interactor: interactor, router: router, visitedStore: visitedStore)
        presenter.setView(view)
        let post = makePost(id: "1", title: "标题")

        presenter.didLoadPosts([post], category: .all)
        presenter.didSelectPost(at: 0)

        #expect(visitedStore.markedPosts.map(\.id) == ["1"])
        #expect(view.updatedVisitedRows.isEmpty)
        #expect(router.selectedPost?.id == "1")
    }

    @Test func tappingRecentVisitedRoutesVisitedStore() {
        let view = SpyPostListView()
        let interactor = SpyPostListInteractor()
        let router = SpyPostListRouter()
        let visitedStore = FakeVisitedPostStore()
        let presenter = PostListPresenter(interactor: interactor, router: router, visitedStore: visitedStore)
        presenter.setView(view)

        presenter.didTapRecentVisited()

        #expect(router.recentVisitedStore === visitedStore)
    }

    @Test func tappingSearchRoutesToSearchPage() {
        let interactor = SpyPostListInteractor()
        let router = SpyPostListRouter()
        let presenter = PostListPresenter(interactor: interactor, router: router)

        presenter.didTapSearch()

        #expect(router.navigateToSearchCount == 1)
    }

    @Test func tappingNotificationRoutesToNotificationPage() throws {
        let interactor = SpyPostListInteractor()
        let router = SpyPostListRouter()
        let presenter = PostListPresenter(interactor: interactor, router: router)
        let url = try #require(URL(string: "https://www.nodeseek.com/notification"))

        presenter.didTapNotification(url: url)

        #expect(router.notificationURL == url)
    }

    @Test func tappingSettingsRoutesToSettingsPage() {
        let interactor = SpyPostListInteractor()
        let router = SpyPostListRouter()
        let presenter = PostListPresenter(interactor: interactor, router: router)

        presenter.didTapSettings()

        #expect(router.navigateToSettingsCount == 1)
    }

    @Test func settingsLogoutReloadsCurrentCategoryWithoutCache() {
        let view = SpyPostListView()
        let interactor = SpyPostListInteractor()
        let router = SpyPostListRouter()
        let presenter = PostListPresenter(interactor: interactor, router: router)
        presenter.setView(view)
        presenter.viewDidLoad()
        interactor.loadPostsCallCount = 0
        interactor.loadPostsCategories.removeAll()

        presenter.didTapSettings()
        router.onSettingsLogout?()

        #expect(interactor.loadPostsCallCount == 1)
        #expect(interactor.loadPostsCategories == [.all])
    }

    @Test func settingsDebugCallbacksReuseExistingLogAndDetailActions() {
        let view = SpyPostListView()
        let interactor = SpyPostListInteractor()
        let router = SpyPostListRouter()
        let presenter = PostListPresenter(interactor: interactor, router: router)
        presenter.setView(view)

        presenter.didTapSettings()
        router.onSettingsLogFile?()
        router.onSettingsDetailTest?()

        #expect(router.navigateToLogFileCount == 1)
        #expect(view.events.contains("showDetailTestInput"))
    }

    @Test func recommendedReadingCategoryRendersLast() {
        let view = SpyPostListView()
        let interactor = SpyPostListInteractor()
        let router = SpyPostListRouter()
        let presenter = PostListPresenter(interactor: interactor, router: router)
        presenter.setView(view)

        presenter.viewDidLoad()

        #expect(view.renderedCategories.last == .award)
    }

    @Test func tappingNewDiscussionRoutesToNewDiscussionWebView() {
        let interactor = SpyPostListInteractor()
        let router = SpyPostListRouter()
        let presenter = PostListPresenter(interactor: interactor, router: router)

        presenter.didTapNewDiscussion()

        #expect(router.navigateToNewDiscussionCount == 1)
    }

    @Test func tappingLogFileRoutesToLogFileViewer() {
        let view = SpyPostListView()
        let interactor = SpyPostListInteractor()
        let router = SpyPostListRouter()
        let presenter = PostListPresenter(interactor: interactor, router: router)
        presenter.setView(view)

        presenter.didTapLogFile()

        #expect(router.navigateToLogFileCount == 1)
    }

    @Test func submittingDetailTestURLNavigatesToParsedPostPage() throws {
        let view = SpyPostListView()
        let interactor = SpyPostListInteractor()
        let router = SpyPostListRouter()
        let presenter = PostListPresenter(interactor: interactor, router: router)
        presenter.setView(view)

        presenter.didSubmitDetailTestURL("https://www.nodeseek.com/post-705039-2")

        #expect(router.selectedPost?.id == "705039")
        #expect(router.selectedPost?.url.absoluteString == "https://www.nodeseek.com/post-705039-2")
        #expect(router.selectedPage == 2)
        #expect(view.lastErrorMessage == nil)
    }

    @Test func submittingInvalidDetailTestURLShowsError() {
        let view = SpyPostListView()
        let interactor = SpyPostListInteractor()
        let router = SpyPostListRouter()
        let presenter = PostListPresenter(interactor: interactor, router: router)
        presenter.setView(view)

        presenter.didSubmitDetailTestURL("https://example.com/post-705039-1")

        #expect(router.selectedPost == nil)
        #expect(view.lastErrorMessage == "请输入 NodeSeek 帖子详情链接，例如 https://www.nodeseek.com/post-705039-1")
    }

    @Test func detailTestTargetAcceptsRelativePostURL() throws {
        let target = try #require(PostDetailTestTarget(rawValue: "/post-705039-3"))

        #expect(target.post.id == "705039")
        #expect(target.page == 3)
        #expect(target.post.title == "详情测试 #705039")
    }

    @Test func detailTestTargetDefaultsMissingPageToFirstPage() throws {
        let target = try #require(PostDetailTestTarget(rawValue: "https://www.nodeseek.com/post-705039"))

        #expect(target.post.id == "705039")
        #expect(target.page == 1)
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
        #expect(interactor.loadPostsSortModes == [.replyTime])
        #expect(view.renderedSortMode == .replyTime)

        presenter.didLoadPosts([allPost], category: .all)
        presenter.didSelectCategory(.tech)
        #expect(interactor.loadPostsCategories == [.all, .tech])
        #expect(interactor.loadPostsSortModes == [.replyTime, .replyTime])

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

    @Test func reselectingCurrentCategoryReloadsFirstPageWithSkeletonAndClearsItems() {
        let view = SpyPostListView()
        let interactor = SpyPostListInteractor()
        let router = SpyPostListRouter()
        let presenter = PostListPresenter(interactor: interactor, router: router)
        presenter.setView(view)
        let post = makePost(id: "1", title: "旧帖子")

        presenter.viewDidLoad()
        presenter.didLoadPosts([post], category: .all)
        view.events.removeAll()

        presenter.didReselectCategory(.all)

        #expect(view.lastRenderedPostIDs.isEmpty)
        #expect(view.events.first == "render")
        #expect(view.events.contains("hideFirstPageError"))
        #expect(view.events.contains("showLoading"))
        #expect(interactor.loadPostsCategories == [.all, .all])
    }

    @Test func firstPageLoadFailureShowsInlineRetryErrorWhenListIsEmpty() {
        let view = SpyPostListView()
        let interactor = SpyPostListInteractor()
        let router = SpyPostListRouter()
        let presenter = PostListPresenter(interactor: interactor, router: router)
        presenter.setView(view)

        presenter.viewDidLoad()
        let hideLoadingBefore = view.hideLoadingCount
        presenter.didFailLoadPosts(error: "网络超时", category: .all)

        #expect(view.hideLoadingCount == hideLoadingBefore + 1)
        #expect(view.firstPageErrorMessages == ["网络超时"])
        #expect(view.lastErrorMessage == nil)
    }

    @Test func retryingFirstPageErrorReloadsCurrentCategory() {
        let view = SpyPostListView()
        let interactor = SpyPostListInteractor()
        let router = SpyPostListRouter()
        let presenter = PostListPresenter(interactor: interactor, router: router)
        presenter.setView(view)

        presenter.viewDidLoad()
        presenter.didFailLoadPosts(error: "网络超时", category: .all)
        view.events.removeAll()

        presenter.didRetryFirstPage()

        #expect(view.events.contains("hideFirstPageError"))
        #expect(view.events.contains("showLoading"))
        #expect(interactor.loadPostsCategories == [.all, .all])
    }

    @Test func togglingSortModeReloadsCurrentCategoryFromFirstPage() {
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
        let second = PostSummary(
            id: "2",
            title: "标题2",
            url: URL(string: "https://www.nodeseek.com/post-2")!,
            authorName: "mist",
            nodeName: "开发",
            replyCount: 4,
            lastActivityText: "1 分钟前"
        )

        presenter.viewDidLoad()
        presenter.didLoadPosts([first], category: .all)
        presenter.didApproachBottom(currentIndex: 0, totalCount: 1)
        presenter.didLoadMorePosts([second], page: 2, category: .all)

        presenter.didToggleSortMode()

        #expect(view.renderedSortMode == .postTime)
        #expect(view.lastRenderedPostIDs.isEmpty)
        #expect(interactor.loadPostsCategories == [.all, .all])
        #expect(interactor.loadPostsSortModes == [.replyTime, .postTime])

        presenter.didLoadPosts([second], category: .all, sortMode: .postTime)
        presenter.didApproachBottom(currentIndex: 0, totalCount: 1)
        #expect(interactor.loadMorePages == [2, 2])
        #expect(interactor.loadMoreSortModes == [.replyTime, .postTime])
    }

    @Test func firstPageCompletionRendersPostsBeforeHidingSkeleton() {
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

        presenter.viewDidLoad()
        view.events.removeAll()
        presenter.didLoadPosts([post], category: .all)

        #expect(view.events.first == "render")
        #expect(view.events.contains("hideLoading"))
    }

    @Test func loadMoreCompletionRendersPostsBeforeHidingFooterLoading() {
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
        view.events.removeAll()
        presenter.didLoadMorePosts([second], page: 2, category: .all)

        #expect(view.events.first == "render")
        #expect(view.events.contains("hideLoadingMore"))
    }

    @Test func loginCloseReloadsCurrentCategoryFromFirstPage() {
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

        presenter.viewDidLoad()
        presenter.didLoadPosts([post], category: .all)
        presenter.didTapLogin()

        #expect(router.navigateToLoginCount == 1)
        #expect(interactor.loadPostsCategories == [.all])

        router.onLoginClose?()

        #expect(view.lastRenderedPostIDs.isEmpty)
        #expect(interactor.loadPostsCategories == [.all, .all])
        #expect(interactor.loadPostsSortModes == [.replyTime, .replyTime])
    }

    @Test func tappingAccountProfileRoutesToUserProfile() throws {
        let interactor = SpyPostListInteractor()
        let router = SpyPostListRouter()
        let presenter = PostListPresenter(interactor: interactor, router: router)
        let profileURL = try #require(URL(string: "https://www.nodeseek.com/space/31037"))

        presenter.didTapAccountProfile(profileURL: profileURL)

        #expect(router.userProfileURL == profileURL)
    }
}

private func makePost(id: String, title: String) -> PostSummary {
    PostSummary(
        id: id,
        title: title,
        url: URL(string: "https://www.nodeseek.com/post-\(id)")!,
        authorName: "mist",
        nodeName: "开发",
        replyCount: 1,
        lastActivityText: "刚刚"
    )
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
    var lastRenderedVisitedFlags: [Bool] = []
    var updatedVisitedRows: [Int] = []
    var updatedVisitedFlags: [Bool] = []
    var lastErrorMessage: String?
    var renderedCategories: [PostListCategory] = []
    var selectedCategory: PostListCategory = .all
    var renderedSortMode: PostListSortMode?
    var events: [String] = []
    var firstPageErrorMessages: [String] = []

    func showLoading() {
        showLoadingCount += 1
        events.append("showLoading")
    }

    func hideLoading() {
        hideLoadingCount += 1
        events.append("hideLoading")
    }

    func showRefreshing() {
        showRefreshingCount += 1
        events.append("showRefreshing")
    }

    func hideRefreshing() {
        hideRefreshingCount += 1
        events.append("hideRefreshing")
    }

    func showLoadingMore() {
        showLoadingMoreCount += 1
        events.append("showLoadingMore")
    }

    func hideLoadingMore() {
        hideLoadingMoreCount += 1
        events.append("hideLoadingMore")
    }

    func showError(message: String) {
        lastErrorMessage = message
    }

    func showFirstPageError(message: String) {
        firstPageErrorMessages.append(message)
        events.append("showFirstPageError")
    }

    func hideFirstPageError() {
        events.append("hideFirstPageError")
    }

    func showDetailTestInput() {
        events.append("showDetailTestInput")
    }

    func renderCategories(_ categories: [PostListCategory], selected: PostListCategory) {
        renderedCategories = categories
        selectedCategory = selected
        events.append("renderCategories")
    }

    func renderSortMode(_ sortMode: PostListSortMode) {
        renderedSortMode = sortMode
        events.append("renderSortMode")
    }

    func render(items: [PostListItem]) {
        renderCallCount += 1
        lastRenderedPostsCount = items.count
        lastRenderedPostIDs = items.map(\.post.id)
        lastRenderedVisitedFlags = items.map(\.isVisited)
        events.append("render")
    }

    func renderVisitedState(at index: Int, isVisited: Bool) {
        updatedVisitedRows.append(index)
        updatedVisitedFlags.append(isVisited)
        events.append("renderVisitedState")
    }
}

@MainActor
private final class FakeVisitedPostStore: VisitedPostStoreProtocol {
    var visitedIDs: Set<String> = []
    var markedPosts: [PostSummary] = []
    var records: [VisitedPostRecord] = []
    var recentRecordLimits: [Int] = []
    var clearAllCount = 0

    func isVisited(postID: String) -> Bool {
        visitedIDs.contains(postID)
    }

    func markVisited(post: PostSummary, visitedAt: Date) {
        visitedIDs.insert(post.id)
        markedPosts.append(post)
    }

    func recentRecords(limit: Int) -> [VisitedPostRecord] {
        recentRecordLimits.append(limit)
        return Array(records.prefix(limit))
    }

    func recentRecords(offset: Int, limit: Int) -> [VisitedPostRecord] {
        recentRecordLimits.append(limit)
        guard offset < records.count else { return [] }
        return Array(records.dropFirst(max(0, offset)).prefix(max(0, limit)))
    }

    func clearAll() {
        clearAllCount += 1
        records.removeAll()
        visitedIDs.removeAll()
    }
}

@MainActor
private final class SpyPostListInteractor: PostListInteractorInput {
    var loadPostsCallCount = 0
    var loadPostsCategories: [PostListCategory] = []
    var loadPostsSortModes: [PostListSortMode] = []
    var loadMorePages: [Int] = []
    var loadMoreCategories: [PostListCategory] = []
    var loadMoreSortModes: [PostListSortMode] = []

    func loadPosts(category: PostListCategory, sortMode: PostListSortMode) {
        loadPostsCallCount += 1
        loadPostsCategories.append(category)
        loadPostsSortModes.append(sortMode)
    }

    func loadMorePosts(page: Int, category: PostListCategory, sortMode: PostListSortMode) {
        loadMorePages.append(page)
        loadMoreCategories.append(category)
        loadMoreSortModes.append(sortMode)
    }
}

@MainActor
private final class SpyPostListRouter: PostListRouterProtocol {
    var selectedPost: PostSummary?
    var selectedPage: Int?
    var recentVisitedStore: VisitedPostStoreProtocol?
    var userProfileURL: URL?
    var notificationURL: URL?
    var navigateToLoginCount = 0
    var navigateToNewDiscussionCount = 0
    var navigateToSearchCount = 0
    var navigateToSettingsCount = 0
    var navigateToLogFileCount = 0
    var onLoginClose: (@MainActor () -> Void)?
    var onSettingsLogout: (@MainActor () -> Void)?
    var onSettingsLogFile: (@MainActor () -> Void)?
    var onSettingsDetailTest: (@MainActor () -> Void)?

    func navigateToPostDetail(post: PostSummary) {
        selectedPost = post
    }

    func navigateToPostDetail(post: PostSummary, page: Int) {
        selectedPost = post
        selectedPage = page
    }

    func navigateToLogin(onClose: @escaping @MainActor () -> Void) {
        navigateToLoginCount += 1
        onLoginClose = onClose
    }

    func navigateToRecentVisitedPosts(visitedStore: VisitedPostStoreProtocol) {
        recentVisitedStore = visitedStore
    }

    func navigateToNewDiscussion() {
        navigateToNewDiscussionCount += 1
    }

    func navigateToNotification(notificationURL: URL) {
        self.notificationURL = notificationURL
    }

    func navigateToSearch() {
        navigateToSearchCount += 1
    }

    func navigateToSettings(
        onLogout: @escaping @MainActor () -> Void,
        onLogFile: @escaping @MainActor () -> Void,
        onDetailTest: (@MainActor () -> Void)?
    ) {
        navigateToSettingsCount += 1
        onSettingsLogout = onLogout
        onSettingsLogFile = onLogFile
        onSettingsDetailTest = onDetailTest
    }

    func navigateToUserProfile(profileURL: URL) {
        userProfileURL = profileURL
    }

    func navigateToLogFile() {
        navigateToLogFileCount += 1
    }

}
