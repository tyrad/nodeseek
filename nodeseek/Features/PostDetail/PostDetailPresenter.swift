//
//  PostDetailPresenter.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation

class PostDetailPresenter: PostDetailPresenterProtocol {
    private static let replyRefreshDelayNanoseconds: UInt64 = 300_000_000

    private struct CommentEndRefreshExpectation {
        enum Kind {
            case refreshCurrent
            case probeNext
        }

        let kind: Kind
        let page: Int
        let oldCount: Int
    }

    private enum ReactionKind {
        case like
        case chickenLeg
        case oppose

        var successToast: String {
            switch self {
            case .like:
                return "已点赞"
            case .chickenLeg:
                return "已投放鸡腿"
            case .oppose:
                return "已反对"
            }
        }

        var pendingToast: String {
            switch self {
            case .like:
                return "正在点赞"
            case .chickenLeg:
                return "正在投放鸡腿"
            case .oppose:
                return "正在反对"
            }
        }

        var alreadyActionSuffix: String {
            switch self {
            case .like:
                return "已点赞"
            case .chickenLeg:
                return "已投放鸡腿"
            case .oppose:
                return "已反对"
            }
        }

        var postAlreadyToast: String {
            "该帖子\(alreadyActionSuffix)"
        }

        var commentAlreadyToast: String {
            "该评论\(alreadyActionSuffix)"
        }
    }
    
    // MARK: - Properties
    private weak var view: PostDetailViewProtocol?
    private let interactor: PostDetailInteractorInput
    private let router: PostDetailRouterProtocol
    private let visitedStore: VisitedPostStoreProtocol
    private var currentPage: Int
    private var nextCommentPage: Int?
    private var loadingMoreCommentPage: Int?
    private var refreshingCommentEndPage: Int?
    private var commentPageCounts: [Int: Int] = [:]
    private var loadedCommentPageCounts: [Int: Int] = [:]
    private var pendingCommentEndRefreshExpectation: CommentEndRefreshExpectation?
    private var currentDetail: PostDetail?
    private var fallbackFavoriteCollectedState = false
    private var isSubmittingReply = false
    private var isSubmittingFavorite = false
    private var isSubmittingPostLike = false
    private var isSubmittingPostChickenLeg = false
    private var isSubmittingPostOppose = false
    private var submittingCommentLikeIDs = Set<String>()
    private var submittingCommentChickenLegIDs = Set<String>()
    private var submittingCommentOpposeIDs = Set<String>()
    private var favoriteRollbackDetail: PostDetail?
    private var favoriteRollbackCollectedState: Bool?
    private var isRefreshingAfterReplySubmission = false
    
    // MARK: - Initialization
    init(
        interactor: PostDetailInteractorInput,
        router: PostDetailRouterProtocol,
        initialPage: Int = 1,
        visitedStore: VisitedPostStoreProtocol = EmptyVisitedPostStore()
    ) {
        self.interactor = interactor
        self.router = router
        self.visitedStore = visitedStore
        self.currentPage = max(1, initialPage)
    }
    
    // MARK: - Setup
    func setView(_ view: PostDetailViewProtocol) {
        self.view = view
    }

    private var commentPageSizeHint: Int? {
        guard commentPageCounts.keys.count > 1 else { return nil }
        return commentPageCounts.values.max()
    }
    
    // MARK: - Methods
    func viewDidLoad() {
        view?.showLoading()
        interactor.loadPostDetail(page: currentPage)
    }

    func didTapLogin() {
        router.navigateToLogin { [weak self] in
            self?.view?.showLoading()
            guard let self else { return }
            self.interactor.loadPostDetail(page: self.currentPage)
        }
    }

    func didApproachCommentEnd() {
        guard let page = nextCommentPage else {
            AppLog.debug(.postDetail, "忽略详情评论加载更多: 已无下一页")
            return
        }
        guard loadingMoreCommentPage == nil else {
            AppLog.debug(.postDetail, "忽略详情评论加载更多: 正在加载 page=\(loadingMoreCommentPage ?? -1)")
            return
        }
        guard currentDetail != nil else {
            AppLog.debug(.postDetail, "忽略详情评论加载更多: 详情尚未完成首屏加载")
            return
        }

        loadingMoreCommentPage = page
        AppLog.info(.postDetail, "触发详情评论加载更多: page=\(page)")
        view?.showLoadingMoreComments()
        interactor.loadPostDetail(page: page)
    }

