//
//  PostListInteractor.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation

@MainActor
class PostListInteractor: PostListInteractorInput {
    
    // MARK: - Properties
    weak var presenter: PostListInteractorOutput?
    private let service: NodeSeekService
    private let sessionStore: NodeSeekSessionStore
    
    // MARK: - Initialization
    init(
        service: NodeSeekService? = nil,
        sessionStore: NodeSeekSessionStore = .shared
    ) {
        self.service = service ?? NodeSeekService(htmlClient: HTMLLoadingStrategyFactory.makeDefaultClient())
        self.sessionStore = sessionStore
    }
    
    // MARK: - Methods
    func loadPosts(category: PostListCategory, sortMode: PostListSortMode) {
        load(page: 1, category: category, sortMode: sortMode, isLoadMore: false)
    }

    func loadMorePosts(page: Int, category: PostListCategory, sortMode: PostListSortMode) {
        load(page: max(2, page), category: category, sortMode: sortMode, isLoadMore: true)
    }

    private func load(page: Int, category: PostListCategory, sortMode: PostListSortMode, isLoadMore: Bool) {
        Task {
            AppLog.info(.postList, "开始加载帖子列表，category=\(category.rawValue), sort=\(sortMode.rawValue), page=\(page), isLoadMore=\(isLoadMore)")
            do {
                let posts = try await loadPosts(page: page, category: category, sortMode: sortMode)
                AppLog.info(.postList, "帖子列表加载成功，category=\(category.rawValue), sort=\(sortMode.rawValue), page=\(page), 数量: \(posts.count)")
                await MainActor.run {
                    if isLoadMore {
                        presenter?.didLoadMorePosts(posts, page: page, category: category, sortMode: sortMode)
                    } else {
                        presenter?.didLoadPosts(posts, category: category, sortMode: sortMode)
                    }
                }
            } catch {
                AppLog.error(.postList, "帖子列表加载失败，category=\(category.rawValue), sort=\(sortMode.rawValue), page=\(page): \(error.localizedDescription)")
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
        AppLog.info(.postList, "列表请求开始，category=\(category.rawValue), sort=\(sortMode.rawValue), page=\(page)")
        let result = try await service.loadPostList(page: page, category: category, sortMode: sortMode)
        switch result {
        case .value(let posts):
            await sessionStore.recordSuccess()
            AppLog.info(.postList, "列表请求拿到有效结果，category=\(category.rawValue), sort=\(sortMode.rawValue), page=\(page)")
            return posts
        case .challenge(let challenge):
            AppLog.warning(.postList, "列表请求命中验证，category=\(category.rawValue), sort=\(sortMode.rawValue), page=\(page): \(challenge.logDescription)")
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
