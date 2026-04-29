//
//  PostListInteractorTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/4/27.
//

import Foundation
import Testing
@testable import nodeseek

@MainActor
struct PostListInteractorTests {
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
        let presenter = SpyPostListInteractorOutput()
        let interactor = PostListInteractor(service: service, sessionStore: sessionStore)
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
}

@MainActor
private final class SpyPostListInteractorOutput: PostListInteractorOutput {
    var loadedPosts: [PostSummary]?
    var errorMessage: String?

    func didLoadAccount(_ account: AccountResponse) {
    }

    func didFailLoadAccount(error: String) {
        errorMessage = error
    }

    func didLoadPosts(_ posts: [PostSummary], category: PostListCategory, sortMode: PostListSortMode) {
        loadedPosts = posts
    }

    func didLoadMorePosts(_ posts: [PostSummary], page: Int, category: PostListCategory, sortMode: PostListSortMode) {
    }

    func didFailLoadPosts(error: String, category: PostListCategory, sortMode: PostListSortMode) {
        errorMessage = error
    }

    func didFailLoadMorePosts(error: String, page: Int, category: PostListCategory, sortMode: PostListSortMode) {
        errorMessage = error
    }
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

    func post(_ url: URL, formFields: [String : String]) async throws -> HTMLResponse {
        urls.append(url)
        return response
    }

    func requestedURLs() -> [URL] {
        urls
    }
}
