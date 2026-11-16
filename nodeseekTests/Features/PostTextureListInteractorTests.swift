//
//  PostTextureListInteractorTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/4/27.
//

import Foundation
import Testing
@testable import nodeseek

@MainActor
struct PostTextureListInteractorTests {
    @Test func stopsAfterFirstChallengeAndUpdatesSharedSessionState() async throws {
        let html = try FixtureLoader.html(named: "cloudflare-challenge")
        let url = URL(string: "https://www.nodeseek.com/")!
        let htmlClient = URLCapturingHTMLClient(response: HTMLResponse(
            statusCode: 403,
            headers: [:],
            finalURL: url,
            html: html
        ))
        let service = NodeSeekService(
            baseURL: url,
            htmlClient: htmlClient,
            parser: KannaNodeSeekParser(baseURL: url)
        )
        let sessionStore = NodeSeekSessionStore()
        let presenter = SpyPostTextureListHostInteractorOutput()
        let interactor = PostTextureListInteractor(service: service, sessionStore: sessionStore)
        interactor.presenter = presenter

        interactor.loadPosts(category: .all, sortMode: .replyTime, generation: 42)
        await waitForInteractorCallbacks()

        let requestedURLs = await htmlClient.requestedURLs()
        let state = await sessionStore.currentState()

        #expect(requestedURLs.count == 1)
        #expect(presenter.loadedPosts == nil)
        #expect(presenter.lastGeneration == 42)
        #expect(presenter.errorMessage == "站点当前需要 Cloudflare 验证，请稍后重试。")
        guard case .challengeRequired(.cloudflare, _) = state else {
            Issue.record("列表命中 challenge 后应写入统一 session 状态")
            return
        }
    }

    @Test func successfulFirstPageLoadNotifiesHostDelegate() {
        let interactor = SpyPostTextureListHostInteractor()
        let view = SpyPostTextureListHostView()
        let delegate = SpyPostTextureListHostPresenterDelegate()
        let presenter = PostTextureListHostPresenter(
            category: .all,
            interactor: interactor,
            visitedStore: EmptyVisitedPostStore(),
            sortPreferenceStore: InMemoryPostListSortPreferenceStore()
        )
        presenter.setView(view)
        presenter.delegate = delegate
        let post = PostSummary(
            id: "1",
            title: "标题",
            url: URL(string: "https://www.nodeseek.com/post-1-1")!,
            authorName: "mist",
            nodeName: "Dev",
            replyCount: 0,
            lastActivityText: "刚刚"
        )

        presenter.didLoadPosts([post], category: .all, sortMode: .replyTime, generation: 0)

        #expect(delegate.loadedFirstPageCategories == [.all])
    }

    @Test func togglingSortWhileFirstPageLoadingStillRequestsNewSort() {
        let interactor = SpyPostTextureListHostInteractor()
        let presenter = makeHostPresenter(interactor: interactor)
        presenter.viewDidLoad()

        // 首页请求还没返回时连续切换两次排序，每次都要按新排序发出请求。
        _ = presenter.toggleSortMode()
        _ = presenter.toggleSortMode()

        #expect(interactor.loadedSortModes == [.replyTime, .postTime, .replyTime])
    }

    @Test func staleResponseAfterSortToggleDoesNotBlockNewSortResult() {
        let interactor = SpyPostTextureListHostInteractor()
        let view = SpyPostTextureListHostView()
        let presenter = makeHostPresenter(interactor: interactor, view: view)
        presenter.viewDidLoad()
        _ = presenter.toggleSortMode()

        presenter.didLoadPosts([makePost(id: "old")], category: .all, sortMode: .replyTime, generation: 0)
        presenter.didLoadPosts([makePost(id: "new")], category: .all, sortMode: .postTime, generation: 1)

        #expect(view.lastItems?.map(\.post.id) == ["new"])
    }

