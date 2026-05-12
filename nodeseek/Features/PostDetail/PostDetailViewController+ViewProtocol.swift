//
//  PostDetailViewController+ViewProtocol.swift
//  nodeseek
//
//  Created by Codex on 2026/4/30.
//

import AsyncDisplayKit
import UIKit

private struct DetailCommentRenderSnapshot {
    let cache: [String: [RenderedContentBlock]]
    let renderedIDs: Set<String>
}

extension PostDetailViewController: PostDetailViewProtocol {
    private func updateLoadMoreCommentsFooter() {
        // footer 固定高度 56pt：
        // - 有下一页：保持空白（按钮和 spinner 都隐藏）
        // - 无下一页：显示“加载新评论”
        // - 加载中：spinner 显示（showLoadingMoreComments 已处理）
        guard isViewLoaded else { return }
        guard displayMode == .content else {
            loadMoreCommentsRefreshButton.isHidden = true
            return
        }
        guard loadMoreCommentsIndicator.isAnimating == false else { return }

        if pagination?.nextPage == nil, comments.isEmpty == false {
            loadMoreCommentsRefreshButton.isHidden = false
        } else {
            loadMoreCommentsRefreshButton.isHidden = true
        }
    }

    func showLoading() {
        loginButton.isHidden = true
        replyButton.isHidden = true
        hideLoadingMoreComments()
        if hasRenderedDetailContent {
            loadingIndicator.startAnimating()
        } else {
            loadingIndicator.stopAnimating()
            showLoadingSkeletonIfNeeded()
        }
    }

    func showLoadingMoreComments() {
        loadMoreCommentsRefreshButton.isHidden = true
        loadMoreCommentsIndicator.startAnimating()
    }

    func hideLoadingMoreComments() {
        loadMoreCommentsIndicator.stopAnimating()
        lastBatchFetchRequestedCommentCount = nil
        updateLoadMoreCommentsFooter()
    }

    func hideLoading() {
        loadingIndicator.stopAnimating()
        updateReplyButtonVisibility()
    }

    func showError(message: String) {
        cancelPendingInitialContentReveal()
        hideLoadingSkeleton()
        let alert = UIAlertController(title: "错误", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    func showToast(message: String) {
        toastHideWorkItem?.cancel()
        toastLabel.text = message
        toastContainerView.isHidden = false
        toastContainerView.alpha = 0
        toastContainerView.transform = CGAffineTransform(translationX: 0, y: 8)

        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            self.toastContainerView.alpha = 1
            self.toastContainerView.transform = .identity
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            UIView.animate(
                withDuration: 0.2,
                delay: 0,
                options: [.curveEaseIn, .allowUserInteraction]
            ) {
                self.toastContainerView.alpha = 0
                self.toastContainerView.transform = CGAffineTransform(translationX: 0, y: 8)
            } completion: { _ in
                self.toastContainerView.isHidden = true
                self.toastContainerView.transform = .identity
            }
        }
        toastHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: workItem)
    }

    func setFavoriteSubmitting(_ isSubmitting: Bool) {
        guard isSubmitting else { return }
        showToast(message: "正在处理")
    }