    func didTapRefreshCommentsAtEnd() {
        guard loadingMoreCommentPage == nil, refreshingCommentEndPage == nil else {
            AppLog.debug(.postDetail, "忽略详情评论到底更新: 正在加载 page=\(loadingMoreCommentPage ?? refreshingCommentEndPage ?? -1)")
            return
        }
        guard currentDetail != nil else {
            AppLog.debug(.postDetail, "忽略详情评论到底更新: 详情尚未完成首屏加载")
            return
        }

        let lastPageCount = commentPageCounts[currentPage] ?? currentDetail?.comments.count ?? 0
        let hint = commentPageSizeHint
        let pageToLoad: Int
        let action: String
        if let hint, lastPageCount >= hint {
            pageToLoad = currentPage + 1
            action = "requestNext"
            loadingMoreCommentPage = pageToLoad
            pendingCommentEndRefreshExpectation = CommentEndRefreshExpectation(
                kind: .probeNext,
                page: currentPage,
                oldCount: loadedCommentPageCounts[currentPage] ?? lastPageCount
            )
        } else {
            pageToLoad = currentPage
            action = "refreshCurrent"
            refreshingCommentEndPage = pageToLoad
            pendingCommentEndRefreshExpectation = CommentEndRefreshExpectation(
                kind: .refreshCurrent,
                page: currentPage,
                oldCount: loadedCommentPageCounts[currentPage] ?? lastPageCount
            )
        }

        AppLog.info(.postDetail, "点击详情评论到底更新: action=\(action), currentPage=\(currentPage), targetPage=\(pageToLoad), lastPageCount=\(lastPageCount), pageSizeHint=\(hint ?? -1)")
        view?.showLoadingMoreComments()
        interactor.loadPostDetail(page: pageToLoad)
    }

    func didTapSendReply(content: String) {
        guard isSubmittingReply == false else { return }

        let normalizedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedContent.isEmpty == false else {
            view?.showError(message: "回复内容不能为空。")
            return
        }

        isSubmittingReply = true
        view?.setReplySubmitting(true)
        interactor.submitReply(content: normalizedContent)
    }

    func didTapFavorite() {
        guard isSubmittingFavorite == false else { return }
        isSubmittingFavorite = true
        view?.setFavoriteSubmitting(true)
        let isCollecting = currentFavoriteCollectedState == false
        favoriteRollbackDetail = currentDetail
        favoriteRollbackCollectedState = currentFavoriteCollectedState
        applyOptimisticFavoriteState(isCollected: isCollecting)
        if isCollecting {
            interactor.addFavorite()
        } else {
            interactor.removeFavorite()
        }
    }

    func didTapCommentLike(_ comment: Comment) {
        guard comment.isLikeClicked == false else {
            view?.showToast(message: ReactionKind.like.commentAlreadyToast)
            return
        }
        guard submittingCommentLikeIDs.contains(comment.id) == false else { return }
        submittingCommentLikeIDs.insert(comment.id)
        view?.showToast(message: ReactionKind.like.pendingToast)
        interactor.addCommentLike(commentID: comment.id)
    }

    func didTapCommentChickenLeg(_ comment: Comment) {
        guard comment.isChickenLegClicked == false else {
            view?.showToast(message: ReactionKind.chickenLeg.commentAlreadyToast)
            return
        }
        guard submittingCommentChickenLegIDs.contains(comment.id) == false else { return }
        submittingCommentChickenLegIDs.insert(comment.id)
        view?.showToast(message: ReactionKind.chickenLeg.pendingToast)
        interactor.addCommentChickenLeg(commentID: comment.id)
    }

    func didTapCommentOppose(_ comment: Comment) {
        guard comment.isOpposeClicked == false else {
            view?.showToast(message: ReactionKind.oppose.commentAlreadyToast)
            return
        }
        guard submittingCommentOpposeIDs.contains(comment.id) == false else { return }
        submittingCommentOpposeIDs.insert(comment.id)
        view?.showToast(message: ReactionKind.oppose.pendingToast)
        interactor.addCommentOppose(commentID: comment.id)
    }