    @Test func toggleSortSavesGlobalPreference() {
        let store = InMemoryPostListSortPreferenceStore()
        let presenter = makeHostPresenter(store: store)
        presenter.viewDidLoad()

        #expect(presenter.toggleSortMode() == .postTime)
        #expect(store.sortMode == .postTime)
    }

    @Test func viewDidLoadUsesPreferenceChangedAfterCreation() {
        let interactor = SpyPostTextureListHostInteractor()
        let store = InMemoryPostListSortPreferenceStore()
        let presenter = makeHostPresenter(interactor: interactor, store: store)

        // 分类页面已创建但还没显示时，在其他分类改了排序。
        store.sortMode = .postTime
        presenter.viewDidLoad()

        #expect(interactor.loadedSortModes == [.postTime])
    }

    @Test func returningToCategoryWithDifferentSortReloadsFromFirstPage() {
        let interactor = SpyPostTextureListHostInteractor()
        let view = SpyPostTextureListHostView()
        let store = InMemoryPostListSortPreferenceStore()
        let presenter = makeHostPresenter(interactor: interactor, view: view, store: store)
        presenter.viewDidLoad()
        presenter.didLoadPosts([makePost(id: "1")], category: .all, sortMode: .replyTime, generation: 0)

        // 在其他分类切到发帖时间优先后回到这里。
        store.sortMode = .postTime
        let didSync = presenter.syncSortModeWithPreference()

        #expect(didSync)
        #expect(presenter.currentSortMode == .postTime)
        #expect(interactor.loadedSortModes == [.replyTime, .postTime])
        #expect(view.lastItems?.isEmpty == true)
    }

    @Test func returningToCategoryWithSameSortKeepsList() {
        let interactor = SpyPostTextureListHostInteractor()
        let view = SpyPostTextureListHostView()
        let presenter = makeHostPresenter(interactor: interactor, view: view)
        presenter.viewDidLoad()
        presenter.didLoadPosts([makePost(id: "1")], category: .all, sortMode: .replyTime, generation: 0)

        #expect(presenter.syncSortModeWithPreference() == false)
        #expect(interactor.loadedSortModes == [.replyTime])
        #expect(view.lastItems?.map(\.post.id) == ["1"])
    }

    @Test func switchingBackRejectsOldFirstPageAfterCurrentResult() {
        let interactor = SpyPostTextureListHostInteractor()
        let view = SpyPostTextureListHostView()
        let presenter = makeHostPresenter(interactor: interactor, view: view)
        presenter.viewDidLoad()
        let oldGeneration = interactor.loadedGenerations.last!
        _ = presenter.toggleSortMode()
        _ = presenter.toggleSortMode()
        let currentGeneration = interactor.loadedGenerations.last!
        #expect(currentGeneration != oldGeneration)

        presenter.didLoadPosts([makePost(id: "new")], category: .all, sortMode: .replyTime, generation: currentGeneration)
        presenter.didLoadPosts([makePost(id: "old")], category: .all, sortMode: .replyTime, generation: oldGeneration)
        #expect(view.lastItems?.map(\.post.id) == ["new"])
    }

    @Test(arguments: [false, true])
    func switchingBackRejectsOldPagination(empty: Bool) {
        let interactor = SpyPostTextureListHostInteractor()
        let view = SpyPostTextureListHostView()
        let presenter = makeHostPresenter(interactor: interactor, view: view)
        presenter.viewDidLoad()
        let oldGeneration = interactor.loadedGenerations.last!
        presenter.didLoadPosts([makePost(id: "old-1")], category: .all, sortMode: .replyTime, generation: oldGeneration)
        presenter.didApproachBottom(at: 0, totalCount: 1)
        presenter.didLoadMorePosts([makePost(id: "old-2")], page: 2, category: .all, sortMode: .replyTime, generation: oldGeneration)
        presenter.didApproachBottom(at: 1, totalCount: 2)
        #expect(interactor.loadedPages == [2, 3])

        _ = presenter.toggleSortMode()
        _ = presenter.toggleSortMode()
        let currentGeneration = interactor.loadedGenerations.last!
        presenter.didLoadPosts([makePost(id: "new-1")], category: .all, sortMode: .replyTime, generation: currentGeneration)
        presenter.didLoadMorePosts(empty ? [] : [makePost(id: "old-3")], page: 3, category: .all, sortMode: .replyTime, generation: oldGeneration)
        #expect(view.lastItems?.map(\.post.id) == ["new-1"])
        presenter.didApproachBottom(at: 0, totalCount: 1)
        #expect(interactor.loadedPages == [2, 3, 2])
        #expect(interactor.pageGenerations.last == currentGeneration)
    }

