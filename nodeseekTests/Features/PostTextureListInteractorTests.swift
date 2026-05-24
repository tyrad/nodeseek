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

        interactor.loadPosts(category: .all, sortMode: .replyTime)
        await waitForInteractorCallbacks()

        let requestedURLs = await htmlClient.requestedURLs()
        let state = await sessionStore.currentState()

        #expect(requestedURLs.count == 1)
        #expect(presenter.loadedPosts == nil)
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
            visitedStore: EmptyVisitedPostStore()
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

        presenter.didLoadPosts([post], category: .all, sortMode: .replyTime)

        #expect(delegate.loadedFirstPageCategories == [.all])
    }
}

@MainActor
private final class SpyPostTextureListHostInteractorOutput: PostTextureListHostInteractorOutput {
    var loadedPosts: [PostSummary]?
    var errorMessage: String?

    func didLoadPosts(_ posts: [PostSummary], category: PostListCategoryItem, sortMode: PostListSortMode) {
        loadedPosts = posts
    }

    func didLoadMorePosts(_ posts: [PostSummary], page: Int, category: PostListCategoryItem, sortMode: PostListSortMode) {
    }

    func didFailLoadPosts(error: String, category: PostListCategoryItem, sortMode: PostListSortMode) {
        errorMessage = error
    }

    func didFailLoadMorePosts(error: String, page: Int, category: PostListCategoryItem, sortMode: PostListSortMode) {
        errorMessage = error
    }
}

@MainActor
private final class SpyPostTextureListHostInteractor: PostTextureListHostInteractorInput {
    weak var presenter: PostTextureListHostInteractorOutput?

    func loadPosts(category: PostListCategoryItem, sortMode: PostListSortMode) {}

    func loadMorePosts(page: Int, category: PostListCategoryItem, sortMode: PostListSortMode) {}
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
    func setItems(_ items: [PostListItem]) {}
    func showLoadingSkeleton() {}
    func hideLoadingSkeleton() {}
    func showFirstPageError(message: String) {}
    func hideFirstPageError() {}
    func hideRefreshing() {}
    func showLoadingMore() {}
    func hideLoadingMore() {}
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