    func didTapPostLike() {
        guard currentDetail?.isLikeClicked != true else {
            view?.showToast(message: ReactionKind.like.postAlreadyToast)
            return
        }
        guard isSubmittingPostLike == false else { return }
        isSubmittingPostLike = true
        view?.showToast(message: ReactionKind.like.pendingToast)
        interactor.addPostLike()
    }

    func didTapPostChickenLeg() {
        guard currentDetail?.isChickenLegClicked != true else {
            view?.showToast(message: ReactionKind.chickenLeg.postAlreadyToast)
            return
        }
        guard isSubmittingPostChickenLeg == false else { return }
        isSubmittingPostChickenLeg = true
        view?.showToast(message: ReactionKind.chickenLeg.pendingToast)
        interactor.addPostChickenLeg()
    }

    func didTapPostOppose() {
        guard currentDetail?.isOpposeClicked != true else {
            view?.showToast(message: ReactionKind.oppose.postAlreadyToast)
            return
        }
        guard isSubmittingPostOppose == false else { return }
        isSubmittingPostOppose = true
        view?.showToast(message: ReactionKind.oppose.pendingToast)
        interactor.addPostOppose()
    }

    private var currentFavoriteCollectedState: Bool {
        currentDetail?.isFavoriteCollected ?? fallbackFavoriteCollectedState
    }

    private func markDetailVisited(_ detail: PostDetail) {
        let page = max(1, detail.page)
        let url = NodeSeekSite.postURL(id: detail.id, page: page)

        let post = PostSummary(
            id: detail.id,
            title: detail.title,
            url: url,
            authorName: detail.authorName,
            nodeName: nil,
            replyCount: detail.comments.count,
            viewCount: 0,
            lastActivityText: detail.metadataText,
            avatarURL: detail.avatarURL
        )
        visitedStore.markVisited(post: post, visitedAt: Date())
    }

    private func applyFavoriteState(isCollected: Bool, response: PostCollectionResponse) {
        fallbackFavoriteCollectedState = isCollected
        guard let currentDetail else { return }
        let nextDetail = currentDetail.updatingFavoriteState(
            count: response.postCollectionCount ?? currentDetail.favoriteCount,
            isCollected: isCollected
        )

        guard nextDetail != currentDetail else { return }
        self.currentDetail = nextDetail
        view?.updatePostBody(detail: nextDetail)
    }

    private func applyOptimisticFavoriteState(isCollected: Bool) {
        fallbackFavoriteCollectedState = isCollected
        guard let currentDetail else { return }
        let baseCount = currentDetail.favoriteCount ?? 0
        let optimisticCount = isCollected ? baseCount + 1 : max(0, baseCount - 1)
        let nextDetail = currentDetail.updatingFavoriteState(
            count: optimisticCount,
            isCollected: isCollected
        )
        guard nextDetail != currentDetail else { return }
        self.currentDetail = nextDetail
        view?.updatePostBody(detail: nextDetail)
    }

    private func restoreFavoriteStateFromRollback() {
        if let rollbackCollectedState = favoriteRollbackCollectedState {
            fallbackFavoriteCollectedState = rollbackCollectedState
        }
        guard let rollback = favoriteRollbackDetail else { return }
        guard currentDetail != rollback else { return }
        currentDetail = rollback
        view?.updatePostBody(detail: rollback)
    }

    private func normalizedReactionToast(message: String?, kind: ReactionKind) -> String {
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, trimmed.isEmpty == false, trimmed != "added" else {
            return kind.successToast
        }
        return trimmed
    }

    private func reactionNextCount(current: Int?, serverCount: Int?) -> Int {
        serverCount ?? max(1, (current ?? 0) + 1)
    }