    @Test func switchingBackRejectsOldFailuresWithoutClearingLoadingState() {
        let interactor = SpyPostTextureListHostInteractor()
        let view = SpyPostTextureListHostView()
        let presenter = makeHostPresenter(interactor: interactor, view: view)
        presenter.viewDidLoad()
        let oldGeneration = interactor.loadedGenerations.last!
        _ = presenter.toggleSortMode()
        _ = presenter.toggleSortMode()
        let currentGeneration = interactor.loadedGenerations.last!
        let hiddenSkeletons = view.hiddenSkeletonCount
        presenter.didFailLoadPosts(error: "old failure", category: .all, sortMode: .replyTime, generation: oldGeneration)
        #expect(view.firstPageErrors.isEmpty)
        #expect(view.hiddenSkeletonCount == hiddenSkeletons)
        presenter.didRequestTabReselectRefresh()
        #expect(interactor.loadedGenerations.count == 3)

        presenter.didLoadPosts([makePost(id: "new")], category: .all, sortMode: .replyTime, generation: currentGeneration)
        presenter.didApproachBottom(at: 0, totalCount: 1)
        let hiddenMore = view.hiddenMoreCount
        presenter.didFailLoadMorePosts(error: "old page failure", page: 2, category: .all, sortMode: .replyTime, generation: oldGeneration)
        presenter.didApproachBottom(at: 0, totalCount: 1)
        #expect(interactor.loadedPages == [2])
        #expect(view.hiddenMoreCount == hiddenMore)
        presenter.didLoadMorePosts([makePost(id: "new-2")], page: 2, category: .all, sortMode: .replyTime, generation: currentGeneration)
        #expect(view.lastItems?.map(\.post.id) == ["new", "new-2"])
    }

    @Test func sortPreferenceStorePersistsAndFallsBackToReplyTime() throws {
        let suiteName = "PostListSortPreferenceStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PostListSortPreferenceStore(userDefaults: defaults, storageKey: "sort")
        #expect(store.sortMode == .replyTime)

        store.sortMode = .postTime
        #expect(PostListSortPreferenceStore(userDefaults: defaults, storageKey: "sort").sortMode == .postTime)

        defaults.set("unknown", forKey: "sort")
        #expect(store.sortMode == .replyTime)
    }
}

@MainActor
private func makeHostPresenter(
    interactor: SpyPostTextureListHostInteractor? = nil,
    view: SpyPostTextureListHostView? = nil,
    store: InMemoryPostListSortPreferenceStore? = nil
) -> PostTextureListHostPresenter {
    let presenter = PostTextureListHostPresenter(
        category: .all,
        interactor: interactor ?? SpyPostTextureListHostInteractor(),
        visitedStore: EmptyVisitedPostStore(),
        sortPreferenceStore: store ?? InMemoryPostListSortPreferenceStore()
    )
    presenter.setView(view ?? SpyPostTextureListHostView())
    return presenter
}

private func makePost(id: String) -> PostSummary {
    PostSummary(
        id: id,
        title: "标题",
        url: URL(string: "https://www.nodeseek.com/post-\(id)-1")!,
        authorName: "mist",
        nodeName: "Dev",
        replyCount: 0,
        lastActivityText: "刚刚"
    )
}