    func render(detail: PostDetail) {
        title = nil
        loginButton.isHidden = true
        showsReplyEntry = detail.isRestricted == false
        let targetPage = max(1, detail.page)
        if shouldPrepareInitialContentReveal {
            prepareInitialContentReveal(for: detail, targetPage: targetPage)
            return
        }
        cancelPendingInitialContentReveal()
        let shouldScrollToTop = false
        let existingHeaderContent = currentHeaderContent
        let existingRenderedContent = headerRenderedContent
        var existingComments: [String: Comment] = [:]
        for comment in comments {
            existingComments[comment.id] = comment
        }
        let existingCommentRenderedCache = commentRenderedCache
        let existingRenderedCommentIDs = renderedCommentIDs
        let isSamePageRefresh = hasRenderedDetailContent
            && targetPage == currentPage
            && existingHeaderContent?.postID == detail.id
        let nextHeaderContent = PostDetailHeaderContent(detail: detail)
        let canReuseHeaderRender = isSamePageRefresh
            && existingHeaderContent?.contentHTML == nextHeaderContent.contentHTML
            && existingRenderedContent != nil
        let shouldPreserveHeader = hasRenderedDetailContent
            && targetPage != 1
            && existingHeaderContent?.postID == detail.id
            && existingHeaderContent?.contentHTML.isEmpty == false
        renderGeneration += 1
        let headerContent = shouldPreserveHeader ? existingHeaderContent! : nextHeaderContent
        let renderedHeaderContent = (shouldPreserveHeader || canReuseHeaderRender) ? existingRenderedContent : nil
        let commentRenderSnapshot: DetailCommentRenderSnapshot
        if isSamePageRefresh {
            commentRenderSnapshot = preservedRenderedCommentSnapshot(
                previousComments: existingComments,
                previousCache: existingCommentRenderedCache,
                previousRenderedIDs: existingRenderedCommentIDs,
                nextComments: detail.comments
            )
        } else {
            commentRenderSnapshot = DetailCommentRenderSnapshot(cache: [:], renderedIDs: [])
        }
        let nextPagination = detail.pagination
            ?? (shouldPreserveHeader ? fallbackPagination(from: pagination, currentPage: detail.page) : nil)

        applyDetailContent(
            targetPage: targetPage,
            headerContent: headerContent,
            renderedHeaderContent: renderedHeaderContent,
            pagination: nextPagination,
            comments: detail.comments,
            commentRenderSnapshot: commentRenderSnapshot,
            shouldScrollToTop: shouldScrollToTop,
            shouldScheduleMissingRender: true
        )
    }

    func appendCommentPage(detail: PostDetail) {
        guard hasRenderedDetailContent else {
            render(detail: detail)
            return
        }

        let oldCommentCount = comments.count
        let hasHeader = currentHeaderContent != nil
        let commentRowOffset = hasHeader ? 2 : 0
        currentPage = max(currentPage, detail.page)
        pagination = detail.pagination
        comments.append(contentsOf: detail.comments)
        loadedCommentPageRanges[detail.page] = oldCommentCount..<comments.count
        var insertedRows: [IndexPath] = []
        if hasHeader, oldCommentCount == 0, comments.isEmpty == false {
            // 初次有评论时，需要补上 header 与评论之间的分割行。
            insertedRows.append(IndexPath(row: 1, section: 0))
        }
        insertedRows.append(contentsOf: (oldCommentCount..<comments.count).map { commentIndex in
            IndexPath(row: commentRowOffset + commentIndex, section: 0)
        })

        if insertedRows.isEmpty {
            return
        }

        tableNode.performBatch(animated: false, updates: { [weak self] in
            self?.tableNode.insertRows(at: insertedRows, with: .none)
        })
        AppLog.debug(.postDetail, "详情评论局部插入完成: inserted=\(insertedRows.count), totalComments=\(comments.count)")
        preheatCommentRender(for: detail.comments)
        updateLoadMoreCommentsFooter()
        updateReplyButtonVisibility()
    }

