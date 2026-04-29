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
    private let sessionStore: NodeSeekSessionStore
    private let logger = Logger(subsystem: "com.nodeseek.app", category: "PostListInteractor")
    
    // MARK: - Initialization
    init(
        service: NodeSeekService = NodeSeekService(),
        sessionStore: NodeSeekSessionStore = .shared
    ) {
        self.service = service
        self.sessionStore = sessionStore
    }
    
    // MARK: - Methods
    func loadAccount() {
        Task {
            do {
                let account = try await loadAccount()
                await MainActor.run {
                    presenter?.didLoadAccount(account)
                }
            } catch {
                logger.error("账号信息加载失败: \(error.localizedDescription)")
                await MainActor.run {
                    presenter?.didFailLoadAccount(error: error.localizedDescription)
                }
            }
        }
    }

    func loadPosts(category: PostListCategory, sortMode: PostListSortMode) {
        load(page: 1, category: category, sortMode: sortMode, isLoadMore: false)
    }

    func loadMorePosts(page: Int, category: PostListCategory, sortMode: PostListSortMode) {
        load(page: max(2, page), category: category, sortMode: sortMode, isLoadMore: true)
    }

    private func load(page: Int, category: PostListCategory, sortMode: PostListSortMode, isLoadMore: Bool) {
        Task {
            logger.info("开始加载帖子列表，category=\(category.rawValue, privacy: .public), sort=\(sortMode.rawValue, privacy: .public), page=\(page), isLoadMore=\(isLoadMore)")
            do {
                let posts = try await loadPosts(page: page, category: category, sortMode: sortMode)
                logger.info("帖子列表加载成功，category=\(category.rawValue, privacy: .public), sort=\(sortMode.rawValue, privacy: .public), page=\(page), 数量: \(posts.count)")
                await MainActor.run {
                    if isLoadMore {
                        presenter?.didLoadMorePosts(posts, page: page, category: category, sortMode: sortMode)
                    } else {
                        presenter?.didLoadPosts(posts, category: category, sortMode: sortMode)
                    }
                }
            } catch {
                logger.error("帖子列表加载失败，category=\(category.rawValue, privacy: .public), sort=\(sortMode.rawValue, privacy: .public), page=\(page): \(error.localizedDescription)")
                await MainActor.run {
                    if isLoadMore {
                        presenter?.didFailLoadMorePosts(error: error.localizedDescription, page: page, category: category, sortMode: sortMode)
                    } else {
                        presenter?.didFailLoadPosts(error: error.localizedDescription, category: category, sortMode: sortMode)
                    }
                }
            }
        }
    }

    private func loadPosts(page: Int, category: PostListCategory, sortMode: PostListSortMode) async throws -> [PostSummary] {
        logger.info("列表请求开始，category=\(category.rawValue, privacy: .public), sort=\(sortMode.rawValue, privacy: .public), page=\(page)")
        let result = try await service.loadPostList(page: page, category: category, sortMode: sortMode)
        switch result {
        case .value(let posts):
            await sessionStore.recordSuccess()
            logger.info("列表请求拿到有效结果，category=\(category.rawValue, privacy: .public), sort=\(sortMode.rawValue, privacy: .public), page=\(page)")
            return posts
        case .challenge(let challenge):
            logger.warning("列表请求命中验证，category=\(category.rawValue, privacy: .public), sort=\(sortMode.rawValue, privacy: .public), page=\(page): \(challenge.logDescription)")
            let message = await sessionStore.recordChallenge(challenge)
            throw PostListLoadError.challengeRequired(message)
        }
    }

    private func loadAccount() async throws -> AccountResponse {
        let result = try await service.loadAccount()
        switch result {
        case .value(let account):
            await sessionStore.recordSuccess()
            return account
        case .challenge(let challenge):
            let message = await sessionStore.recordChallenge(challenge)
            throw PostListLoadError.challengeRequired(message)
        }
    }
}

private enum PostListLoadError: LocalizedError {
    case challengeRequired(String)
    case unknown

    var errorDescription: String? {
        switch self {
        case .challengeRequired(let message):
            return message
        case .unknown:
            return "列表加载失败，请稍后重试。"
        }
    }
}
