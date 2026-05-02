//
//  PostDetailInteractor.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation

class PostDetailInteractor: PostDetailInteractorInput {
    
    // MARK: - Properties
    weak var presenter: PostDetailInteractorOutput?
    private let post: PostSummary?
    private let service: NodeSeekService
    private let initialPage: Int
    private let commentSubmitter: NodeSeekCommentSubmitter
    private let sessionStore: NodeSeekSessionStore
    
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
            AppLog.info(.postDetail, "开始加载帖子详情，postID=\(post.id), page=\(normalizedPage)")
            do {
                guard let detail = try await loadDetail(postID: post.id, page: normalizedPage) else {
                    return
                }
                AppLog.info(.postDetail, "帖子详情加载成功，postID=\(detail.id), 评论数量: \(detail.comments.count)")
                await MainActor.run {
                    presenter?.didLoadPostDetail(PostDetailResponse(detail: detail))
                }
            } catch {
                await MainActor.run {
                    if Self.isCancelledLoad(error) {
                        AppLog.info(.postDetail, "帖子详情加载取消，postID=\(post.id)")
                        presenter?.didCancelLoadPostDetail()
                    } else {
                        AppLog.error(.postDetail, "帖子详情加载失败，postID=\(post.id): \(error.localizedDescription)")
                        presenter?.didFailLoadPostDetail(error: error.localizedDescription)
                    }
                }
            }
        }
    }

    func submitReply(content: String) {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedContent.isEmpty == false else {
            presenter?.didFailSubmitReply(error: "回复内容不能为空。")
            return
        }

        guard let post else {
            presenter?.didFailSubmitReply(error: PostDetailSubmitError.missingPost.localizedDescription)
            return
        }

        Task {
            AppLog.info(.postDetail, "开始通过 WebView 提交回复，postID=\(post.id)")
            do {
                let response = try await commentSubmitter.submitComment(
                    postID: post.id,
                    content: trimmedContent,
                    referer: post.url
                )
                await sessionStore.recordSuccess()
                await MainActor.run {
                    presenter?.didSubmitReply(PostDetailSubmitReplyResponse(message: response.message))
                }
            } catch {
                AppLog.error(.postDetail, "回复提交失败: \(error.localizedDescription)")
                await MainActor.run {
                    presenter?.didFailSubmitReply(error: error.localizedDescription)
                }
            }
        }
    }

    private func loadDetail(postID: String, page: Int) async throws -> PostDetail? {
        AppLog.info(.postDetail, "详情请求开始，postID=\(postID), page=\(page)")
        let result = try await service.loadPostDetail(postID: postID, page: page)
        switch result {
        case .value(let detail):
            await sessionStore.recordSuccess()
            return detail
        case .challenge(let challenge):
            AppLog.warning(.postDetail, "详情请求命中验证，postID=\(postID): \(challenge.logDescription)")
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

    private static func isCancelledLoad(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
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

private enum PostDetailSubmitError: LocalizedError {
    case challengeRequired(String)
    case missingPost

    var errorDescription: String? {
        switch self {
        case .challengeRequired(let message):
            return message
        case .missingPost:
            return "缺少帖子信息，无法发表评论。"
        }
    }
}