@MainActor
private final class SpyPostTextureListHostInteractorOutput: PostTextureListHostInteractorOutput {
    var loadedPosts: [PostSummary]?
    var errorMessage: String?
    var lastGeneration: Int?

    func didLoadPosts(_ posts: [PostSummary], category: PostListCategoryItem, sortMode: PostListSortMode, generation: Int) {
        lastGeneration = generation
        loadedPosts = posts
    }

    func didLoadMorePosts(_ posts: [PostSummary], page: Int, category: PostListCategoryItem, sortMode: PostListSortMode, generation: Int) {
    }

    func didFailLoadPosts(error: String, category: PostListCategoryItem, sortMode: PostListSortMode, generation: Int) {
        lastGeneration = generation
        errorMessage = error
    }

    func didFailLoadMorePosts(error: String, page: Int, category: PostListCategoryItem, sortMode: PostListSortMode, generation: Int) {
        lastGeneration = generation
        errorMessage = error
    }
}

@MainActor
private final class SpyPostTextureListHostInteractor: PostTextureListHostInteractorInput {
    weak var presenter: PostTextureListHostInteractorOutput?
    private(set) var loadedSortModes: [PostListSortMode] = []
    private(set) var loadedGenerations: [Int] = []
    private(set) var loadedPages: [Int] = []
    private(set) var pageGenerations: [Int] = []

    func loadPosts(category: PostListCategoryItem, sortMode: PostListSortMode, generation: Int) {
        loadedSortModes.append(sortMode)
        loadedGenerations.append(generation)
    }

    func loadMorePosts(page: Int, category: PostListCategoryItem, sortMode: PostListSortMode, generation: Int) {
        loadedPages.append(page)
        pageGenerations.append(generation)
    }
}

@MainActor
private final class SpyPostTextureListHostPresenterDelegate: PostTextureListHostPresenterDelegate {
    private(set) var loadedFirstPageCategories: [PostListCategoryItem] = []

    func postTextureListHostDidSelectPost(_ post: PostSummary, category: PostListCategoryItem) {}

    func postTextureListHostDidChangeSortMode(_ sortMode: PostListSortMode, category: PostListCategoryItem) {}

    func postTextureListHostDidLoadFirstPage(category: PostListCategoryItem) {
        loadedFirstPageCategories.append(category)
    }
}

@MainActor
private final class SpyPostTextureListHostView: PostTextureListHostViewProtocol {
    private(set) var lastItems: [PostListItem]?
    private(set) var hiddenSkeletonCount = 0
    private(set) var hiddenMoreCount = 0
    private(set) var firstPageErrors: [String] = []

    func setItems(_ items: [PostListItem]) {
        lastItems = items
    }
    func showLoadingSkeleton() {}
    func hideLoadingSkeleton() { hiddenSkeletonCount += 1 }
    func showFirstPageError(message: String) { firstPageErrors.append(message) }
    func hideFirstPageError() {}
    func showTabRefreshLoading() {}
    func hideTabRefreshLoading(failureMessage: String?) {}
    func hideRefreshing() {}
    func showLoadingMore() {}
    func hideLoadingMore() { hiddenMoreCount += 1 }
    func updateVisitedState(at index: Int, isVisited: Bool) {}
}

@MainActor
private func waitForInteractorCallbacks() async {
    for _ in 0..<50 {
        await Task.yield()
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
}

private actor URLCapturingHTMLClient: HTMLClient {
    private var urls: [URL] = []
    private let response: HTMLResponse

    init(response: HTMLResponse) {
        self.response = response
    }

    func get(_ url: URL) async throws -> HTMLResponse {
        urls.append(url)
        return response
    }

    func post(_ url: URL, formFields: [String: String]) async throws -> HTMLResponse {
        urls.append(url)
        return response
    }

    func requestedURLs() -> [URL] {
        urls
    }
}