    func refreshCurrentCommentPage(detail: PostDetail) {
        guard hasRenderedDetailContent else {
            render(detail: detail)
            return
        }
        guard let oldRange = loadedCommentPageRanges[detail.page],
              oldRange.lowerBound >= 0,
              oldRange.upperBound <= comments.count else {
            render(detail: detail)
            return
        }

        let oldComments = Array(comments[oldRange])
        let newComments = detail.comments
        let commonCount = min(oldComments.count, newComments.count)
        let hasHeader = currentHeaderContent != nil
        let oldTotalCount = comments.count
        let commentRowOffset = hasHeader ? 2 : 0
        let reloadRows = (0..<commonCount).compactMap { offset -> IndexPath? in
            let oldComment = oldComments[offset]
            let newComment = newComments[offset]
            guard oldComment != newComment else { return nil }
            comments[oldRange.lowerBound + offset] = newComments[offset]
            if oldComment.contentHTML != newComment.contentHTML {
                commentRenderedCache[newComment.id] = nil
                renderedCommentIDs.remove(newComment.id)
                commentRenderInFlight.remove(newComment.id)
            }
            return IndexPath(row: commentRowOffset + oldRange.lowerBound + offset, section: 0)
        }

        var deleteRows: [IndexPath] = []
        var insertRows: [IndexPath] = []
        if oldComments.count > newComments.count {
            deleteRows = (newComments.count..<oldComments.count).map { offset in
                IndexPath(row: commentRowOffset + oldRange.lowerBound + offset, section: 0)
            }
            for comment in oldComments[newComments.count..<oldComments.count] {
                commentRenderedCache[comment.id] = nil
                renderedCommentIDs.remove(comment.id)
                commentRenderInFlight.remove(comment.id)
            }
            comments.removeSubrange((oldRange.lowerBound + newComments.count)..<oldRange.upperBound)
        } else if newComments.count > oldComments.count {
            let inserted = Array(newComments[oldComments.count..<newComments.count])
            comments.insert(contentsOf: inserted, at: oldRange.upperBound)
            insertRows = (oldComments.count..<newComments.count).map { offset in
                IndexPath(row: commentRowOffset + oldRange.lowerBound + offset, section: 0)
            }
        }

        loadedCommentPageRanges[detail.page] = oldRange.lowerBound..<(oldRange.lowerBound + newComments.count)
        shiftLoadedCommentPageRanges(after: detail.page, delta: newComments.count - oldComments.count)
        pagination = detail.pagination
        currentPage = max(currentPage, detail.page)

        if hasHeader, oldTotalCount > 0, comments.isEmpty {
            deleteRows.append(IndexPath(row: 1, section: 0))
        } else if hasHeader, oldTotalCount == 0, comments.isEmpty == false {
            insertRows.insert(IndexPath(row: 1, section: 0), at: 0)
        }

        tableNode.performBatch(animated: false, updates: { [weak self] in
            guard let self else { return }
            if deleteRows.isEmpty == false {
                self.tableNode.deleteRows(at: deleteRows, with: .none)
            }
            if insertRows.isEmpty == false {
                self.tableNode.insertRows(at: insertRows, with: .none)
            }
            if reloadRows.isEmpty == false {
                self.tableNode.reloadRows(at: reloadRows, with: .none)
            }
        })
        AppLog.debug(.postDetail, "详情评论当前页局部刷新完成: page=\(detail.page), reload=\(reloadRows.count), insert=\(insertRows.count), delete=\(deleteRows.count), totalComments=\(comments.count)")
        preheatCommentRender(for: newComments)
        updateLoadMoreCommentsFooter()
        updateReplyButtonVisibility()
    }

    func updatePostBody(detail: PostDetail) {
        guard hasRenderedDetailContent else {
            render(detail: detail)
            return
        }
        let nextContent = PostDetailHeaderContent(detail: detail)
        guard let previousContent = currentHeaderContent else {
            configureHeader(nextContent, renderedContent: headerRenderedContent)
            scheduleHeaderReload()
            return
        }

        if Self.isHeaderLayoutEquivalent(previousContent, nextContent) {
            currentHeaderContent = nextContent
            if let row = detailRows.firstIndex(where: { if case .header = $0 { return true }; return false }),
               let node = tableNode.nodeForRow(at: IndexPath(row: row, section: 0)) as? PostBodyCellNode {
                node.updateLikeReaction(count: nextContent.likeCount, isClicked: nextContent.isLikeClicked)
                node.updateChickenLegReaction(count: nextContent.chickenLegCount, isClicked: nextContent.isChickenLegClicked)
                node.updateOpposeReaction(count: nextContent.opposeCount, isClicked: nextContent.isOpposeClicked)
                node.updateFavoriteReaction(count: nextContent.favoriteCount, isCollected: nextContent.isFavoriteCollected)
            }
            return
        }

        configureHeader(nextContent, renderedContent: headerRenderedContent)
        scheduleHeaderReload()
    }

    func updateCommentLike(commentID: String, count: Int?, isClicked: Bool) {
        guard let commentIndex = comments.firstIndex(where: { $0.id == commentID }) else { return }
        comments[commentIndex] = comments[commentIndex].updatingLikeReaction(count: count, isClicked: isClicked)

        guard let row = detailRows.firstIndex(where: {
            if case .comment(let index) = $0 {
                return index == commentIndex
            }
            return false
        }) else { return }

        let indexPath = IndexPath(row: row, section: 0)
        if let node = tableNode.nodeForRow(at: indexPath) as? CommentCellNode {
            node.updateLikeReaction(count: count, isClicked: isClicked)
            return
        }

        scheduleRowsReload([indexPath])
    }