    private func applyPostReactionSuccess(response: CommentUpvoteResponse, kind: ReactionKind) {
        if let currentDetail {
            let currentCount: Int?
            let nextDetail: PostDetail
            switch kind {
            case .like:
                currentCount = currentDetail.likeCount
                nextDetail = currentDetail.updatingPostLikeState(
                    count: reactionNextCount(current: currentCount, serverCount: response.current),
                    isClicked: true
                )
            case .chickenLeg:
                currentCount = currentDetail.chickenLegCount
                nextDetail = currentDetail.updatingPostChickenLegState(
                    count: reactionNextCount(current: currentCount, serverCount: response.current),
                    isClicked: true
                )
            case .oppose:
                currentCount = currentDetail.opposeCount
                nextDetail = currentDetail.updatingPostOpposeState(
                    count: reactionNextCount(current: currentCount, serverCount: response.current),
                    isClicked: true
                )
            }
            self.currentDetail = nextDetail
            view?.updatePostBody(detail: nextDetail)
        }
        view?.showToast(message: normalizedReactionToast(message: response.message, kind: kind))
    }

    private func applyCommentReactionSuccess(
        commentID: String,
        response: CommentUpvoteResponse,
        kind: ReactionKind
    ) {
        if let currentDetail,
           let comment = currentDetail.comments.first(where: { $0.id == commentID }) {
            let currentCount: Int?
            let nextDetail: PostDetail
            let nextCount: Int
            switch kind {
            case .like:
                currentCount = comment.likeCount
                nextCount = reactionNextCount(current: currentCount, serverCount: response.current)
                nextDetail = currentDetail.updatingCommentLikeState(
                    commentID: commentID,
                    count: nextCount,
                    isClicked: true
                )
                view?.updateCommentLike(commentID: commentID, count: nextCount, isClicked: true)
            case .chickenLeg:
                currentCount = comment.chickenLegCount
                nextCount = reactionNextCount(current: currentCount, serverCount: response.current)
                nextDetail = currentDetail.updatingCommentChickenLegState(
                    commentID: commentID,
                    count: nextCount,
                    isClicked: true
                )
                view?.updateCommentChickenLeg(commentID: commentID, count: nextCount, isClicked: true)
            case .oppose:
                currentCount = comment.opposeCount
                nextCount = reactionNextCount(current: currentCount, serverCount: response.current)
                nextDetail = currentDetail.updatingCommentOpposeState(
                    commentID: commentID,
                    count: nextCount,
                    isClicked: true
                )
                view?.updateCommentOppose(commentID: commentID, count: nextCount, isClicked: true)
            }
            self.currentDetail = nextDetail
        }
        view?.showToast(message: normalizedReactionToast(message: response.message, kind: kind))
    }

    private func handleReactionFailure(error: String, kind: ReactionKind) {
        if error.contains(kind.alreadyActionSuffix) {
            view?.showToast(message: error)
            return
        }
        view?.showError(message: error)
    }
}

private extension PostDetail {
    func appendingCommentPage(_ pageDetail: PostDetail) -> PostDetail {
        PostDetail(
            id: id,
            title: title,
            requiredReadingLevel: requiredReadingLevel,
            authorName: authorName,
            avatarURL: avatarURL,
            authorProfileURL: authorProfileURL,
            metadataText: metadataText,
            contentHTML: contentHTML,
            likeCount: likeCount,
            isLikeClicked: isLikeClicked,
            chickenLegCount: chickenLegCount,
            isChickenLegClicked: isChickenLegClicked,
            opposeCount: opposeCount,
            isOpposeClicked: isOpposeClicked,
            favoriteCount: favoriteCount,
            isFavoriteCollected: isFavoriteCollected,
            comments: comments + pageDetail.comments,
            page: max(page, pageDetail.page),
            pagination: pageDetail.pagination,
            isLastPage: pageDetail.pagination?.nextPage == nil
        )
    }
}

// MARK: - Interactor Output
extension PostDetailPresenter: PostDetailInteractorOutput {
    
