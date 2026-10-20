//
//  NodeSeekService.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation

struct NodeSeekService: Sendable {
    let baseURL: URL
    private let htmlClient: any HTMLClient
    private let parser: any NodeSeekParser
    private let challengeDetector: ChallengeDetector
    private let currentAccountStore: CurrentAccountStore?

    init(
        baseURL: URL = NodeSeekSite.baseURL,
        htmlClient: any HTMLClient = HiddenWebViewHTMLClient(),
        parser: (any NodeSeekParser)? = nil,
        challengeDetector: ChallengeDetector = ChallengeDetector(),
        currentAccountStore: CurrentAccountStore? = .shared
    ) {
        self.baseURL = baseURL
        self.htmlClient = htmlClient
        self.parser = parser ?? KannaNodeSeekParser(
            baseURL: baseURL,
            debugLogger: { AppLog.debug(.account, $0) }
        )
        self.challengeDetector = challengeDetector
        self.currentAccountStore = currentAccountStore
    }

    func loadPostList(
        page: Int = 1,
        category: PostListCategoryItem = .all,
        sortMode: PostListSortMode = .replyTime
    ) async throws -> NodeSeekResult<[PostSummary]> {
        let targetURL = postListURL(page: page, category: category, sortMode: sortMode)
        AppLog.info(.service, "开始抓取 NodeSeek 列表，category=\(category.rawValue), sort=\(sortMode.rawValue), page=\(page): \(targetURL.absoluteString)")
        let response = try await htmlClient.get(targetURL)
        AppLog.info(.service, "抓取返回 category=\(category.rawValue), sort=\(sortMode.rawValue), page=\(page), status=\(response.statusCode), htmlLength=\(response.html.utf8.count), finalURL=\(response.finalURL.absoluteString)")

        switch try await parsePostListInBackground(response: response) {
        case .challenge(let challenge):
            AppLog.warning(.service, "检测到 challenge: \(challenge.logDescription)")
            return .challenge(challenge)
        case .posts(let posts, let account):
            await saveOpportunisticAccount(account)
            AppLog.info(.service, "列表解析完成，帖子数量: \(posts.count)")
            return .value(posts)
        }
    }

    func loadSearchResults(
        query: String,
        page: Int = 1,
        category: PostListCategory = .all
    ) async throws -> NodeSeekResult<[PostSummary]> {
        let targetURL = searchURL(query: query, page: page, category: category)
        AppLog.info(.service, "开始抓取 NodeSeek 搜索，category=\(category.rawValue), page=\(page): \(targetURL.absoluteString)")
        let response = try await htmlClient.get(targetURL)
        AppLog.info(.service, "搜索抓取返回 category=\(category.rawValue), page=\(page), status=\(response.statusCode), htmlLength=\(response.html.utf8.count), finalURL=\(response.finalURL.absoluteString)")

        switch try await parsePostListInBackground(response: response) {
        case .challenge(let challenge):
            AppLog.warning(.service, "检测到搜索 challenge: \(challenge.logDescription)")
            return .challenge(challenge)
        case .posts(let posts, let account):
            await saveOpportunisticAccount(account)
            AppLog.info(.service, "搜索解析完成，帖子数量: \(posts.count)")
            return .value(posts)
        }
    }

    func loadAccount() async throws -> NodeSeekResult<AccountResponse> {
        let targetURL = baseURL
        AppLog.info(.service, "开始抓取 NodeSeek 账号信息: \(targetURL.absoluteString)")
        AppLog.debug(.account, "service: request \(targetURL.absoluteString)")
        let response = try await htmlClient.get(targetURL)
        AppLog.info(.service, "账号信息抓取返回 status=\(response.statusCode), htmlLength=\(response.html.count), finalURL=\(response.finalURL.absoluteString)")
        AppLog.debug(
            .account,
            "service: response status=\(response.statusCode) len=\(response.html.count) final=\(response.finalURL.path) userCard=\(response.html.contains("user-card")) usercardMe=\(response.html.contains("usercard-me")) tempScript=\(response.html.contains("temp-script")) capturedConfig=\(response.html.contains("nodeseek-captured-config")) memberID=\(response.html.contains("member_id"))"
        )

        if let challenge = challengeDetector.detect(response: response) {
            AppLog.warning(.service, "检测到账号信息 challenge: \(challenge.logDescription)")
            AppLog.debug(.account, "service: challenge \(challenge.logDescription)")
            return .challenge(challenge)
        }

        let account = try parser.parseAccount(html: response.html)
        await currentAccountStore?.save(account)
        AppLog.info(.service, "账号信息解析完成，loggedIn=\(account.isLoggedIn), displayName=\(account.displayName)")
        AppLog.debug(.account, "service: parsed loggedIn=\(account.isLoggedIn) name=\(account.displayName) avatar=\(account.avatarURL?.path ?? "nil") profile=\(account.profileURL?.path ?? "nil") stats=\(account.stats.joined(separator: "|"))")
        return .value(account)
    }