    func updateCommentChickenLeg(commentID: String, count: Int?, isClicked: Bool) {
        guard let commentIndex = comments.firstIndex(where: { $0.id == commentID }) else { return }
        comments[commentIndex] = comments[commentIndex].updatingChickenLegReaction(count: count, isClicked: isClicked)

        guard let row = detailRows.firstIndex(where: {
            if case .comment(let index) = $0 {
                return index == commentIndex
            }
            return false
        }) else { return }

        let indexPath = IndexPath(row: row, section: 0)
        if let node = tableNode.nodeForRow(at: indexPath) as? CommentCellNode {
            node.updateChickenLegReaction(count: count, isClicked: isClicked)
            return
        }

        scheduleRowsReload([indexPath])
    }

    func updateCommentOppose(commentID: String, count: Int?, isClicked: Bool) {
        guard let commentIndex = comments.firstIndex(where: { $0.id == commentID }) else { return }
        comments[commentIndex] = comments[commentIndex].updatingOpposeReaction(count: count, isClicked: isClicked)

        guard let row = detailRows.firstIndex(where: {
            if case .comment(let index) = $0 {
                return index == commentIndex
            }
            return false
        }) else { return }

        let indexPath = IndexPath(row: row, section: 0)
        if let node = tableNode.nodeForRow(at: indexPath) as? CommentCellNode {
            node.updateOpposeReaction(count: count, isClicked: isClicked)
            return
        }

        scheduleRowsReload([indexPath])
    }

    private static func isHeaderLayoutEquivalent(
        _ lhs: PostDetailHeaderContent,
        _ rhs: PostDetailHeaderContent
    ) -> Bool {
        lhs.postID == rhs.postID
            && lhs.title == rhs.title
            && lhs.requiredReadingLevel == rhs.requiredReadingLevel
            && lhs.authorName == rhs.authorName
            && lhs.avatarURL == rhs.avatarURL
            && lhs.authorProfileURL == rhs.authorProfileURL
            && lhs.metadataText == rhs.metadataText
            && lhs.contentHTML == rhs.contentHTML
    }

    private var shouldPrepareInitialContentReveal: Bool {
        hasRenderedDetailContent == false && displayMode == .skeleton
    }

    private func cancelPendingInitialContentReveal() {
        pendingInitialContentRevealGeneration = nil
        initialContentRevealWorkItem?.cancel()
        initialContentRevealWorkItem = nil
    }

