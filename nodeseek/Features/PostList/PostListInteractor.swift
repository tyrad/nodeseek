//
//  PostListInteractor.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation
import OSLog

class PostListInteractor: PostListInteractorInput {
    
    // MARK: - Properties
    weak var presenter: PostListInteractorOutput?
    private let service: NodeSeekService
    private let maxChallengeRetryCount: Int
    private let challengeRetryDelayNanoseconds: UInt64
    private let logger = Logger(subsystem: "com.nodeseek.app", category: "PostListInteractor")
    
    // MARK: - Initialization
    init(
        service: NodeSeekService = NodeSeekService(),
        maxChallengeRetryCount: Int = 2,
        challengeRetryDelayNanoseconds: UInt64 = 2_000_000_000
    ) {
        self.service = service
        self.maxChallengeRetryCount = max(0, maxChallengeRetryCount)
        self.challengeRetryDelayNanoseconds = challengeRetryDelayNanoseconds
    }
    
    // MARK: - Methods
    func loadPosts(category: PostListCategory) {
        load(page: 1, category: category, isLoadMore: false)
    }

    func loadMorePosts(page: Int, category: PostListCategory) {
        load(page: max(2, page), category: category, isLoadMore: true)
    }

    private func load(page: Int, category: PostListCategory, isLoadMore: Bool) {
        Task {
            logger.info("开始加载帖子列表，category=\(category.rawValue, privacy: .public), page=\(page), isLoadMore=\(isLoadMore)")
            do {
                let posts = try await loadPostsWithChallengeRetry(page: page, category: category)
                logger.info("帖子列表加载成功，category=\(category.rawValue, privacy: .public), page=\(page), 数量: \(posts.count)")
                await MainActor.run {
                    if isLoadMore {
                        presenter?.didLoadMorePosts(posts, page: page, category: category)
                    } else {
                        presenter?.didLoadPosts(posts, category: category)
                    }
                }
            } catch {
                logger.error("帖子列表加载失败，category=\(category.rawValue, privacy: .public), page=\(page): \(error.localizedDescription)")
                await MainActor.run {
                    if isLoadMore {
                        presenter?.didFailLoadMorePosts(error: error.localizedDescription, page: page, category: category)
                    } else {
                        presenter?.didFailLoadPosts(error: error.localizedDescription, category: category)
                    }
                }
            }
        }
    }

    private func loadPostsWithChallengeRetry(page: Int, category: PostListCategory) async throws -> [PostSummary] {
        for attempt in 0...self.maxChallengeRetryCount {
            self.logger.info("列表请求第 \(attempt + 1) 次，最大重试: \(self.maxChallengeRetryCount + 1), category=\(category.rawValue, privacy: .public), page=\(page)")
            let result = try await self.service.loadPostList(page: page, category: category)
            switch result {
            case .value(let posts):
                self.logger.info("第 \(attempt + 1) 次请求拿到有效列表，category=\(category.rawValue, privacy: .public), page=\(page)")
                return posts
            case .challenge(let challenge):
                self.logger.warning("第 \(attempt + 1) 次请求仍命中验证，category=\(category.rawValue, privacy: .public), page=\(page): \(challenge.logDescription)")
                guard attempt < self.maxChallengeRetryCount else {
                    self.logger.error("达到最大重试次数，验证未自动通过，category=\(category.rawValue, privacy: .public), page=\(page)")
                    throw PostListLoadError.challengeNotPassed
                }

                self.logger.info("等待 \(self.challengeRetryDelayNanoseconds / 1_000_000_000)s 后继续重试")
                try? await Task.sleep(nanoseconds: self.challengeRetryDelayNanoseconds)
            }
        }

        throw PostListLoadError.unknown
    }
}

private enum PostListLoadError: LocalizedError {
    case challengeNotPassed
    case unknown

    var errorDescription: String? {
        switch self {
        case .challengeNotPassed:
            return "站点验证未自动通过，请稍后下拉重试。"
        case .unknown:
            return "列表加载失败，请稍后重试。"
        }
    }
}