    func loadPostDetail(postID: String, page: Int = 1) async throws -> NodeSeekResult<PostDetail> {
        let targetURL = postDetailURL(postID: postID, page: page)
        AppLog.info(.service, "开始抓取 NodeSeek 详情，postID=\(postID), page=\(page): \(targetURL.absoluteString)")
        let response = try await htmlClient.get(targetURL)
        AppLog.info(.service, "详情抓取返回 postID=\(postID), page=\(page), status=\(response.statusCode), htmlLength=\(response.html.count), finalURL=\(response.finalURL.absoluteString)")

        if let challenge = challengeDetector.detect(response: response) {
            AppLog.warning(.service, "检测到详情 challenge: \(challenge.logDescription)")
            return .challenge(challenge)
        }

        await updateCurrentAccountIfPresent(in: response.html)
        let detail = try parser.parsePostDetail(html: response.html, url: targetURL)
        AppLog.info(.service, "详情解析完成，postID=\(detail.id), 评论数量: \(detail.comments.count)")
        return .value(detail)
    }

    private func postListURL(page: Int, category: PostListCategoryItem, sortMode: PostListSortMode) -> URL {
        let url = category.pathComponents(page: page).reduce(baseURL) { partialURL, pathComponent in
            partialURL.appendingPathComponent(pathComponent)
        }
        return url.appendingSortQuery(sortMode)
    }

    private func postDetailURL(postID: String, page: Int) -> URL {
        if baseURL == NodeSeekSite.baseURL {
            return NodeSeekSite.postURL(id: postID, page: page)
        }
        return baseURL.appendingPathComponent("post-\(postID)-\(max(1, page))")
    }

    private func searchURL(query: String, page: Int, category: PostListCategory) -> URL {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("search"),
            resolvingAgainstBaseURL: true
        ) else {
            return baseURL.appendingPathComponent("search")
        }

        var queryItems = [URLQueryItem(name: "q", value: query)]
        let normalizedPage = max(1, page)
        if normalizedPage > 1 {
            queryItems.append(URLQueryItem(name: "page", value: "\(normalizedPage)"))
        }
        if let categoryValue = category.searchQueryValue {
            queryItems.append(URLQueryItem(name: "category", value: categoryValue))
        }
        components.queryItems = queryItems
        return components.url ?? baseURL.appendingPathComponent("search")
    }

    private func updateCurrentAccountIfPresent(in html: String) async {
        guard currentAccountStore != nil else { return }
        await saveOpportunisticAccount(Self.opportunisticAccount(in: html, parser: parser))
    }

    private func saveOpportunisticAccount(_ account: AccountResponse?) async {
        guard let currentAccountStore, let account else { return }
        await currentAccountStore.save(account)
        AppLog.debug(.account, "service: opportunistic account save -> loggedIn=\(account.isLoggedIn) name=\(account.displayName)")
    }

    /// 整页 HTML 解析在真机上要十几到几十毫秒，留在主线程会让列表分页时掉帧，
    /// 所以 challenge 检测、账号解析和列表解析一起放到后台执行。
    private func parsePostListInBackground(response: HTMLResponse) async throws -> PostListParseOutcome {
        let parser = parser
        let challengeDetector = challengeDetector
        let parsesAccount = currentAccountStore != nil
        return try await Task.detached(priority: .userInitiated) {
            if let challenge = challengeDetector.detect(response: response) {
                return .challenge(challenge)
            }
            let account = parsesAccount ? Self.opportunisticAccount(in: response.html, parser: parser) : nil
            let posts = try parser.parsePostList(html: response.html)
            return .posts(posts, account: account)
        }.value
    }

    private nonisolated static func opportunisticAccount(in html: String, parser: any NodeSeekParser) -> AccountResponse? {
        guard htmlContainsCurrentAccountSignal(html) else { return nil }

        do {
            let account = try parser.parseAccount(html: html)
            return account.isLoggedIn ? account : nil
        } catch {
            AppLog.debug(.account, "service: opportunistic account parse failed \(error.localizedDescription)")
            return nil
        }
    }

    private nonisolated static func htmlContainsCurrentAccountSignal(_ html: String) -> Bool {
        html.contains("user-card")
            || html.contains(#"id="temp-script""#)
            || html.contains(#"id='temp-script'"#)
            || html.contains("nodeseek-captured-config")
    }
}

private enum PostListParseOutcome: Sendable {
    case challenge(ChallengeKind)
    case posts([PostSummary], account: AccountResponse?)
}

private extension URL {
    func appendingSortQuery(_ sortMode: PostListSortMode) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: true) else {
            return self
        }

        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "sortBy" }
        queryItems.append(URLQueryItem(name: "sortBy", value: sortMode.rawValue))
        components.queryItems = queryItems
        return components.url ?? self
    }
}
