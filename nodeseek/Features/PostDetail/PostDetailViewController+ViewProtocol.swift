//
//  PostDetailViewController+ViewProtocol.swift
//  nodeseek
//
//  Created by Codex on 2026/4/30.
//

import AsyncDisplayKit
import UIKit

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

    func render(detail: PostDetail) {
        title = "详情"
        loginButton.isHidden = true
        showsReplyEntry = true
        let shouldScrollToTop = hasRenderedDetailContent && detail.page != currentPage
        let existingHeaderContent = currentHeaderContent
        let existingRenderedContent = headerRenderedContent
        let shouldPreserveHeader = hasRenderedDetailContent
            && detail.page != 1
            && existingHeaderContent?.postID == detail.id
            && existingHeaderContent?.contentHTML.isEmpty == false
        currentPage = max(1, detail.page)
        pageLoadingTargetPage = nil
        renderGeneration += 1
        hasRenderedDetailContent = true
        displayMode = .content
        let headerContent = shouldPreserveHeader ? existingHeaderContent! : PostDetailHeaderContent(detail: detail)
        configureHeader(headerContent, renderedContent: shouldPreserveHeader ? existingRenderedContent : nil)
        pagination = detail.pagination ?? (shouldPreserveHeader ? fallbackPagination(from: pagination, currentPage: detail.page) : nil)
        comments = detail.comments
        commentRenderedCache.removeAll(keepingCapacity: true)
        renderedCommentIDs.removeAll(keepingCapacity: true)
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
        if shouldPreserveHeader == false || existingRenderedContent == nil {
            scheduleHeaderRender(for: headerContent)
        }
        preheatCommentRender(for: comments)
        updateReplyButtonVisibility()
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
        title = "详情"
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
