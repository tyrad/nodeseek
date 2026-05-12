//
//  PostDetailPresenter.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation

class PostDetailPresenter: PostDetailPresenterProtocol {
    private static let replyRefreshDelayNanoseconds: UInt64 = 300_000_000

    private enum CommentPageRequest {
        case append(page: Int)
        case refreshCurrent(page: Int, oldCount: Int, showNoNewToast: Bool)
        case probeNext(requestedPage: Int, currentPage: Int, oldCount: Int)
        case replyRefresh(page: Int)

        var requestedPage: Int {
            switch self {
            case .append(let page),
                 .refreshCurrent(let page, _, _),
                 .replyRefresh(let page):
                return page
            case .probeNext(let requestedPage, _, _):
                return requestedPage
            }
        }

        var showsFooterLoading: Bool {
            switch self {
            case .append, .refreshCurrent, .probeNext:
                return true
            case .replyRefresh:
                return false
            }
        }
    }

    private struct CommentPageTracker {
        private var historicalPageCounts: [Int: Int] = [:]
        private var loadedPageCounts: [Int: Int] = [:]

        var pageSizeHint: Int? {
            guard historicalPageCounts.keys.count > 1 else { return nil }
            return historicalPageCounts.values.max()
        }

        func loadedCount(for page: Int) -> Int? {
            loadedPageCounts[page]
        }

        mutating func recordLoadedPage(page: Int, count: Int, replacesLoadedPages: Bool) {
            let normalizedPage = max(1, page)
            if replacesLoadedPages {
                loadedPageCounts = [normalizedPage: count]
            } else {
                loadedPageCounts[normalizedPage] = count
            }
            historicalPageCounts[normalizedPage] = max(historicalPageCounts[normalizedPage] ?? 0, count)
        }

        mutating func reset() {
            historicalPageCounts.removeAll(keepingCapacity: true)
            loadedPageCounts.removeAll(keepingCapacity: true)
        }

        func replacingCommentPage(
            in currentDetail: PostDetail?,
            with pageDetail: PostDetail,
            page: Int
        ) -> PostDetail? {
            guard var currentDetail else { return nil }
            guard currentDetail.id == pageDetail.id else { return nil }

            let normalizedPage = max(1, page)
            guard let oldCount = loadedPageCounts[normalizedPage] else { return nil }

            if normalizedPage > 1 {
                for p in 1..<normalizedPage where loadedPageCounts[p] == nil {
                    return nil
                }
            }

            let prefixCount = (1..<normalizedPage).reduce(0) { partialResult, page in
                partialResult + (loadedPageCounts[page] ?? 0)
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
            currentDetail = currentDetail.replacingComments(
                nextComments,
                page: max(currentDetail.page, pageDetail.page),
                pagination: pageDetail.pagination
            )
            return currentDetail
        }
    }

    private struct CommentPageResponseHandling {
        let renderedDetail: PostDetail
        let shouldReplaceLoadedPages: Bool
        let shouldHideFooterLoading: Bool
        let shouldToastNoNewComments: Bool
        let logReason: String?
    }

    private struct CommentPageReplaceResult {
        let detail: PostDetail
        let usedFallback: Bool
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
    private let initialPage: Int
    private var currentPage: Int
    private var nextCommentPage: Int?
    private var activeCommentPageRequest: CommentPageRequest?
    private var commentPageTracker = CommentPageTracker()
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
        self.initialPage = max(1, initialPage)
        self.currentPage = self.initialPage
    }
    
    // MARK: - Setup
    func setView(_ view: PostDetailViewProtocol) {
        self.view = view
    }

    private var commentPageSizeHint: Int? {
        commentPageTracker.pageSizeHint
    }
    
    // MARK: - Methods
    func viewDidLoad() {
        view?.showLoading()
        interactor.loadPostDetail(page: currentPage)
    }

    func refreshInitialPage() {
        // currentPage 会随着加载更多变化；右上角刷新要回到进入详情时的页码。
        view?.showLoading()
        activeCommentPageRequest = nil
        nextCommentPage = nil
        commentPageTracker.reset()
        currentDetail = nil
        currentPage = initialPage
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
        guard activeCommentPageRequest == nil else {
            AppLog.debug(.postDetail, "忽略详情评论加载更多: 正在加载 page=\(activeCommentPageRequest?.requestedPage ?? -1)")
            return
        }
        guard currentDetail != nil else {
            AppLog.debug(.postDetail, "忽略详情评论加载更多: 详情尚未完成首屏加载")
            return
        }

        activeCommentPageRequest = .append(page: page)
        AppLog.info(.postDetail, "触发详情评论加载更多: page=\(page)")
        view?.showLoadingMoreComments()
        interactor.loadPostDetail(page: page)
    }