    func didLoadPostDetail(_ response: PostDetailResponse) {
        favoriteRollbackDetail = nil
        favoriteRollbackCollectedState = nil
        let requestedLoadingMorePage = loadingMoreCommentPage
        let requestedRefreshingEndPage = refreshingCommentEndPage
        let commentEndRefreshExpectation = pendingCommentEndRefreshExpectation
        pendingCommentEndRefreshExpectation = nil
        let loadedPage = max(1, response.detail.page)
        let isAppendingCommentPage = requestedLoadingMorePage == loadedPage
        let isRefreshingCommentEnd = requestedRefreshingEndPage == loadedPage
        let isReplyRefresh = isRefreshingAfterReplySubmission && loadedPage == currentPage && currentDetail != nil
        let shouldFallbackToRefreshCurrentPage = requestedLoadingMorePage != nil
            && isAppendingCommentPage == false
            && loadedPage == currentPage
            && currentDetail != nil
        isRefreshingAfterReplySubmission = false
        loadingMoreCommentPage = nil
        refreshingCommentEndPage = nil

        let renderedDetail: PostDetail
        if isAppendingCommentPage, let currentDetail {
            renderedDetail = currentDetail.appendingCommentPage(response.detail)
            view?.appendCommentPage(detail: response.detail)
            view?.hideLoadingMoreComments()
            AppLog.info(.postDetail, "详情评论加载更多完成: page=\(loadedPage), appended=\(response.detail.comments.count), total=\(renderedDetail.comments.count)")
        } else if isRefreshingCommentEnd || isReplyRefresh || shouldFallbackToRefreshCurrentPage {
            let reason: String
            if isReplyRefresh {
                reason = "reply"
            } else if isRefreshingCommentEnd {
                reason = "endFooter"
            } else {
                reason = "probeFallback"
            }
            renderedDetail = mergedDetailReplacingCommentPage(
                currentDetail: currentDetail,
                pageDetail: response.detail,
                page: loadedPage
            ) ?? response.detail
            view?.refreshCurrentCommentPage(detail: response.detail)
            if isRefreshingCommentEnd || shouldFallbackToRefreshCurrentPage {
                view?.hideLoadingMoreComments()
            }
            AppLog.info(.postDetail, "详情评论当前页刷新完成: page=\(loadedPage), count=\(response.detail.comments.count), reason=\(reason)")
        } else {
            renderedDetail = response.detail
            view?.render(detail: response.detail)
        }

        // 统计“单页评论数”的最大值：只有历史加载过 >=2 个不同页码时才算 pageSizeHint。
        let existingCount = commentPageCounts[loadedPage] ?? 0
        commentPageCounts[loadedPage] = max(existingCount, response.detail.comments.count)
        loadedCommentPageCounts[loadedPage] = response.detail.comments.count

        currentPage = isAppendingCommentPage ? max(currentPage, loadedPage) : loadedPage
        currentDetail = renderedDetail
        nextCommentPage = renderedDetail.pagination?.nextPage
        fallbackFavoriteCollectedState = renderedDetail.isFavoriteCollected
        markDetailVisited(renderedDetail)
        view?.hideLoading()

        if isRefreshingCommentEnd {
            AppLog.debug(.postDetail, "详情评论到底更新完成: page=\(loadedPage), pageSizeHint=\(commentPageSizeHint ?? -1)")
        }
        if shouldFallbackToRefreshCurrentPage {
            AppLog.debug(.postDetail, "详情评论探测下一页回落刷新当前页: requested=\(requestedLoadingMorePage ?? -1), loaded=\(loadedPage)")
        }

        if let expectation = commentEndRefreshExpectation {
            let newCount = response.detail.comments.count
            let shouldToastNoNew: Bool
            switch expectation.kind {
            case .refreshCurrent:
                shouldToastNoNew = isRefreshingCommentEnd && loadedPage == expectation.page && newCount <= expectation.oldCount
            case .probeNext:
                shouldToastNoNew = shouldFallbackToRefreshCurrentPage && loadedPage == expectation.page && newCount <= expectation.oldCount
            }
            if shouldToastNoNew {
                AppLog.info(.postDetail, "详情评论到底更新无新评论: kind=\(expectation.kind), page=\(expectation.page), old=\(expectation.oldCount), new=\(newCount)")
                view?.showToast(message: "暂无新评论")
            }
        }
    }

    func didRequireLogin(message: String) {
        loadingMoreCommentPage = nil
        refreshingCommentEndPage = nil
        nextCommentPage = nil
        isRefreshingAfterReplySubmission = false
        pendingCommentEndRefreshExpectation = nil
        loadedCommentPageCounts.removeAll(keepingCapacity: true)
        view?.hideLoadingMoreComments()
        view?.hideLoading()
        view?.renderLoginRequired(message: message)
    }
    
