//
//  PostDetailInteractor.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation
import OSLog

class PostDetailInteractor: PostDetailInteractorInput {
    
    // MARK: - Properties
    weak var presenter: PostDetailInteractorOutput?
    private let post: PostSummary?
    private let service: NodeSeekService
    private let page: Int
    private let maxChallengeRetryCount: Int
    private let challengeRetryDelayNanoseconds: UInt64
    private let logger = Logger(subsystem: "com.nodeseek.app", category: "PostDetailInteractor")
    
    // MARK: - Initialization
    init(
        post: PostSummary? = nil,
        service: NodeSeekService = NodeSeekService(),
        page: Int = 1,
        maxChallengeRetryCount: Int = 2,
        challengeRetryDelayNanoseconds: UInt64 = 2_000_000_000
    ) {
        self.post = post
        self.service = service
        self.page = max(1, page)
        self.maxChallengeRetryCount = max(0, maxChallengeRetryCount)
        self.challengeRetryDelayNanoseconds = challengeRetryDelayNanoseconds
    }
    
    // MARK: - Methods
    func loadPostDetail() {
        guard let post else {
            presenter?.didFailLoadPostDetail(error: "缺少帖子信息，无法加载详情。")
            return
        }

        Task {
            logger.info("开始加载帖子详情，postID=\(post.id, privacy: .public), page=\(self.page)")
            do {
                let detail = try await loadDetailWithChallengeRetry(postID: post.id)
                logger.info("帖子详情加载成功，postID=\(detail.id, privacy: .public), 评论数量: \(detail.comments.count)")
                await MainActor.run {
                    presenter?.didLoadPostDetail(PostDetailResponse(detail: detail))
                }
            } catch {
                logger.error("帖子详情加载失败，postID=\(post.id, privacy: .public): \(error.localizedDescription)")
                await MainActor.run {
                    presenter?.didFailLoadPostDetail(error: error.localizedDescription)
                }
            }
        }
    }

    private func loadDetailWithChallengeRetry(postID: String) async throws -> PostDetail {
        for attempt in 0...maxChallengeRetryCount {
            logger.info("详情请求第 \(attempt + 1) 次，最大重试: \(self.maxChallengeRetryCount + 1), postID=\(postID, privacy: .public)")
            let result = try await service.loadPostDetail(postID: postID, page: page)
            switch result {
            case .value(let detail):
                return detail
            case .challenge(let challenge):
                logger.warning("详情请求命中验证，postID=\(postID, privacy: .public): \(challenge.logDescription)")
                guard attempt < maxChallengeRetryCount else {
                    throw PostDetailLoadError.challengeNotPassed
                }

                try? await Task.sleep(nanoseconds: challengeRetryDelayNanoseconds)
            }
        }

        throw PostDetailLoadError.unknown
    }
}

private enum PostDetailLoadError: LocalizedError {
    case challengeNotPassed
    case unknown

    var errorDescription: String? {
        switch self {
        case .challengeNotPassed:
            return "站点验证未自动通过，请稍后重试。"
        case .unknown:
            return "详情加载失败，请稍后重试。"
        }
    }
}