    func didTapRefreshCommentsAtEnd() {
        guard activeCommentPageRequest == nil else {
            AppLog.debug(.postDetail, "忽略详情评论到底更新: 正在加载 page=\(activeCommentPageRequest?.requestedPage ?? -1)")
            return
        }
        guard currentDetail != nil else {
            AppLog.debug(.postDetail, "忽略详情评论到底更新: 详情尚未完成首屏加载")
            return
        }

        let lastPageCount = commentPageTracker.loadedCount(for: currentPage) ?? currentDetail?.comments.count ?? 0
        let hint = commentPageSizeHint
        let pageToLoad: Int
        let action: String
        if let hint, lastPageCount >= hint {
            pageToLoad = currentPage + 1
            action = "requestNext"
            activeCommentPageRequest = .probeNext(
                requestedPage: pageToLoad,
                currentPage: currentPage,
                oldCount: lastPageCount
            )
        } else {
            pageToLoad = currentPage
            action = "refreshCurrent"
            activeCommentPageRequest = .refreshCurrent(
                page: pageToLoad,
                oldCount: lastPageCount,
                showNoNewToast: true
            )
        }

        AppLog.info(.postDetail, "点击详情评论到底更新: action=\(action), currentPage=\(currentPage), targetPage=\(pageToLoad), lastPageCount=\(lastPageCount), pageSizeHint=\(hint ?? -1)")
        view?.showLoadingMoreComments()
        interactor.loadPostDetail(page: pageToLoad)
    }

    func didTapSendReply(content: String) {
        let startedAt = Date()
        AppLog.info(.postDetail, "Presenter 收到发送回复: contentLength=\(content.count), isSubmittingReply=\(isSubmittingReply), currentPage=\(currentPage), isLastPage=\(currentDetail?.isLastPage == true)")
        guard isSubmittingReply == false else {
            AppLog.warning(.postDetail, "Presenter 忽略发送回复: 已在提交中, elapsedMs=\(AppLog.elapsedMilliseconds(since: startedAt))")
            return
        }

        let normalizedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedContent.isEmpty == false else {
            AppLog.warning(.postDetail, "Presenter 中止发送回复: 规范化后内容为空, elapsedMs=\(AppLog.elapsedMilliseconds(since: startedAt))")
            view?.showError(message: "回复内容不能为空。")
            return
        }

        isSubmittingReply = true
        AppLog.info(.postDetail, "Presenter 设置回复提交状态=true 前: elapsedMs=\(AppLog.elapsedMilliseconds(since: startedAt))")
        view?.setReplySubmitting(true)
        AppLog.info(.postDetail, "Presenter 设置回复提交状态=true 后，准备调用 interactor: normalizedLength=\(normalizedContent.count), elapsedMs=\(AppLog.elapsedMilliseconds(since: startedAt))")
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
        replacingComments(
            comments + pageDetail.comments,
            page: max(page, pageDetail.page),
            pagination: pageDetail.pagination
        )
    }

    func replacingComments(
        _ nextComments: [Comment],
        page: Int,
        pagination: PostDetailPagination?
    ) -> PostDetail {
        PostDetail(
            id: id,
            title: title,
            requiredReadingLevel: requiredReadingLevel,
            authorName: authorName,
            avatarURL: avatarURL,
            authorProfileURL: authorProfileURL,
            metadataText: metadataText,
            contentHTML: contentHTML,
            signatureHTML: signatureHTML,
            likeCount: likeCount,
            isLikeClicked: isLikeClicked,
            chickenLegCount: chickenLegCount,
            isChickenLegClicked: isChickenLegClicked,
            opposeCount: opposeCount,
            isOpposeClicked: isOpposeClicked,
            favoriteCount: favoriteCount,
            isFavoriteCollected: isFavoriteCollected,
            isRestricted: isRestricted,
            comments: nextComments,
            page: page,
            pagination: pagination,
            isLastPage: pagination?.nextPage == nil
        )
    }
}

// MARK: - Interactor Output
extension PostDetailPresenter: PostDetailInteractorOutput {
    
