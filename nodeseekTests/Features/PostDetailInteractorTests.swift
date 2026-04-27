//
//  PostDetailInteractorTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/4/27.
//

import Foundation
import Testing
@testable import nodeseek

@MainActor
struct PostDetailInteractorTests {
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
        let presenter = SpyPostDetailInteractorOutput()
        let post = PostSummary(
            id: "703863",
            title: "标题",
            url: URL(string: "https://www.nodeseek.com/post-703863-1")!,
            authorName: "mist",
            nodeName: "日常",
            replyCount: 0,
            lastActivityText: "刚刚"
        )
        let interactor = PostDetailInteractor(
            post: post,
            service: service,
            sessionStore: sessionStore
        )
        interactor.presenter = presenter

        interactor.loadPostDetail()
        await waitForInteractorCallbacks()

        let requestedURLs = await htmlClient.requestedURLs()
        let state = await sessionStore.currentState()

        #expect(requestedURLs.count == 1)
        #expect(presenter.loadedResponse == nil)
        #expect(presenter.errorMessage == "站点当前需要 Cloudflare 验证，请稍后重试。")
        guard case .challengeRequired(.cloudflare, _) = state else {
            Issue.record("详情命中 challenge 后应写入统一 session 状态")
            return
        }
    }

    @Test func reportsLoginRequiredInlineInsteadOfFailingDetailLoad() async throws {
        let html = try FixtureLoader.html(named: "post-login-required")
        let url = URL(string: "https://www.nodeseek.com/")!
        let htmlClient = URLCapturingHTMLClient(response: HTMLResponse(
            statusCode: 404,
            headers: [:],
            finalURL: URL(string: "https://www.nodeseek.com/post-704286-1")!,
            html: html
        ))
        let service = NodeSeekService(
            baseURL: url,
            htmlClient: htmlClient,
            parser: KannaNodeSeekParser(baseURL: url)
        )
        let sessionStore = NodeSeekSessionStore()
        let presenter = SpyPostDetailInteractorOutput()
        let post = PostSummary(
            id: "704286",
            title: "受限帖子",
            url: URL(string: "https://www.nodeseek.com/post-704286-1")!,
            authorName: "mist",
            nodeName: "日常",
            replyCount: 0,
            lastActivityText: "刚刚"
        )
        let interactor = PostDetailInteractor(
            post: post,
            service: service,
            sessionStore: sessionStore
        )
        interactor.presenter = presenter

        interactor.loadPostDetail()
        await waitForInteractorCallbacks()

        #expect(presenter.loadedResponse == nil)
        #expect(presenter.errorMessage == nil)
        #expect(presenter.loginRequiredMessage == "本帖需要注册用户才能查看😭")
    }
}

@MainActor
private final class SpyPostDetailInteractorOutput: PostDetailInteractorOutput {
    var loadedResponse: PostDetailResponse?
    var loginRequiredMessage: String?
    var errorMessage: String?

    func didLoadPostDetail(_ response: PostDetailResponse) {
        loadedResponse = response
    }

    func didRequireLogin(message: String) {
        loginRequiredMessage = message
    }

    func didFailLoadPostDetail(error: String) {
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