    func didFailLoadPostDetail(error: String) {
        let isReplyRefresh = isRefreshingAfterReplySubmission
        let isLoadingMore = loadingMoreCommentPage != nil
        let isRefreshingCommentEnd = refreshingCommentEndPage != nil
        loadingMoreCommentPage = nil
        refreshingCommentEndPage = nil
        isRefreshingAfterReplySubmission = false
        pendingCommentEndRefreshExpectation = nil
        if isLoadingMore || isRefreshingCommentEnd {
            AppLog.warning(.postDetail, "详情评论加载更多失败: \(error)")
            view?.hideLoadingMoreComments()
            view?.showToast(message: "更多评论加载失败")
            return
        }
        view?.hideLoading()
        if isReplyRefresh == false {
            view?.showError(message: error)
        }
    }

    func didCancelLoadPostDetail() {
        let isLoadingMore = loadingMoreCommentPage != nil
        let isRefreshingCommentEnd = refreshingCommentEndPage != nil
        loadingMoreCommentPage = nil
        refreshingCommentEndPage = nil
        isRefreshingAfterReplySubmission = false
        pendingCommentEndRefreshExpectation = nil
        if isLoadingMore || isRefreshingCommentEnd {
            view?.hideLoadingMoreComments()
            return
        }
        view?.hideLoading()
    }

    func didSubmitReply(_ response: PostDetailSubmitReplyResponse) {
        isSubmittingReply = false
        view?.setReplySubmitting(false)
        view?.finishReplySubmission()

        let responseMessage = response.message?.trimmingCharacters(in: .whitespacesAndNewlines)
        if currentDetail?.isLastPage == true {
            let toastMessage: String
            if let responseMessage, responseMessage.isEmpty == false {
                toastMessage = responseMessage
            } else {
                toastMessage = "评论已发布"
            }
            view?.showToast(message: toastMessage)
            scheduleCurrentPageRefreshAfterReplySubmission()
        } else {
            view?.showToast(message: "评论已发布，可到最后一页查看")
        }
    }

    func didFailSubmitReply(error: String) {
        isSubmittingReply = false
        view?.setReplySubmitting(false)
        view?.showError(message: error)
    }

    private func scheduleCurrentPageRefreshAfterReplySubmission() {
        let page = currentPage
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.replyRefreshDelayNanoseconds)
            guard let self else { return }
            self.isRefreshingAfterReplySubmission = true
            self.interactor.loadPostDetail(page: page)
        }
    }

    func didAddFavorite(_ response: PostCollectionResponse) {
        isSubmittingFavorite = false
        applyFavoriteState(isCollected: true, response: response)
        favoriteRollbackDetail = nil
        favoriteRollbackCollectedState = nil
        view?.setFavoriteSubmitting(false)
        view?.showToast(message: "已收藏")
    }

    func didFailAddFavorite(error: String) {
        isSubmittingFavorite = false
        restoreFavoriteStateFromRollback()
        favoriteRollbackDetail = nil
        favoriteRollbackCollectedState = nil
        view?.setFavoriteSubmitting(false)
        view?.showError(message: error)
    }

    func didRemoveFavorite(_ response: PostCollectionResponse) {
        isSubmittingFavorite = false
        applyFavoriteState(isCollected: false, response: response)
        favoriteRollbackDetail = nil
        favoriteRollbackCollectedState = nil
        view?.setFavoriteSubmitting(false)
        view?.showToast(message: "已取消收藏")
    }

    func didFailRemoveFavorite(error: String) {
        isSubmittingFavorite = false
        restoreFavoriteStateFromRollback()
        favoriteRollbackDetail = nil
        favoriteRollbackCollectedState = nil
        view?.setFavoriteSubmitting(false)
        view?.showError(message: error)
    }

    func didAddPostLike(_ response: PostUpvoteResponse) {
        isSubmittingPostLike = false
        applyPostReactionSuccess(response: response, kind: .like)
    }

    func didFailAddPostLike(error: String) {
        isSubmittingPostLike = false
        handleReactionFailure(error: error, kind: .like)
    }

    func didAddCommentLike(commentID: String, response: CommentUpvoteResponse) {
        submittingCommentLikeIDs.remove(commentID)
        applyCommentReactionSuccess(commentID: commentID, response: response, kind: .like)
    }

    func didFailAddCommentLike(commentID: String, error: String) {
        submittingCommentLikeIDs.remove(commentID)
        handleReactionFailure(error: error, kind: .like)
    }

    func didAddPostChickenLeg(_ response: PostChickenLegResponse) {
        isSubmittingPostChickenLeg = false
        applyPostReactionSuccess(response: response, kind: .chickenLeg)
    }

    func didFailAddPostChickenLeg(error: String) {
        isSubmittingPostChickenLeg = false
        handleReactionFailure(error: error, kind: .chickenLeg)
    }

    func didAddCommentChickenLeg(commentID: String, response: CommentChickenLegResponse) {
        submittingCommentChickenLegIDs.remove(commentID)
        applyCommentReactionSuccess(commentID: commentID, response: response, kind: .chickenLeg)
    }

    func didFailAddCommentChickenLeg(commentID: String, error: String) {
        submittingCommentChickenLegIDs.remove(commentID)
        handleReactionFailure(error: error, kind: .chickenLeg)
    }

    func didAddPostOppose(_ response: PostDislikeResponse) {
        isSubmittingPostOppose = false
        applyPostReactionSuccess(response: response, kind: .oppose)
    }

    func didFailAddPostOppose(error: String) {
        isSubmittingPostOppose = false
        handleReactionFailure(error: error, kind: .oppose)
    }

    func didAddCommentOppose(commentID: String, response: CommentDislikeResponse) {
        submittingCommentOpposeIDs.remove(commentID)
        applyCommentReactionSuccess(commentID: commentID, response: response, kind: .oppose)
    }

    func didFailAddCommentOppose(commentID: String, error: String) {
        submittingCommentOpposeIDs.remove(commentID)
        handleReactionFailure(error: error, kind: .oppose)
    }
}

