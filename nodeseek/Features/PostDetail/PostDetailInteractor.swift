//
//  PostDetailInteractor.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation

@MainActor
class PostDetailInteractor: PostDetailInteractorInput {
    private enum FavoriteAction {
        case add
        case remove
    }
    
    // MARK: - Properties
    weak var presenter: PostDetailInteractorOutput?
    private let post: PostSummary?
    private let service: NodeSeekService
    private let initialPage: Int
    private let commentSubmitter: NodeSeekCommentSubmitter
    private let collectionSubmitter: PostCollectionSubmitting
    private let postUpvoteSubmitter: PostUpvoteSubmitting
    private let commentUpvoteSubmitter: CommentUpvoteSubmitting
    private let postChickenLegSubmitter: PostChickenLegSubmitting
    private let commentChickenLegSubmitter: CommentChickenLegSubmitting
    private let postDislikeSubmitter: PostDislikeSubmitting
    private let commentDislikeSubmitter: CommentDislikeSubmitting
    private let sessionStore: NodeSeekSessionStore
    
    // MARK: - Initialization
    init(
        post: PostSummary? = nil,
        service: NodeSeekService? = nil,
        commentSubmitter: NodeSeekCommentSubmitter? = nil,
        collectionSubmitter: PostCollectionSubmitting? = nil,
        postUpvoteSubmitter: PostUpvoteSubmitting? = nil,
        commentUpvoteSubmitter: CommentUpvoteSubmitting? = nil,
        postChickenLegSubmitter: PostChickenLegSubmitting? = nil,
        commentChickenLegSubmitter: CommentChickenLegSubmitting? = nil,
        postDislikeSubmitter: PostDislikeSubmitting? = nil,
        commentDislikeSubmitter: CommentDislikeSubmitting? = nil,
        page: Int = 1,
        sessionStore: NodeSeekSessionStore = .shared
    ) {
        self.post = post
        self.service = service ?? NodeSeekService(htmlClient: HTMLLoadingStrategyFactory.makeDefaultClient())
        self.initialPage = max(1, page)
        self.commentSubmitter = commentSubmitter ?? NodeSeekCommentSubmitter()
        self.collectionSubmitter = collectionSubmitter ?? NodeSeekPostCollectionSubmitter()
        self.postUpvoteSubmitter = postUpvoteSubmitter ?? NodeSeekPostUpvoteSubmitter()
        self.commentUpvoteSubmitter = commentUpvoteSubmitter ?? NodeSeekCommentUpvoteSubmitter()
        self.postChickenLegSubmitter = postChickenLegSubmitter ?? NodeSeekPostChickenLegSubmitter()
        self.commentChickenLegSubmitter = commentChickenLegSubmitter ?? NodeSeekCommentChickenLegSubmitter()
        self.postDislikeSubmitter = postDislikeSubmitter ?? NodeSeekPostDislikeSubmitter()
        self.commentDislikeSubmitter = commentDislikeSubmitter ?? NodeSeekCommentDislikeSubmitter()
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
            presenter?.didFailSubmitReply(error: "缺少帖子信息，无法发表评论。")
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

    func addFavorite() {
        submitFavorite(action: .add)
    }

    func removeFavorite() {
        submitFavorite(action: .remove)
    }

    func addPostLike() {
        guard let post else {
            presenter?.didFailAddPostLike(error: "缺少帖子信息，无法点赞。")
            return
        }

        Task {
            AppLog.info(.postDetail, "开始点赞帖子，postID=\(post.id)")
            do {
                let response = try await postUpvoteSubmitter.addUpvote(postID: post.id, referer: post.url)
                await sessionStore.recordSuccess()
                await MainActor.run {
                    presenter?.didAddPostLike(response)
                }
            } catch {
                AppLog.error(.postDetail, "点赞帖子失败，postID=\(post.id): \(error.localizedDescription)")
                await MainActor.run {
                    presenter?.didFailAddPostLike(error: error.localizedDescription)
                }
            }
        }
    }

    func addCommentLike(commentID: String) {
        guard let post else {
            presenter?.didFailAddCommentLike(commentID: commentID, error: "缺少帖子信息，无法点赞。")
            return
        }

        Task {
            AppLog.info(.postDetail, "开始点赞评论，postID=\(post.id), commentID=\(commentID)")
            do {
                let response = try await commentUpvoteSubmitter.addUpvote(commentID: commentID, referer: post.url)
                await sessionStore.recordSuccess()
                await MainActor.run {
                    presenter?.didAddCommentLike(commentID: commentID, response: response)
                }
            } catch {
                AppLog.error(.postDetail, "点赞评论失败，commentID=\(commentID): \(error.localizedDescription)")
                await MainActor.run {
                    presenter?.didFailAddCommentLike(commentID: commentID, error: error.localizedDescription)
                }
            }
        }
    }

    func addPostChickenLeg() {
        guard let post else {
            presenter?.didFailAddPostChickenLeg(error: "缺少帖子信息，无法投放鸡腿。")
            return
        }

        Task {
            AppLog.info(.postDetail, "开始给帖子投放鸡腿，postID=\(post.id)")
            do {
                let response = try await postChickenLegSubmitter.addChickenLeg(postID: post.id, referer: post.url)
                await sessionStore.recordSuccess()
                await MainActor.run {
                    presenter?.didAddPostChickenLeg(response)
                }
            } catch {
                AppLog.error(.postDetail, "给帖子投放鸡腿失败，postID=\(post.id): \(error.localizedDescription)")
                await MainActor.run {
                    presenter?.didFailAddPostChickenLeg(error: error.localizedDescription)
                }
            }
        }
    }

    func addCommentChickenLeg(commentID: String) {
        guard let post else {
            presenter?.didFailAddCommentChickenLeg(commentID: commentID, error: "缺少帖子信息，无法投放鸡腿。")
            return
        }

        Task {
            AppLog.info(.postDetail, "开始给评论投放鸡腿，postID=\(post.id), commentID=\(commentID)")
            do {
                let response = try await commentChickenLegSubmitter.addChickenLeg(commentID: commentID, referer: post.url)
                await sessionStore.recordSuccess()
                await MainActor.run {
                    presenter?.didAddCommentChickenLeg(commentID: commentID, response: response)
                }
            } catch {
                AppLog.error(.postDetail, "给评论投放鸡腿失败，commentID=\(commentID): \(error.localizedDescription)")
                await MainActor.run {
                    presenter?.didFailAddCommentChickenLeg(commentID: commentID, error: error.localizedDescription)
                }
            }
        }
    }

    func addPostOppose() {
        guard let post else {
            presenter?.didFailAddPostOppose(error: "缺少帖子信息，无法反对。")
            return
        }

        Task {
            AppLog.info(.postDetail, "开始反对帖子，postID=\(post.id)")
            do {
                let response = try await postDislikeSubmitter.addDislike(postID: post.id, referer: post.url)
                await sessionStore.recordSuccess()
                await MainActor.run {
                    presenter?.didAddPostOppose(response)
                }
            } catch {
                AppLog.error(.postDetail, "反对帖子失败，postID=\(post.id): \(error.localizedDescription)")
                await MainActor.run {
                    presenter?.didFailAddPostOppose(error: error.localizedDescription)
                }
            }
        }
    }

    func addCommentOppose(commentID: String) {
        guard let post else {
            presenter?.didFailAddCommentOppose(commentID: commentID, error: "缺少帖子信息，无法反对。")
            return
        }

        Task {
            AppLog.info(.postDetail, "开始反对评论，postID=\(post.id), commentID=\(commentID)")
            do {
                let response = try await commentDislikeSubmitter.addDislike(commentID: commentID, referer: post.url)
                await sessionStore.recordSuccess()
                await MainActor.run {
                    presenter?.didAddCommentOppose(commentID: commentID, response: response)
                }
            } catch {
                AppLog.error(.postDetail, "反对评论失败，commentID=\(commentID): \(error.localizedDescription)")
                await MainActor.run {
                    presenter?.didFailAddCommentOppose(commentID: commentID, error: error.localizedDescription)
                }
            }
        }
    }

    private func submitFavorite(action: FavoriteAction) {
        guard let post else {
            let message = "缺少帖子信息，无法收藏。"
            switch action {
            case .add:
                presenter?.didFailAddFavorite(error: message)
            case .remove:
                presenter?.didFailRemoveFavorite(error: message)
            }
            return
        }

        Task {
            let actionText: String
            switch action {
            case .add:
                actionText = "收藏"
            case .remove:
                actionText = "取消收藏"
            }
            AppLog.info(.postDetail, "开始\(actionText)帖子，postID=\(post.id)")
            do {
                let response: PostCollectionResponse
                switch action {
                case .add:
                    response = try await collectionSubmitter.addFavorite(postID: post.id, referer: post.url)
                case .remove:
                    response = try await collectionSubmitter.removeFavorite(postID: post.id, referer: post.url)
                }
                await sessionStore.recordSuccess()
                await MainActor.run {
                    switch action {
                    case .add:
                        presenter?.didAddFavorite(response)
                    case .remove:
                        presenter?.didRemoveFavorite(response)
                    }
                }
            } catch {
                AppLog.error(.postDetail, "\(actionText)帖子失败: \(error.localizedDescription)")
                await MainActor.run {
                    switch action {
                    case .add:
                        presenter?.didFailAddFavorite(error: error.localizedDescription)
                    case .remove:
                        presenter?.didFailRemoveFavorite(error: error.localizedDescription)
                    }
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
            throw MessageError(message: message)
        }
    }

    private static func isCancelledLoad(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}

private struct MessageError: LocalizedError {
    let message: String
    var errorDescription: String? {
        message
    }
}