    func didLoadPostDetail(_ response: PostDetailResponse) {
        favoriteRollbackDetail = nil
        favoriteRollbackCollectedState = nil
        let commentRequest = activeCommentPageRequest
        activeCommentPageRequest = nil
        let loadedPage = max(1, response.detail.page)

        let handling = handleCommentPageResponse(
            response.detail,
            loadedPage: loadedPage,
            request: commentRequest
        )
        commentPageTracker.recordLoadedPage(
            page: loadedPage,
            count: response.detail.comments.count,
            replacesLoadedPages: handling.shouldReplaceLoadedPages
        )

        currentPage = handling.renderedDetail.page
        currentDetail = handling.renderedDetail
        nextCommentPage = handling.renderedDetail.pagination?.nextPage
        fallbackFavoriteCollectedState = handling.renderedDetail.isFavoriteCollected
        markDetailVisited(handling.renderedDetail)
        view?.hideLoading()

        if handling.shouldHideFooterLoading {
            view?.hideLoadingMoreComments()
        }
        if let logReason = handling.logReason {
            AppLog.debug(.postDetail, "详情评论页请求完成: reason=\(logReason), page=\(loadedPage), pageSizeHint=\(commentPageSizeHint ?? -1)")
        }
        if handling.shouldToastNoNewComments {
            AppLog.info(.postDetail, "详情评论到底更新无新评论: page=\(loadedPage), count=\(response.detail.comments.count)")
            view?.showToast(message: "暂无新评论")
        }
    }

    private func handleCommentPageResponse(
        _ detail: PostDetail,
        loadedPage: Int,
        request: CommentPageRequest?
    ) -> CommentPageResponseHandling {
        guard let request else {
            view?.render(detail: detail)
            return CommentPageResponseHandling(
                renderedDetail: detail,
                shouldReplaceLoadedPages: true,
                shouldHideFooterLoading: false,
                shouldToastNoNewComments: false,
                logReason: nil
            )
        }

        switch request {
        case .append(let page) where page == loadedPage:
            let renderedDetail = currentDetail?.appendingCommentPage(detail) ?? detail
            view?.appendCommentPage(detail: detail)
            AppLog.info(.postDetail, "详情评论加载更多完成: page=\(loadedPage), appended=\(detail.comments.count), total=\(renderedDetail.comments.count)")
            return CommentPageResponseHandling(
                renderedDetail: renderedDetail,
                shouldReplaceLoadedPages: false,
                shouldHideFooterLoading: true,
                shouldToastNoNewComments: false,
                logReason: "append"
            )

        case .refreshCurrent(let page, let oldCount, let showNoNewToast) where page == loadedPage:
            let replaceResult = replacingCurrentCommentPage(with: detail, page: loadedPage)
            view?.refreshCurrentCommentPage(detail: detail)
            AppLog.info(.postDetail, "详情评论当前页刷新完成: page=\(loadedPage), count=\(detail.comments.count), reason=endFooter")
            return CommentPageResponseHandling(
                renderedDetail: replaceResult.detail,
                shouldReplaceLoadedPages: replaceResult.usedFallback,
                shouldHideFooterLoading: true,
                shouldToastNoNewComments: showNoNewToast && detail.comments.count <= oldCount,
                logReason: "endFooter"
            )

        case .probeNext(let requestedPage, _, _) where requestedPage == loadedPage:
            let renderedDetail = currentDetail?.appendingCommentPage(detail) ?? detail
            view?.appendCommentPage(detail: detail)
            AppLog.info(.postDetail, "详情评论探测下一页加载完成: page=\(loadedPage), appended=\(detail.comments.count), total=\(renderedDetail.comments.count)")
            return CommentPageResponseHandling(
                renderedDetail: renderedDetail,
                shouldReplaceLoadedPages: false,
                shouldHideFooterLoading: true,
                shouldToastNoNewComments: false,
                logReason: "probeNext"
            )

        case .probeNext(let requestedPage, let currentPage, let oldCount) where currentPage == loadedPage:
            let replaceResult = replacingCurrentCommentPage(with: detail, page: loadedPage)
            view?.refreshCurrentCommentPage(detail: detail)
            AppLog.info(.postDetail, "详情评论探测下一页回落刷新当前页: requested=\(requestedPage), loaded=\(loadedPage), count=\(detail.comments.count)")
            return CommentPageResponseHandling(
                renderedDetail: replaceResult.detail,
                shouldReplaceLoadedPages: replaceResult.usedFallback,
                shouldHideFooterLoading: true,
                shouldToastNoNewComments: detail.comments.count <= oldCount,
                logReason: "probeFallback"
            )

        case .replyRefresh(let page) where page == loadedPage:
            let replaceResult = replacingCurrentCommentPage(with: detail, page: loadedPage)
            view?.refreshCurrentCommentPage(detail: detail)
            AppLog.info(.postDetail, "回复后详情评论当前页刷新完成: page=\(loadedPage), count=\(detail.comments.count)")
            return CommentPageResponseHandling(
                renderedDetail: replaceResult.detail,
                shouldReplaceLoadedPages: replaceResult.usedFallback,
                shouldHideFooterLoading: false,
                shouldToastNoNewComments: false,
                logReason: "reply"
            )

        default:
            AppLog.warning(.postDetail, "详情评论页请求返回非预期页: requested=\(request.requestedPage), loaded=\(loadedPage)")
            view?.render(detail: detail)
            return CommentPageResponseHandling(
                renderedDetail: detail,
                shouldReplaceLoadedPages: true,
                shouldHideFooterLoading: request.showsFooterLoading,
                shouldToastNoNewComments: false,
                logReason: "unexpectedPage"
            )
        }
    }

