//
//  NodeSeekService.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation
import OSLog

struct NodeSeekService: Sendable {
    let baseURL: URL
    private let htmlClient: any HTMLClient
    private let parser: any NodeSeekParser
    private let challengeDetector: ChallengeDetector
    private let logger = Logger(subsystem: "com.nodeseek.app", category: "NodeSeekService")

    init(
        baseURL: URL = NodeSeekSite.baseURL,
        htmlClient: any HTMLClient = HiddenWebViewHTMLClient(),
        parser: (any NodeSeekParser)? = nil,
        challengeDetector: ChallengeDetector = ChallengeDetector()
    ) {
        self.baseURL = baseURL
        self.htmlClient = htmlClient
        self.parser = parser ?? KannaNodeSeekParser(
            baseURL: baseURL,
            debugLogger: CurrentAccountDebugLog.post
        )
        self.challengeDetector = challengeDetector
    }

    func loadPostList(
        page: Int = 1,
        category: PostListCategory = .all,
        sortMode: PostListSortMode = .replyTime
    ) async throws -> NodeSeekResult<[PostSummary]> {
        let targetURL = postListURL(page: page, category: category, sortMode: sortMode)
        logger.info("开始抓取 NodeSeek 列表，category=\(category.rawValue, privacy: .public), sort=\(sortMode.rawValue, privacy: .public), page=\(page): \(targetURL.absoluteString)")
        let response = try await htmlClient.get(targetURL)
        logger.info("抓取返回 category=\(category.rawValue, privacy: .public), sort=\(sortMode.rawValue, privacy: .public), page=\(page), status=\(response.statusCode), htmlLength=\(response.html.count), finalURL=\(response.finalURL.absoluteString)")

        if let challenge = challengeDetector.detect(response: response) {
            logger.warning("检测到 challenge: \(challenge.logDescription)")
            return .challenge(challenge)
        }

        let posts = try parser.parsePostList(html: response.html)
        logger.info("列表解析完成，帖子数量: \(posts.count)")
        return .value(posts)
    }

    func loadAccount() async throws -> NodeSeekResult<AccountResponse> {
        let targetURL = baseURL
        logger.info("开始抓取 NodeSeek 账号信息: \(targetURL.absoluteString)")
        CurrentAccountDebugLog.post("service: request \(targetURL.absoluteString)")
        let response = try await htmlClient.get(targetURL)
        logger.info("账号信息抓取返回 status=\(response.statusCode), htmlLength=\(response.html.count), finalURL=\(response.finalURL.absoluteString)")
        CurrentAccountDebugLog.post(
            "service: response status=\(response.statusCode) len=\(response.html.count) final=\(response.finalURL.path) userCard=\(response.html.contains("user-card")) usercardMe=\(response.html.contains("usercard-me")) tempScript=\(response.html.contains("temp-script")) capturedConfig=\(response.html.contains("nodeseek-captured-config")) memberID=\(response.html.contains("member_id"))"
        )

        if let challenge = challengeDetector.detect(response: response) {
            logger.warning("检测到账号信息 challenge: \(challenge.logDescription)")
            CurrentAccountDebugLog.post("service: challenge \(challenge.logDescription)")
            return .challenge(challenge)
        }

        let account = try parser.parseAccount(html: response.html)
        logger.info("账号信息解析完成，loggedIn=\(account.isLoggedIn, privacy: .public), displayName=\(account.displayName, privacy: .public)")
        CurrentAccountDebugLog.post("service: parsed loggedIn=\(account.isLoggedIn) name=\(account.displayName) avatar=\(account.avatarURL?.path ?? "nil") profile=\(account.profileURL?.path ?? "nil") stats=\(account.stats.joined(separator: "|"))")
        return .value(account)
    }

    func loadPostDetail(postID: String, page: Int = 1) async throws -> NodeSeekResult<PostDetail> {
        let targetURL = postDetailURL(postID: postID, page: page)
        logger.info("开始抓取 NodeSeek 详情，postID=\(postID, privacy: .public), page=\(page): \(targetURL.absoluteString)")
        let response = try await htmlClient.get(targetURL)
        logger.info("详情抓取返回 postID=\(postID, privacy: .public), page=\(page), status=\(response.statusCode), htmlLength=\(response.html.count), finalURL=\(response.finalURL.absoluteString)")

        if let challenge = challengeDetector.detect(response: response) {
            logger.warning("检测到详情 challenge: \(challenge.logDescription)")
            return .challenge(challenge)
        }

        let detail = try parser.parsePostDetail(html: response.html, url: targetURL)
        logger.info("详情解析完成，postID=\(detail.id, privacy: .public), 评论数量: \(detail.comments.count)")
        return .value(detail)
    }

    private func postListURL(page: Int, category: PostListCategory, sortMode: PostListSortMode) -> URL {
        let normalized = max(1, page)
        let url: URL
        guard let pathComponent = category.pathComponent else {
            url = baseURL.appendingPathComponent("page-\(normalized)")
            return url.appendingSortQuery(sortMode)
        }

        if normalized == 1 {
            url = baseURL
                .appendingPathComponent("categories")
                .appendingPathComponent(pathComponent)
            return url.appendingSortQuery(sortMode)
        }

        url = baseURL
            .appendingPathComponent("categories")
            .appendingPathComponent(pathComponent)
            .appendingPathComponent("page-\(normalized)")
        return url.appendingSortQuery(sortMode)
    }

    private func postDetailURL(postID: String, page: Int) -> URL {
        if baseURL == NodeSeekSite.baseURL {
            return NodeSeekSite.postURL(id: postID, page: page)
        }
        return baseURL.appendingPathComponent("post-\(postID)-\(max(1, page))")
    }
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
