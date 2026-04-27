//
//  NodeSeekServiceTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/4/27.
//

import Foundation
import Testing
@testable import nodeseek

@MainActor
struct NodeSeekServiceTests {
    @Test func returnsChallengeWhenPostListResponseIsCloudflare() async throws {
        let html = try FixtureLoader.html(named: "cloudflare-challenge")
        let url = URL(string: "https://www.nodeseek.com/")!
        let service = NodeSeekService(
            baseURL: url,
            htmlClient: StaticHTMLClient(response: HTMLResponse(
                statusCode: 403,
                headers: [:],
                finalURL: url,
                html: html
            )),
            parser: KannaNodeSeekParser(baseURL: url)
        )

        let result = try await service.loadPostList()

        switch result {
        case .challenge(.cloudflare(url)):
            #expect(url.absoluteString == "https://www.nodeseek.com/")
        default:
            Issue.record("应返回 Cloudflare challenge，而不是普通列表")
        }
    }

    @Test func parsesPostListWhenResponseIsNormalHTML() async throws {
        let html = try FixtureLoader.html(named: "post-list-basic")
        let url = URL(string: "https://www.nodeseek.com/")!
        let service = NodeSeekService(
            baseURL: url,
            htmlClient: StaticHTMLClient(response: HTMLResponse(
                statusCode: 200,
                headers: [:],
                finalURL: url,
                html: html
            )),
            parser: KannaNodeSeekParser(baseURL: url)
        )

        let result = try await service.loadPostList()

        switch result {
        case .value(let posts):
            #expect(posts.count == 1)
            #expect(posts.first?.id == "123")
        default:
            Issue.record("应返回解析后的帖子列表")
        }
    }

    @Test func parsesPostListWhenServerHeaderIsCloudflareButPageIsNormal() async throws {
        let html = try FixtureLoader.html(named: "post-list-basic")
        let url = URL(string: "https://www.nodeseek.com/")!
        let service = NodeSeekService(
            baseURL: url,
            htmlClient: StaticHTMLClient(response: HTMLResponse(
                statusCode: 200,
                headers: ["Server": "cloudflare"],
                finalURL: url,
                html: html
            )),
            parser: KannaNodeSeekParser(baseURL: url)
        )

        let result = try await service.loadPostList()

        switch result {
        case .value(let posts):
            #expect(posts.count == 1)
        default:
            Issue.record("仅有 Server=cloudflare 时不应判定为 challenge")
        }
    }

    @Test func loadsTargetPageURLWhenRequestingPagination() async throws {
        let html = try FixtureLoader.html(named: "post-list-basic")
        let url = URL(string: "https://www.nodeseek.com/")!
        let htmlClient = URLCapturingHTMLClient(response: HTMLResponse(
            statusCode: 200,
            headers: [:],
            finalURL: url,
            html: html
        ))
        let service = NodeSeekService(
            baseURL: url,
            htmlClient: htmlClient,
            parser: KannaNodeSeekParser(baseURL: url)
        )

        _ = try await service.loadPostList(page: 2)
        let requestedURLs = await htmlClient.requestedURLs()

        #expect(requestedURLs.count == 1)
        #expect(requestedURLs.first?.path == "/page-2")
    }

    @Test func loadsCategoryRootURLForFirstPage() async throws {
        let html = try FixtureLoader.html(named: "post-list-basic")
        let url = URL(string: "https://www.nodeseek.com/")!
        let htmlClient = URLCapturingHTMLClient(response: HTMLResponse(
            statusCode: 200,
            headers: [:],
            finalURL: url,
            html: html
        ))
        let service = NodeSeekService(
            baseURL: url,
            htmlClient: htmlClient,
            parser: KannaNodeSeekParser(baseURL: url)
        )

        _ = try await service.loadPostList(page: 1, category: .tech)
        let requestedURLs = await htmlClient.requestedURLs()

        #expect(requestedURLs.count == 1)
        #expect(requestedURLs.first?.path == "/categories/tech")
    }

    @Test func loadsCategoryPagedURLWhenRequestingPagination() async throws {
        let html = try FixtureLoader.html(named: "post-list-basic")
        let url = URL(string: "https://www.nodeseek.com/")!
        let htmlClient = URLCapturingHTMLClient(response: HTMLResponse(
            statusCode: 200,
            headers: [:],
            finalURL: url,
            html: html
        ))
        let service = NodeSeekService(
            baseURL: url,
            htmlClient: htmlClient,
            parser: KannaNodeSeekParser(baseURL: url)
        )

        _ = try await service.loadPostList(page: 3, category: .tech)
        let requestedURLs = await htmlClient.requestedURLs()

        #expect(requestedURLs.count == 1)
        #expect(requestedURLs.first?.path == "/categories/tech/page-3")
    }

    @Test func loadsPostDetailURLWithoutHTMLSuffix() async throws {
        let html = try FixtureLoader.html(named: "post-703863-1")
        let url = URL(string: "https://www.nodeseek.com/")!
        let htmlClient = URLCapturingHTMLClient(response: HTMLResponse(
            statusCode: 200,
            headers: [:],
            finalURL: URL(string: "https://www.nodeseek.com/post-703863-1")!,
            html: html
        ))
        let service = NodeSeekService(
            baseURL: url,
            htmlClient: htmlClient,
            parser: KannaNodeSeekParser(baseURL: url)
        )

        _ = try await service.loadPostDetail(postID: "703863", page: 1)
        let requestedURLs = await htmlClient.requestedURLs()

        #expect(requestedURLs.count == 1)
        #expect(requestedURLs.first?.path == "/post-703863-1")
        #expect(requestedURLs.first?.pathExtension.isEmpty == true)
    }

    @Test func returnsLoginRequiredWhenPostDetailIsRestrictedToRegisteredUsers() async throws {
        let html = try FixtureLoader.html(named: "post-login-required")
        let finalURL = URL(string: "https://www.nodeseek.com/post-704286-1")!
        let service = NodeSeekService(
            baseURL: URL(string: "https://www.nodeseek.com/")!,
            htmlClient: StaticHTMLClient(response: HTMLResponse(
                statusCode: 404,
                headers: [:],
                finalURL: finalURL,
                html: html
            ))
        )

        let result = try await service.loadPostDetail(postID: "704286", page: 1)

        switch result {
        case .challenge(.loginRequired(let url)):
            #expect(url == finalURL)
        default:
            Issue.record("注册用户可见的详情页应返回 loginRequired，而不是进入普通详情解析")
        }
    }
}

private struct StaticHTMLClient: HTMLClient {
    let response: HTMLResponse

    func get(_ url: URL) async throws -> HTMLResponse {
        response
    }

    func post(_ url: URL, formFields: [String: String]) async throws -> HTMLResponse {
        response
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
