//
//  PostListPresenterTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/4/27.
//

import Foundation
import Testing
import UIKit
@testable import nodeseek

@MainActor
struct PostListPresenterTests {
    @Test func viewDidLoadRendersCategoriesAndDefaultSortMode() {
        let view = SpyPostListView()
        let presenter = makePresenter(view: view)

        presenter.viewDidLoad()

        #expect(view.renderedCategories.last == .award)
        #expect(view.selectedCategory == .all)
        #expect(view.renderedSortMode == .replyTime)
    }

    @Test func reselectingCurrentCategoryReloadsSelectedHost() {
        let view = SpyPostListView()
        let presenter = makePresenter(view: view)
        presenter.viewDidLoad()
        view.events.removeAll()

        presenter.didReselectCategory(.all)

        #expect(view.events == ["reloadSelectedCategory"])
    }

    @Test func settingsLogoutReloadsSelectedHost() {
        let view = SpyPostListView()
        let router = SpyPostListRouter()
        let presenter = makePresenter(view: view, router: router)

        presenter.didTapSettings()
        router.onSettingsLogout?()

        #expect(router.navigateToSettingsCount == 1)
        #expect(view.events == ["reloadSelectedCategory"])
    }

    @Test func loginCloseReloadsSelectedHost() {
        let view = SpyPostListView()
        let router = SpyPostListRouter()
        let presenter = makePresenter(view: view, router: router)

        presenter.didTapLogin()
        router.onLoginClose?()

        #expect(router.navigateToLoginCount == 1)
        #expect(view.events == ["reloadSelectedCategory"])
    }

    @Test func selectingPostNavigatesToDetail() {
        let router = SpyPostListRouter()
        let presenter = makePresenter(router: router)
        let post = makePost(id: "1", title: "标题")

        presenter.didSelectPost(post)

        #expect(router.selectedPost?.id == "1")
    }

    @Test func selectingPostUsesPageAndAnchorFromPostURL() {
        let router = SpyPostListRouter()
        let presenter = makePresenter(router: router)
        let post = PostSummary(
            id: "717963",
            title: "标题",
            url: URL(string: "https://www.nodeseek.com/post-717963-6#52")!,
            authorName: "mist",
            nodeName: "开发",
            replyCount: 52,
            lastActivityText: "刚刚"
        )

        presenter.didSelectPost(post)

        #expect(router.selectedPost?.id == "717963")
        #expect(router.selectedPage == 6)
        #expect(router.selectedAnchorID == "52")
    }

    @Test func tappingRecentVisitedRoutesVisitedStore() {
        let router = SpyPostListRouter()
        let visitedStore = FakeVisitedPostStore()
        let presenter = makePresenter(router: router, visitedStore: visitedStore)

        presenter.didTapRecentVisited()

        #expect(router.recentVisitedStore === visitedStore)
    }

    @Test func tappingSearchRoutesToSearchPage() {
        let router = SpyPostListRouter()
        let presenter = makePresenter(router: router)

        presenter.didTapSearch()

        #expect(router.navigateToSearchCount == 1)
    }

    @Test func tappingNotificationRoutesToNotificationPage() throws {
        let router = SpyPostListRouter()
        let presenter = makePresenter(router: router)
        let url = try #require(URL(string: "https://www.nodeseek.com/notification"))

        presenter.didTapNotification(url: url)

        #expect(router.notificationURL == url)
    }

    @Test func tappingCheckInRoutesToBoardPage() {
        let router = SpyPostListRouter()
        let presenter = makePresenter(router: router)

        presenter.didTapCheckIn()

        #expect(router.checkInURL == URL(string: "https://www.nodeseek.com/board"))
    }

    @Test func tappingSettingsRoutesToSettingsPage() {
        let router = SpyPostListRouter()
        let presenter = makePresenter(router: router)

        presenter.didTapSettings()

        #expect(router.navigateToSettingsCount == 1)
    }

    @Test func settingsDebugCallbacksReuseExistingLogAndDetailActions() {
        let view = SpyPostListView()
        let router = SpyPostListRouter()
        let presenter = makePresenter(view: view, router: router)

        presenter.didTapSettings()
        router.onSettingsLogFile?()
        router.onSettingsDetailTest?()

        #expect(router.navigateToLogFileCount == 1)
        #expect(view.events.contains("openDetailTestURLFromPasteboard"))
    }

    @Test func tappingNewDiscussionRoutesToNewDiscussionWebView() {
        let router = SpyPostListRouter()
        let presenter = makePresenter(router: router)

        presenter.didTapNewDiscussion()

        #expect(router.navigateToNewDiscussionCount == 1)
    }