    private func prepareInitialContentReveal(for detail: PostDetail, targetPage: Int) {
        renderGeneration += 1
        let generation = renderGeneration
        pendingInitialContentRevealGeneration = generation
        initialContentRevealWorkItem?.cancel()
        tableReloadWorkItem?.cancel()
        pendingReloadIndexPaths.removeAll()

        let headerContent = PostDetailHeaderContent(detail: detail)
        let baseURL = baseURL
        let headerWidth = availableHeaderContentWidth
        let commentWidth = availableCommentContentWidth

        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            self?.revealInitialContent(
                detail: detail,
                targetPage: targetPage,
                headerContent: headerContent,
                renderedHeaderContent: nil,
                renderedCommentCache: [:],
                renderedCommentIDs: [],
                generation: generation,
                shouldScheduleMissingRender: true
            )
        }
        initialContentRevealWorkItem = timeoutWorkItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + initialContentRevealTimeout,
            execute: timeoutWorkItem
        )

        renderQueue.async { [weak self] in
            let renderedHeaderContent = Self.makeRenderedContent(
                html: headerContent.contentHTML,
                baseURL: baseURL,
                maxImageWidth: headerWidth
            )
            var renderedCommentCache: [String: [RenderedContentBlock]] = [:]
            var renderedCommentIDs = Set<String>()

            for comment in detail.comments {
                let renderedContent = Self.makeRenderedContent(
                    html: comment.contentHTML,
                    baseURL: baseURL,
                    maxImageWidth: commentWidth
                )
                renderedCommentIDs.insert(comment.id)
                if let renderedContent {
                    renderedCommentCache[comment.id] = renderedContent
                }
            }

            DispatchQueue.main.async {
                self?.revealInitialContent(
                    detail: detail,
                    targetPage: targetPage,
                    headerContent: headerContent,
                    renderedHeaderContent: renderedHeaderContent,
                    renderedCommentCache: renderedCommentCache,
                    renderedCommentIDs: renderedCommentIDs,
                    generation: generation,
                    shouldScheduleMissingRender: false
                )
            }
        }
    }

    private func revealInitialContent(
        detail: PostDetail,
        targetPage: Int,
        headerContent: PostDetailHeaderContent,
        renderedHeaderContent: [RenderedContentBlock]?,
        renderedCommentCache: [String: [RenderedContentBlock]],
        renderedCommentIDs: Set<String>,
        generation: Int,
        shouldScheduleMissingRender: Bool
    ) {
        guard pendingInitialContentRevealGeneration == generation else { return }
        pendingInitialContentRevealGeneration = nil
        initialContentRevealWorkItem?.cancel()
        initialContentRevealWorkItem = nil

        applyDetailContent(
            targetPage: targetPage,
            headerContent: headerContent,
            renderedHeaderContent: renderedHeaderContent,
            pagination: detail.pagination,
            comments: detail.comments,
            commentRenderSnapshot: DetailCommentRenderSnapshot(
                cache: renderedCommentCache,
                renderedIDs: renderedCommentIDs
            ),
            shouldScrollToTop: false,
            shouldScheduleMissingRender: shouldScheduleMissingRender
        )
    }

    private func applyDetailContent(
        targetPage: Int,
        headerContent: PostDetailHeaderContent,
        renderedHeaderContent: [RenderedContentBlock]?,
        pagination: PostDetailPagination?,
        comments: [Comment],
        commentRenderSnapshot: DetailCommentRenderSnapshot,
        shouldScrollToTop: Bool,
        shouldScheduleMissingRender: Bool
    ) {
        currentPage = targetPage
        hasRenderedDetailContent = true
        displayMode = .content
        configureHeader(headerContent, renderedContent: renderedHeaderContent)
        self.pagination = pagination
        self.comments = comments
        loadedCommentPageRanges = [targetPage: 0..<comments.count]
        commentRenderedCache = commentRenderSnapshot.cache
        renderedCommentIDs = commentRenderSnapshot.renderedIDs
        commentRenderInFlight.removeAll(keepingCapacity: true)
        reloadTableData()
        if shouldScrollToTop {
            let targetRow = pageCompletionScrollRow()
            #if DEBUG
            pendingScrollToRow = targetRow
            #endif
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.tableNode.scrollToRow(
                    at: IndexPath(row: targetRow, section: 0),
                    at: .top,
                    animated: false
                )
            }
        }

        if shouldScheduleMissingRender {
            if renderedHeaderContent == nil {
                scheduleHeaderRender(for: headerContent)
            }
            preheatCommentRender(for: comments)
        }
        updateLoadMoreCommentsFooter()
        updateReplyButtonVisibility()
        consumeInitialAnchorIfNeeded()
    }

    private func preservedRenderedCommentSnapshot(
        previousComments: [String: Comment],
        previousCache: [String: [RenderedContentBlock]],
        previousRenderedIDs: Set<String>,
        nextComments: [Comment]
    ) -> DetailCommentRenderSnapshot {
        var nextCache: [String: [RenderedContentBlock]] = [:]
        var nextRenderedIDs: Set<String> = []

        for comment in nextComments {
            guard previousComments[comment.id]?.contentHTML == comment.contentHTML,
                  previousRenderedIDs.contains(comment.id) else {
                continue
            }
            nextRenderedIDs.insert(comment.id)
            if let cached = previousCache[comment.id] {
                nextCache[comment.id] = cached
            }
        }

        return DetailCommentRenderSnapshot(cache: nextCache, renderedIDs: nextRenderedIDs)
    }

    func setReplySubmitting(_ isSubmitting: Bool) {
        let startedAt = Date()
        AppLog.info(.postDetail, "View 设置回复发送按钮 loading 开始: isSubmitting=\(isSubmitting), oldButtonEnabled=\(inlineReplySendButton.isEnabled), oldInteraction=\(inlineReplySendButton.isUserInteractionEnabled), oldEditorEditable=\(replyTextView.isEditable)")
        var configuration = inlineReplySendButton.configuration ?? UIButton.Configuration.plain()
        configuration.showsActivityIndicator = isSubmitting
        configuration.image = nil
        configuration.title = isSubmitting ? nil : "发送"
        configuration.baseForegroundColor = PostDetailReplySendButtonStyle.foregroundColor
        configuration.background.backgroundColor = PostDetailReplySendButtonStyle.backgroundColor
        configuration.titleTextAttributesTransformer = PostDetailReplySendButtonStyle.titleAttributesTransformer
        configuration.activityIndicatorColorTransformer = PostDetailReplySendButtonStyle.activityIndicatorColorTransformer
        inlineReplySendButton.configuration = configuration
        inlineReplySendButton.accessibilityLabel = isSubmitting ? "正在发送评论" : "发送"
        replyTextView.isEditable = !isSubmitting
        inlineReplySendButton.isEnabled = true
        inlineReplySendButton.isUserInteractionEnabled = !isSubmitting
        setReplyContextControlsEnabled(!isSubmitting)
        inlineReplySendButton.alpha = 1
        AppLog.info(.postDetail, "View 设置回复发送按钮 loading 完成: isSubmitting=\(isSubmitting), showsActivityIndicator=\(configuration.showsActivityIndicator), buttonEnabled=\(inlineReplySendButton.isEnabled), interaction=\(inlineReplySendButton.isUserInteractionEnabled), editorEditable=\(replyTextView.isEditable), elapsedMs=\(AppLog.elapsedMilliseconds(since: startedAt))")
    }

    func renderLoginRequired(message: String) {
        cancelPendingInitialContentReveal()
        title = nil
        loginButton.isHidden = false
        showsReplyEntry = false
        replyComposerMode = .plain
        updateReplyContext(for: .plain)
        dismissReplyEditor()
        updateReplyButtonVisibility()
        renderGeneration += 1
        hasRenderedDetailContent = true
        displayMode = .content
        let existing = currentHeaderContent
        headerRenderedContent = nil
        let headerContent = PostDetailHeaderContent(
            postID: existing?.postID ?? "login-required",
            title: existing?.title ?? "需要登录",
            authorName: existing?.authorName ?? "NodeSeek",
            avatarURL: existing?.avatarURL,
            metadataText: existing?.metadataText,
            contentHTML: message
        )
        configureHeader(headerContent, renderedContent: nil)
        pagination = nil
        comments = []
        commentRenderedCache.removeAll(keepingCapacity: true)
        renderedCommentIDs.removeAll(keepingCapacity: true)
        commentRenderInFlight.removeAll(keepingCapacity: true)
        reloadTableData()
        scheduleHeaderRender(for: headerContent)
        updateLoadMoreCommentsFooter()
    }

    func finishReplySubmission() {
        replyTextView.text = nil
        replyComposerMode = .plain
        updateReplyContext(for: .plain)
        dismissReplyEditor()
    }
}

