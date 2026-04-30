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
    private let initialPage: Int
    private let commentSubmitter: NodeSeekCommentSubmitter
    private let sessionStore: NodeSeekSessionStore
    private let logger = Logger(subsystem: "com.nodeseek.app", category: "PostDetailInteractor")
    
    // MARK: - Initialization
    init(
        post: PostSummary? = nil,
        service: NodeSeekService = NodeSeekService(),
        commentSubmitter: NodeSeekCommentSubmitter = NodeSeekCommentSubmitter(),
        page: Int = 1,
        sessionStore: NodeSeekSessionStore = .shared
    ) {
        self.post = post
        self.service = service
        self.initialPage = max(1, page)
        self.commentSubmitter = commentSubmitter
        self.sessionStore = sessionStore
    }
    
    // MARK: - Methods
    func loadPostDetail() {
        loadPostDetail(page: initialPage)
    }

    func loadPostDetail(page: Int) {
        guard let post else {
            presenter?.didFailLoadPostDetail(error: "缺少帖子信息，无法加载详情。")
            return
        }

        let normalizedPage = max(1, page)
        Task {
            logger.info("开始加载帖子详情，postID=\(post.id, privacy: .public), page=\(normalizedPage)")
            do {
                guard let detail = try await loadDetail(postID: post.id, page: normalizedPage) else {
                    return
                }
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

    func submitComment(content: String, completion: @escaping @MainActor (Result<CommentSubmitResponse, Error>) -> Void) {
        guard let post else {
            completion(.failure(PostDetailLoadError.missingPost))
            return
        }

        Task {
            do {
                let referer = post.url
                let response = try await commentSubmitter.submitComment(
                    postID: post.id,
                    content: content,
                    referer: referer
                )
                await MainActor.run {
                    completion(.success(response))
                }
            } catch {
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }

    private func loadDetail(postID: String, page: Int) async throws -> PostDetail? {
        logger.info("详情请求开始，postID=\(postID, privacy: .public), page=\(page)")
        let result = try await service.loadPostDetail(postID: postID, page: page)
        switch result {
        case .value(let detail):
            await sessionStore.recordSuccess()
            return detail
        case .challenge(let challenge):
            logger.warning("详情请求命中验证，postID=\(postID, privacy: .public): \(challenge.logDescription)")
            let message = await sessionStore.recordChallenge(challenge)
            if case .loginRequired = challenge {
                await MainActor.run {
                    presenter?.didRequireLogin(message: message)
                }
                return nil
            }
            throw PostDetailLoadError.challengeRequired(message)
        }
    }
}

private enum PostDetailLoadError: LocalizedError {
    case challengeRequired(String)
    case missingPost
    case unknown

    var errorDescription: String? {
        switch self {
        case .challengeRequired(let message):
            return message
        case .missingPost:
            return "缺少帖子信息，无法发表评论。"
        case .unknown:
            return "详情加载失败，请稍后重试。"
        }
    }
}