    @Test func tappingLogFileRoutesToLogFileViewer() {
        let router = SpyPostListRouter()
        let presenter = makePresenter(router: router)

        presenter.didTapLogFile()

        #expect(router.navigateToLogFileCount == 1)
    }

    @Test func submittingDetailTestURLNavigatesToParsedPostPage() {
        let view = SpyPostListView()
        let router = SpyPostListRouter()
        let presenter = makePresenter(view: view, router: router)

        presenter.didSubmitDetailTestURL("https://www.nodeseek.com/post-705039-2")

        #expect(router.selectedPost?.id == "705039")
        #expect(router.selectedPost?.url.absoluteString == "https://www.nodeseek.com/post-705039-2")
        #expect(router.selectedPage == 2)
        #expect(view.lastErrorMessage == nil)
    }

    @Test func submittingDetailTestURLPreservesAnchor() {
        let router = SpyPostListRouter()
        let presenter = makePresenter(router: router)

        presenter.didSubmitDetailTestURL("https://www.nodeseek.com/post-717963-6#52")

        #expect(router.selectedPost?.id == "717963")
        #expect(router.selectedPage == 6)
        #expect(router.selectedAnchorID == "52")
    }

    @Test func submittingInvalidDetailTestURLShowsError() {
        let view = SpyPostListView()
        let router = SpyPostListRouter()
        let presenter = makePresenter(view: view, router: router)

        presenter.didSubmitDetailTestURL("https://example.com/post-705039-1")

        #expect(router.selectedPost == nil)
        #expect(view.lastErrorMessage == "剪贴板里没有可打开的 NodeSeek 帖子详情链接，例如 https://www.nodeseek.com/post-705039-1")
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

    @Test func tappingAccountProfileRoutesToUserProfile() throws {
        let router = SpyPostListRouter()
        let presenter = makePresenter(router: router)
        let profileURL = try #require(URL(string: "https://www.nodeseek.com/space/31037"))

        presenter.didTapAccountProfile(profileURL: profileURL)

        #expect(router.userProfileURL == profileURL)
    }
}

@MainActor
private func makePresenter(
    view: SpyPostListView? = nil,
    router: SpyPostListRouter? = nil,
    visitedStore: VisitedPostStoreProtocol = EmptyVisitedPostStore()
) -> PostListPresenter {
    let router = router ?? SpyPostListRouter()
    let presenter = PostListPresenter(
        router: router,
        visitedStore: visitedStore
    )
    if let view {
        presenter.setView(view)
    }
    return presenter
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
    var lastErrorMessage: String?
    var renderedCategories: [PostListCategory] = []
    var selectedCategory: PostListCategory = .all
    var renderedSortMode: PostListSortMode?
    var events: [String] = []

    func showError(message: String) {
        lastErrorMessage = message
    }

    func openDetailTestURLFromPasteboard() {
        events.append("openDetailTestURLFromPasteboard")
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

    func reloadSelectedCategory() {
        events.append("reloadSelectedCategory")
    }
}

@MainActor
private final class FakeVisitedPostStore: VisitedPostStoreProtocol {
    func isVisited(postID: String) -> Bool {
        false
    }

    func markVisited(post: PostSummary, visitedAt: Date) {
    }

    func recentRecords(limit: Int) -> [VisitedPostRecord] {
        []
    }

    func recentRecords(offset: Int, limit: Int) -> [VisitedPostRecord] {
        []
    }

    func clearAll() {
    }
}

@MainActor
private final class SpyPostListRouter: PostListRouterProtocol {
    var selectedPost: PostSummary?
    var selectedPage: Int?
    var selectedAnchorID: String?
    var recentVisitedStore: VisitedPostStoreProtocol?
    var userProfileURL: URL?
    var notificationURL: URL?
    var checkInURL: URL?
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

    func navigateToPostDetail(post: PostSummary, page: Int, initialAnchorID: String?) {
        selectedPost = post
        selectedPage = page
        selectedAnchorID = initialAnchorID
    }

    func navigateToLogin(onClose: @escaping @MainActor () -> Void) {
        navigateToLoginCount += 1
        onLoginClose = onClose
    }

    func navigateToUserProfile(profileURL: URL) {
        userProfileURL = profileURL
    }

    func navigateToNewDiscussion() {
        navigateToNewDiscussionCount += 1
    }

    func navigateToCheckIn(boardURL: URL) {
        checkInURL = boardURL
    }

    func navigateToNotification(notificationURL: URL) {
        self.notificationURL = notificationURL
    }

    func navigateToRecentVisitedPosts(visitedStore: VisitedPostStoreProtocol) {
        recentVisitedStore = visitedStore
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

    func navigateToLogFile() {
        navigateToLogFileCount += 1
    }
}