private extension PostDetailPresenter {
    func mergedDetailReplacingCommentPage(
        currentDetail: PostDetail?,
        pageDetail: PostDetail,
        page: Int
    ) -> PostDetail? {
        guard var currentDetail else { return nil }
        guard currentDetail.id == pageDetail.id else { return nil }

        let oldCount = loadedCommentPageCounts[page]
        guard let oldCount else { return nil }

        // 只支持“从 1 开始顺序加载”的页替换：page 之前的每一页都要有记录，否则无法安全计算偏移。
        if page > 1 {
            for p in 1..<(page) where loadedCommentPageCounts[p] == nil {
                return nil
            }
        }

        let prefixCount = (1..<page).reduce(0) { partialResult, p in
            partialResult + (loadedCommentPageCounts[p] ?? 0)
        }
        let lowerBound = prefixCount
        let upperBound = prefixCount + oldCount
        guard lowerBound >= 0,
              upperBound >= lowerBound,
              upperBound <= currentDetail.comments.count else {
            return nil
        }

        var nextComments = currentDetail.comments
        nextComments.replaceSubrange(lowerBound..<upperBound, with: pageDetail.comments)

        currentDetail = PostDetail(
            id: currentDetail.id,
            title: currentDetail.title,
            requiredReadingLevel: currentDetail.requiredReadingLevel,
            authorName: currentDetail.authorName,
            avatarURL: currentDetail.avatarURL,
            authorProfileURL: currentDetail.authorProfileURL,
            metadataText: currentDetail.metadataText,
            contentHTML: currentDetail.contentHTML,
            likeCount: currentDetail.likeCount,
            isLikeClicked: currentDetail.isLikeClicked,
            chickenLegCount: currentDetail.chickenLegCount,
            isChickenLegClicked: currentDetail.isChickenLegClicked,
            opposeCount: currentDetail.opposeCount,
            isOpposeClicked: currentDetail.isOpposeClicked,
            favoriteCount: currentDetail.favoriteCount,
            isFavoriteCollected: currentDetail.isFavoriteCollected,
            comments: nextComments,
            page: max(currentDetail.page, pageDetail.page),
            pagination: pageDetail.pagination,
            isLastPage: pageDetail.pagination?.nextPage == nil
        )
        return currentDetail
    }
}
