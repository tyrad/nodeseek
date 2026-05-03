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
    func showLoading() {
        loginButton.isHidden = true
        replyButton.isHidden = true
        if hasRenderedDetailContent {
            loadingIndicator.startAnimating()
        } else {
            loadingIndicator.stopAnimating()
            showLoadingSkeletonIfNeeded()
        }
    }

    func showPageLoading() {
        loginButton.isHidden = true
        loadingIndicator.stopAnimating()
        guard hasRenderedDetailContent, currentHeaderContent != nil else {
            showLoading()
            return
        }
        displayMode = .pageSkeleton
        updatePageScrubber(isLoading: true, currentPageOverride: pageLoadingTargetPage)
        reloadTableData()
    }

    func hideLoading() {
        loadingIndicator.stopAnimating()
        updateReplyButtonVisibility()
    }

    func showError(message: String) {
        cancelPendingInitialContentReveal()
        hideLoadingSkeleton()
        let alert = UIAlertController(title: "错误", message: message, preferredStyle: .alert)
        pageLoadingTargetPage = nil
        updatePageScrubber(isLoading: false)
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
        showsReplyEntry = true
        let targetPage = max(1, detail.page)
        if shouldPrepareInitialContentReveal {
            prepareInitialContentReveal(for: detail, targetPage: targetPage)
            return
        }
        cancelPendingInitialContentReveal()
        let shouldScrollToTop = hasRenderedDetailContent && targetPage != currentPage
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
                node.updateFavoriteReaction(count: nextContent.favoriteCount, isCollected: nextContent.isFavoriteCollected)
            }
            return
        }

        configureHeader(nextContent, renderedContent: headerRenderedContent)
        scheduleHeaderReload()
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
        pageLoadingTargetPage = nil
        hasRenderedDetailContent = true
        displayMode = .content
        configureHeader(headerContent, renderedContent: renderedHeaderContent)
        self.pagination = pagination
        self.comments = comments
        commentRenderedCache = commentRenderSnapshot.cache
        renderedCommentIDs = commentRenderSnapshot.renderedIDs
        commentRenderInFlight.removeAll(keepingCapacity: true)
        updatePageScrubber(isLoading: false)
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
        updateReplyButtonVisibility()
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
        var configuration = inlineReplySendButton.configuration ?? UIButton.Configuration.plain()
        configuration.showsActivityIndicator = isSubmitting
        configuration.image = isSubmitting ? nil : UIImage(systemName: "arrow.up")
        configuration.baseForegroundColor = .label
        configuration.background.backgroundColor = .clear
        inlineReplySendButton.configuration = configuration
        inlineReplySendButton.accessibilityLabel = isSubmitting ? "正在发送评论" : "发送"
        replyTextView.isEditable = !isSubmitting
        inlineReplySendButton.isEnabled = !isSubmitting
        replyContextCloseButton.isEnabled = !isSubmitting
        inlineReplySendButton.alpha = 1
    }

    func renderLoginRequired(message: String) {
        cancelPendingInitialContentReveal()
        title = nil
        loginButton.isHidden = false
        showsReplyEntry = false
        replyComposerMode = .plain
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
        updatePageScrubber(isLoading: false)
        reloadTableData()
        scheduleHeaderRender(for: headerContent)
    }

    func finishReplySubmission() {
        replyTextView.text = nil
        replyComposerMode = .plain
        dismissReplyEditor()
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
        replyComposerMode = action == "引用" ? .quote(comment) : .reply(comment)
        updateReplyContext(for: replyComposerMode)
        replyEditorBackdrop.isHidden = false
        replyEditorContainer.isHidden = false
        view.bringSubviewToFront(replyEditorBackdrop)
        view.bringSubviewToFront(replyEditorContainer)
    }
}
#endif
