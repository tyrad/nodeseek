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
    @Test func loadAccountParsesCurrentUserFromHomePage() async throws {
        let html = """
        <div id="nsk-right-panel-container">
            <div class="user-card">
                <div class="user-head">
                    <a title="缭雾" href="/space/31037">
                        <img src="/avatar/31037.png" alt="缭雾" class="avatar-normal skeleton">
                    </a>
                    <div class="menu">
                        <a href="/space/31037" class="Username">缭雾</a>
                    </div>
                </div>
                <div class="user-stat">
                    <span>等级 Lv 1</span>
                    <span>鸡腿 306</span>
                </div>
            </div>
        </div>
        """
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

        let result = try await service.loadAccount()
        let requestedURLs = await htmlClient.requestedURLs()

        #expect(requestedURLs.count == 1)
        #expect(requestedURLs.first?.path == "/")
        switch result {
        case .value(let account):
            #expect(account.displayName == "缭雾")
            #expect(account.avatarURL?.path == "/avatar/31037.png")
            #expect(account.stats == ["等级 Lv 1", "鸡腿 306"])
        default:
            Issue.record("账号页正常 HTML 应解析为当前账号")
        }
    }

    @Test func loadAccountParsesCurrentUserFromTempScriptWhenRightPanelIsSkeleton() async throws {
        let accountJSON = """
        {
          "user": {
            "member_id": 31037,
            "member_name": "缭雾",
            "rank": 1,
            "coin": 330,
            "stardust": 2
          }
        }
        """
        let payload = Data(accountJSON.utf8).base64EncodedString()
        let html = """
        <div id="nsk-right-panel-container">
            <div id="usercard-me" class="skeleton" style="height: 146px; margin-bottom: 10px"></div>
        </div>
        <script id="temp-script" type="application/json">\(payload)</script>
        """
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

        let result = try await service.loadAccount()

        switch result {
        case .value(let account):
            #expect(account.displayName == "缭雾")
            #expect(account.avatarURL?.path == "/avatar/31037.png")
            #expect(account.profileURL?.path == "/space/31037")
            #expect(account.stats == ["等级 Lv 1", "鸡腿 330", "星辰 2"])
        default:
            Issue.record("skeleton 右栏 + temp-script 应解析为当前账号")
        }
    }

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

    @Test func loadPostListStoresAccountParsedFromSameHTML() async throws {
        let html = try FixtureLoader.html(named: "post-list-basic")
            .replacingOccurrences(of: "</body>", with: accountHTML(displayName: "缭雾") + "</body>")
        let url = URL(string: "https://www.nodeseek.com/")!
        let store = CurrentAccountStore(
            userDefaults: try #require(UserDefaults(suiteName: "NodeSeekServiceTests.\(UUID().uuidString)")),
            storageKey: "account"
        )
        let service = NodeSeekService(
            baseURL: url,
            htmlClient: StaticHTMLClient(response: HTMLResponse(
                statusCode: 200,
                headers: [:],
                finalURL: url,
                html: html
            )),
            parser: KannaNodeSeekParser(baseURL: url),
            currentAccountStore: store
        )

        _ = try await service.loadPostList()
        let snapshot = await store.snapshot()

        #expect(snapshot?.account.displayName == "缭雾")
        #expect(snapshot?.account.isLoggedIn == true)
        #expect(snapshot?.account.profileURL?.path == "/space/31037")
        #expect(snapshot?.account.notification?.url.absoluteString == "https://www.nodeseek.com/notification")
        #expect(snapshot?.account.notification?.iconColorCSS == "rgb(243, 17, 17)")
    }

    @Test func loadPostListDoesNotOverwriteCachedAccountWhenHTMLHasNoAccountSignal() async throws {
        let html = try FixtureLoader.html(named: "post-list-basic")
        let url = URL(string: "https://www.nodeseek.com/")!
        let store = CurrentAccountStore(
            userDefaults: try #require(UserDefaults(suiteName: "NodeSeekServiceTests.\(UUID().uuidString)")),
            storageKey: "account"
        )
        await store.save(AccountResponse(displayName: "已缓存", isLoggedIn: true))
        let service = NodeSeekService(
            baseURL: url,
            htmlClient: StaticHTMLClient(response: HTMLResponse(
                statusCode: 200,
                headers: [:],
                finalURL: url,
                html: html
            )),
            parser: KannaNodeSeekParser(baseURL: url),
            currentAccountStore: store
        )

        _ = try await service.loadPostList()
        let snapshot = await store.snapshot()

        #expect(snapshot?.account.displayName == "已缓存")
        #expect(snapshot?.account.isLoggedIn == true)
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

    @Test func loadsSortQueryWhenRequestingPostList() async throws {
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

        _ = try await service.loadPostList(page: 1, category: .all, sortMode: .postTime)
        let requestedURLs = await htmlClient.requestedURLs()

        #expect(requestedURLs.count == 1)
        #expect(requestedURLs.first?.query == "sortBy=postTime")
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

    @Test func loadsSupplementalCategoryURLsUsingSidebarCategoryCodes() async throws {
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

        _ = try await service.loadPostList(page: 2, category: .photoShare)
        _ = try await service.loadPostList(page: 1, category: .meaningless)
        let requestedURLs = await htmlClient.requestedURLs()

        #expect(requestedURLs.map(\.path) == [
            "/categories/photo-share/page-2",
            "/categories/meaningless"
        ])
    }

    @Test func loadsAwardURLWhenRequestingRecommendedReadingFirstPage() async throws {
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

        _ = try await service.loadPostList(page: 1, category: .award)
        let requestedURLs = await htmlClient.requestedURLs()

        #expect(requestedURLs.count == 1)
        #expect(requestedURLs.first?.path == "/award/page-1")
    }

    @Test func loadsAwardPagedURLWhenRequestingRecommendedReadingPagination() async throws {
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

        _ = try await service.loadPostList(page: 3, category: .award)
        let requestedURLs = await htmlClient.requestedURLs()

        #expect(requestedURLs.count == 1)
        #expect(requestedURLs.first?.path == "/award/page-3")
    }

    @Test func loadSearchResultsUsesSearchURLWithEncodedKeyword() async throws {
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

        _ = try await service.loadSearchResults(query: "美西", page: 1, category: .all)
        let requestedURLs = await htmlClient.requestedURLs()

        #expect(requestedURLs.count == 1)
        #expect(requestedURLs.first?.path == "/search")
        let components = URLComponents(url: try #require(requestedURLs.first), resolvingAgainstBaseURL: true)
        #expect(components?.queryItems?.first(where: { $0.name == "q" })?.value == "美西")
        #expect(components?.queryItems?.contains(where: { $0.name == "page" }) == false)
        #expect(components?.queryItems?.contains(where: { $0.name == "category" }) == false)
    }

    @Test func loadSearchResultsAddsPageAndCategoryWhenNeeded() async throws {
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

        _ = try await service.loadSearchResults(query: "美国", page: 2, category: .daily)
        let requestedURLs = await htmlClient.requestedURLs()

        #expect(requestedURLs.count == 1)
        let components = URLComponents(url: try #require(requestedURLs.first), resolvingAgainstBaseURL: true)
        #expect(components?.path == "/search")
        #expect(components?.queryItems?.first(where: { $0.name == "q" })?.value == "美国")
        #expect(components?.queryItems?.first(where: { $0.name == "page" })?.value == "2")
        #expect(components?.queryItems?.first(where: { $0.name == "category" })?.value == "daily")
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

    @Test func loadsPostDetailRequestedPageURL() async throws {
        let html = try FixtureLoader.html(named: "post-703863-1")
        let url = URL(string: "https://www.nodeseek.com/")!
        let htmlClient = URLCapturingHTMLClient(response: HTMLResponse(
            statusCode: 200,
            headers: [:],
            finalURL: URL(string: "https://www.nodeseek.com/post-703863-3")!,
            html: html
        ))
        let service = NodeSeekService(
            baseURL: url,
            htmlClient: htmlClient,
            parser: KannaNodeSeekParser(baseURL: url)
        )

        _ = try await service.loadPostDetail(postID: "703863", page: 3)
        let requestedURLs = await htmlClient.requestedURLs()

        #expect(requestedURLs.count == 1)
        #expect(requestedURLs.first?.path == "/post-703863-3")
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

    private func accountHTML(displayName: String) -> String {
        """
        <header>
            <div id="nsk-head" class="nsk-container">
                <a href="/notification">
                    <svg class="iconpark-icon" style="color:rgb(243, 17, 17)">
                        <use href="#remind"></use>
                    </svg>
                </a>
            </div>
        </header>
        <div id="nsk-right-panel-container">
            <div class="user-card">
                <div class="user-head">
                    <a title="\(displayName)" href="/space/31037">
                        <img src="/avatar/31037.png" alt="\(displayName)" class="avatar-normal skeleton">
                    </a>
                    <div class="menu">
                        <a href="/space/31037" class="Username">\(displayName)</a>
                    </div>
                </div>
                <div class="user-stat">
                    <span>等级 Lv 1</span>
                    <span>鸡腿 306</span>
                </div>
            </div>
        </div>
        """
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

    func post(_ url: URL, formFields: [String: String]) async throws -> HTMLResponse {
        urls.append(url)
        return response
    }

    func requestedURLs() -> [URL] {
        urls
    }
}