private extension PostDetailViewController {
    func shiftLoadedCommentPageRanges(after page: Int, delta: Int) {
        guard delta != 0 else { return }
        for key in loadedCommentPageRanges.keys where key > page {
            guard let range = loadedCommentPageRanges[key] else { continue }
            loadedCommentPageRanges[key] = (range.lowerBound + delta)..<(range.upperBound + delta)
        }
    }
}

extension PostDetailViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer is UITapGestureRecognizer else { return true }
        guard let touchedView = touch.view else { return true }
        return touchedView.isDescendant(of: replyEditorContainer) == false
    }
}

#if DEBUG
extension PostDetailViewController {
    func showReplyEditorForTesting(action: String, authorName: String, floorText: String?) {
        showsReplyEntry = true
        let comment = Comment(
            id: "reply-editor-test-comment",
            authorName: authorName,
            avatarURL: nil,
            floorText: floorText,
            createdAtText: nil,
            contentHTML: ""
        )
        replyComposerMode = action == "引用" ? .quote([comment]) : .reply([comment])
        updateReplyContext(for: replyComposerMode)
        replyEditorBackdrop.isHidden = false
        replyEditorContainer.isHidden = false
        view.bringSubviewToFront(replyEditorBackdrop)
        view.bringSubviewToFront(replyEditorContainer)
    }
}
#endif