    private func replacingCurrentCommentPage(with detail: PostDetail, page: Int) -> CommentPageReplaceResult {
        if let merged = commentPageTracker.replacingCommentPage(
            in: currentDetail,
            with: detail,
            page: page
        ) {
            return CommentPageReplaceResult(detail: merged, usedFallback: false)
        }
        return CommentPageReplaceResult(detail: detail, usedFallback: true)
    }

    func didRequireLogin(message: String) {
        activeCommentPageRequest = nil
        nextCommentPage = nil
        commentPageTracker.reset()
        view?.hideLoadingMoreComments()
        view?.hideLoading()
        view?.renderLoginRequired(message: message)
    }
    
    func didFailLoadPostDetail(error: String) {
        let failedRequest = activeCommentPageRequest
        activeCommentPageRequest = nil
        if failedRequest?.showsFooterLoading == true {
            AppLog.warning(.postDetail, "详情评论加载更多失败: \(error)")
            view?.hideLoadingMoreComments()
            view?.showToast(message: "更多评论加载失败")
            return
        }
        view?.hideLoading()
        if case .replyRefresh = failedRequest {
            return
        } else {
            view?.showError(message: error)
        }
    }

    func didCancelLoadPostDetail() {
        let cancelledRequest = activeCommentPageRequest
        activeCommentPageRequest = nil
        if cancelledRequest?.showsFooterLoading == true {
            view?.hideLoadingMoreComments()
            return
        }
        view?.hideLoading()
    }

    func didSubmitReply(_ response: PostDetailSubmitReplyResponse) {
        AppLog.info(.postDetail, "Presenter 收到回复提交成功: message=\(response.message ?? "nil"), currentPage=\(currentPage), isLastPage=\(currentDetail?.isLastPage == true)")
        isSubmittingReply = false
        AppLog.info(.postDetail, "Presenter 设置回复提交状态=false 前: success")
        view?.setReplySubmitting(false)
        AppLog.info(.postDetail, "Presenter 完成回复提交 UI 收尾前: success")
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
        AppLog.error(.postDetail, "Presenter 收到回复提交失败: \(error)")
        isSubmittingReply = false
        AppLog.info(.postDetail, "Presenter 设置回复提交状态=false 前: failure")
        view?.setReplySubmitting(false)
        view?.showError(message: error)
    }

    private func scheduleCurrentPageRefreshAfterReplySubmission() {
        let page = currentPage
        AppLog.info(.postDetail, "回复提交成功后调度当前页刷新: page=\(page), delayNs=\(Self.replyRefreshDelayNanoseconds)")
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.replyRefreshDelayNanoseconds)
            guard let self else { return }
            guard self.activeCommentPageRequest == nil else {
                AppLog.debug(.postDetail, "忽略回复后评论刷新: 正在加载 page=\(self.activeCommentPageRequest?.requestedPage ?? -1)")
                return
            }
            self.activeCommentPageRequest = .replyRefresh(page: page)
            AppLog.info(.postDetail, "回复提交成功后开始刷新当前页: page=\(page)")
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
