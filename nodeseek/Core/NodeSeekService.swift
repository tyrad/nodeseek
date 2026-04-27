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
        baseURL: URL = URL(string: "https://www.nodeseek.com")!,
        htmlClient: any HTMLClient = HiddenWebViewHTMLClient(),
        parser: (any NodeSeekParser)? = nil,
        challengeDetector: ChallengeDetector = ChallengeDetector()
    ) {
        self.baseURL = baseURL
        self.htmlClient = htmlClient
        self.parser = parser ?? KannaNodeSeekParser(baseURL: baseURL)
        self.challengeDetector = challengeDetector
    }

    func loadPostList(page: Int = 1, category: PostListCategory = .all) async throws -> NodeSeekResult<[PostSummary]> {
        let targetURL = postListURL(page: page, category: category)
        logger.info("开始抓取 NodeSeek 列表，category=\(category.rawValue, privacy: .public), page=\(page): \(targetURL.absoluteString)")
        let response = try await htmlClient.get(targetURL)
        logger.info("抓取返回 category=\(category.rawValue, privacy: .public), page=\(page), status=\(response.statusCode), htmlLength=\(response.html.count), finalURL=\(response.finalURL.absoluteString)")

        if let challenge = challengeDetector.detect(response: response) {
            logger.warning("检测到 challenge: \(challenge.logDescription)")
            return .challenge(challenge)
        }

        let posts = try parser.parsePostList(html: response.html)
        logger.info("列表解析完成，帖子数量: \(posts.count)")
        return .value(posts)
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

    private func postListURL(page: Int, category: PostListCategory) -> URL {
        let normalized = max(1, page)
        guard let pathComponent = category.pathComponent else {
            return baseURL.appendingPathComponent("page-\(normalized)")
        }

        if normalized == 1 {
            return baseURL
                .appendingPathComponent("categories")
                .appendingPathComponent(pathComponent)
        }

        return baseURL
            .appendingPathComponent("categories")
            .appendingPathComponent(pathComponent)
            .appendingPathComponent("page-\(normalized)")
    }

    private func postDetailURL(postID: String, page: Int) -> URL {
        let normalized = max(1, page)
        return baseURL.appendingPathComponent("post-\(postID)-\(normalized)")
    }
}
