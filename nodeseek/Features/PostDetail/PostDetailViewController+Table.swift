//
//  PostDetailViewController+Table.swift
//  nodeseek
//
//  Created by Codex on 2026/4/30.
//

import UIKit

extension PostDetailViewController {
    var showsInlineReplyPagination: Bool {
        displayMode == .content && totalCommentPages > 1 && authorFilter == nil
            && ReplyPaginationDisplaySettings.shared.showsInlineBar
    }

    var detailRows: [DetailRow] {
        var rows: [DetailRow] = []
        if currentHeaderContent != nil {
            rows.append(.header)
            if shouldShowInitialPageHint {
                rows.append(.entryHint)
            }
            if authorFilter != nil, displayMode == .content {
                rows.append(.authorFilterBanner)
            } else if showsInlineReplyPagination {
                rows.append(.replyPagination)
            } else if displayMode == .pageSkeleton || !comments.isEmpty {
                rows.append(.postRepliesDivider)
            }
        }
        if displayMode == .pageSkeleton {
            rows.append(contentsOf: (0..<skeletonCommentRowCount).map(DetailRow.skeletonComment))
        } else if let authorFilter {
            rows.append(contentsOf: comments.indices.filter { authorFilter.matches(comments[$0]) }.map(DetailRow.comment))
        } else {
            rows.append(contentsOf: comments.indices.map(DetailRow.comment))
        }
        return rows
    }

    func pageCompletionScrollRow() -> Int {
        let rows = detailRows
        if let commentRow = rows.firstIndex(where: { row in
            if case .comment = row {
                return true
            }
            return false
        }) {
            return commentRow
        }
        return rows.firstIndex(where: { if case .header = $0 { return true }; return false }) ?? 0
    }
}

extension PostDetailViewController {
    func handlePostLikeTap(_ header: PostDetailHeaderContent) {
        confirmActionIfNeeded(isAlreadyApplied: header.isLikeClicked, context: .postLike) { [weak self] in
            self?.presenter.didTapPostLike()
        }
    }

    func handleCommentLikeTap(_ comment: Comment) {
        confirmActionIfNeeded(isAlreadyApplied: comment.isLikeClicked, context: .commentLike) { [weak self] in
            self?.presenter.didTapCommentLike(comment)
        }
    }

    func handlePostChickenLegTap(_ header: PostDetailHeaderContent) {
        confirmActionIfNeeded(isAlreadyApplied: header.isChickenLegClicked, context: .postChickenLeg) { [weak self] in
            self?.presenter.didTapPostChickenLeg()
        }
    }

    func handleCommentChickenLegTap(_ comment: Comment) {
        confirmActionIfNeeded(isAlreadyApplied: comment.isChickenLegClicked, context: .commentChickenLeg) { [weak self] in
            self?.presenter.didTapCommentChickenLeg(comment)
        }
    }

    func handlePostOpposeTap(_ header: PostDetailHeaderContent) {
        confirmActionIfNeeded(isAlreadyApplied: header.isOpposeClicked, context: .postOppose) { [weak self] in
            self?.presenter.didTapPostOppose()
        }
    }

    func handleCommentOpposeTap(_ comment: Comment) {
        confirmActionIfNeeded(isAlreadyApplied: comment.isOpposeClicked, context: .commentOppose) { [weak self] in
            self?.presenter.didTapCommentOppose(comment)
        }
    }

    private func confirmActionIfNeeded(
        isAlreadyApplied: Bool,
        context: PostDetailActionConfirmationContext,
        onConfirm: @escaping @MainActor () -> Void
    ) {
        // 与回复、引用一致：游客先提示登录，登录后再继续原操作。
        ensureNodeSeekLoggedIn(context: "reaction", allowCachedLogin: true) { [weak self] in
            guard let self else { return }
            guard isAlreadyApplied == false else {
                onConfirm()
                return
            }
            actionConfirmationPresenter(self, context, onConfirm)
        }
    }

    func handleFavoriteTap() {
        ensureNodeSeekLoggedIn(context: "favorite", allowCachedLogin: true) { [weak self] in
            self?.presenter.didTapFavorite()
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateNavigationAuthorVisibility(contentOffsetY: scrollView.contentOffset.y, animated: true)
        // 只响应手指拖动和惯性滚动，代码触发的滚动不浮出页码。
        if scrollView.isDragging || scrollView.isDecelerating {
            showPageIndicatorWhileScrolling()
            updateReplyBarForUserScroll(scrollView)
        } else {
            replyBarScrollAnchorY = scrollView.contentOffset.y
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if decelerate == false {
            schedulePageIndicatorHide()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        schedulePageIndicatorHide()
    }
}
