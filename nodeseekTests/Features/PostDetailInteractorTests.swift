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

    @Test func submitReplyUsesCommentSubmitterAndReportsSuccess() async throws {
        let automation = SpyCommentSubmissionAutomation(response: CommentAutomationResponse(
            ok: true,
            statusCode: 200,
            message: "已发布",
            reason: "submitted"
        ))
        let presenter = SpyPostDetailInteractorOutput()
        let post = Self.makePost()
        let interactor = PostDetailInteractor(
            post: post,
            service: Self.makeUnusedService(),
            commentSubmitter: NodeSeekCommentSubmitter(automation: automation),
            sessionStore: NodeSeekSessionStore()
        )
        interactor.presenter = presenter

        interactor.submitReply(content: "  测试评论  ")
        await waitForInteractorCallbacks()

        #expect(automation.submittedPostID == 703863)
        #expect(automation.submittedContent == "测试评论")
        #expect(automation.submittedReferer == post.url)
        #expect(presenter.didSubmitReplyCount == 1)
        #expect(presenter.submitReplyResponse == PostDetailSubmitReplyResponse(message: "已发布"))
        #expect(presenter.submitReplyErrorMessage == nil)
    }

    @Test func submitReplyReportsMissingPost() async throws {
        let presenter = SpyPostDetailInteractorOutput()
        let interactor = PostDetailInteractor(
            post: nil,
            service: Self.makeUnusedService(),
            sessionStore: NodeSeekSessionStore()
        )
        interactor.presenter = presenter

        interactor.submitReply(content: "测试评论")

        #expect(presenter.didSubmitReplyCount == 0)
        #expect(presenter.submitReplyErrorMessage == "缺少帖子信息，无法发表评论。")
    }

    @Test func submitReplyReportsSubmitterFailureMessage() async throws {
        let automation = SpyCommentSubmissionAutomation(response: CommentAutomationResponse(
            ok: false,
            statusCode: 400,
            message: "评论内容太短",
            reason: "server_error"
        ))
        let presenter = SpyPostDetailInteractorOutput()
        let interactor = PostDetailInteractor(
            post: Self.makePost(),
            service: Self.makeUnusedService(),
            commentSubmitter: NodeSeekCommentSubmitter(automation: automation),
            sessionStore: NodeSeekSessionStore()
        )
        interactor.presenter = presenter

        interactor.submitReply(content: "短")
        await waitForInteractorCallbacks()

        #expect(presenter.didSubmitReplyCount == 0)
        #expect(presenter.submitReplyErrorMessage == "评论内容太短")
    }

    @Test func addFavoriteUsesCollectionSubmitterAndReportsSuccess() async throws {
        let collectionSubmitter = SpyPostCollectionSubmitting(response: PostCollectionResponse(message: "已收藏"))
        let presenter = SpyPostDetailInteractorOutput()
        let post = Self.makePost()
        let interactor = PostDetailInteractor(
            post: post,
            service: Self.makeUnusedService(),
            collectionSubmitter: collectionSubmitter,
            sessionStore: NodeSeekSessionStore()
        )
        interactor.presenter = presenter

        interactor.addFavorite()
        await waitForInteractorCallbacks()

        #expect(collectionSubmitter.submittedPostID == post.id)
        #expect(collectionSubmitter.submittedReferer == post.url)
        #expect(presenter.addFavoriteResponse == PostCollectionResponse(message: "已收藏"))
        #expect(presenter.addFavoriteErrorMessage == nil)
    }

    @Test func addFavoriteReportsMissingPost() {
        let presenter = SpyPostDetailInteractorOutput()
        let interactor = PostDetailInteractor(
            post: nil,
            service: Self.makeUnusedService(),
            sessionStore: NodeSeekSessionStore()
        )
        interactor.presenter = presenter

        interactor.addFavorite()

        #expect(presenter.addFavoriteResponse == nil)
        #expect(presenter.addFavoriteErrorMessage == "缺少帖子信息，无法收藏。")
    }

    private static func makePost() -> PostSummary {
        PostSummary(
            id: "703863",
            title: "标题",
            url: URL(string: "https://www.nodeseek.com/post-703863-1")!,
            authorName: "mist",
            nodeName: "日常",
            replyCount: 0,
            lastActivityText: "刚刚"
        )
    }

    private static func makeUnusedService() -> NodeSeekService {
        let url = URL(string: "https://www.nodeseek.com/")!
        return NodeSeekService(
            baseURL: url,
            htmlClient: URLCapturingHTMLClient(response: HTMLResponse(
                statusCode: 200,
                headers: [:],
                finalURL: url,
                html: ""
            )),
            parser: KannaNodeSeekParser(baseURL: url)
        )
    }
}

@MainActor
private final class SpyPostDetailInteractorOutput: PostDetailInteractorOutput {
    var loadedResponse: PostDetailResponse?
    var loginRequiredMessage: String?
    var errorMessage: String?
    var didSubmitReplyCount = 0
    var submitReplyResponse: PostDetailSubmitReplyResponse?
    var submitReplyErrorMessage: String?
    var addFavoriteResponse: PostCollectionResponse?
    var addFavoriteErrorMessage: String?

    func didLoadPostDetail(_ response: PostDetailResponse) {
        loadedResponse = response
    }

    func didRequireLogin(message: String) {
        loginRequiredMessage = message
    }

    func didFailLoadPostDetail(error: String) {
        errorMessage = error
    }

    func didCancelLoadPostDetail() {
        errorMessage = "cancelled"
    }

    func didSubmitReply(_ response: PostDetailSubmitReplyResponse) {
        didSubmitReplyCount += 1
        submitReplyResponse = response
    }

    func didFailSubmitReply(error: String) {
        submitReplyErrorMessage = error
    }

    func didAddFavorite(_ response: PostCollectionResponse) {
        addFavoriteResponse = response
    }

    func didFailAddFavorite(error: String) {
        addFavoriteErrorMessage = error
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

    func post(_ url: URL, formFields: [String: String]) async throws -> HTMLResponse {
        urls.append(url)
        return response
    }

    func requestedURLs() -> [URL] {
        urls
    }
}

@MainActor
private final class SpyCommentSubmissionAutomation: CommentSubmissionAutomating {
    private let response: CommentAutomationResponse
    private(set) var submittedPostID: Int?
    private(set) var submittedContent: String?
    private(set) var submittedReferer: URL?

    init(response: CommentAutomationResponse) {
        self.response = response
    }

    func submitComment(postID: Int, content: String, referer: URL) async throws -> CommentAutomationResponse {
        submittedPostID = postID
        submittedContent = content
        submittedReferer = referer
        return response
    }
}

@MainActor
private final class SpyPostCollectionSubmitting: PostCollectionSubmitting {
    private let response: PostCollectionResponse
    private(set) var submittedPostID: String?
    private(set) var submittedReferer: URL?

    init(response: PostCollectionResponse) {
        self.response = response
    }

    func addFavorite(postID: String, referer: URL) async throws -> PostCollectionResponse {
        submittedPostID = postID
        submittedReferer = referer
        return response
    }
}
