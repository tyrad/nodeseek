//
//  PostDetailViewController+ViewProtocol.swift
//  nodeseek
//
//  Created by Codex on 2026/4/30.
//

import UIKit

extension PostDetailViewController: PostDetailViewProtocol {
    func updateLoadMoreCommentsFooter() {
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
        collectionList.didFinishLoadingMore()
        updateLoadMoreCommentsFooter()
    }

    func hideLoading() {
        // 跳页请求结束却没渲染（失败或取消）时清掉待跳标记，否则续页一直被拦住。
        pendingPageJumpScroll = false
        loadingIndicator.stopAnimating()
        collectionList.scheduleBatchFetchCheck()
        updateReplyButtonVisibility()
    }

    func showError(message: String) {
        pendingPageJumpScroll = false
        hideLoadingSkeleton()
        let alert = UIAlertController(title: "错误", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    func showToast(message: String) {
        presentToast(message: message, style: .success)
    }

    func showProgressToast(message: String) {
        presentToast(message: message, style: .progress)
    }

    func showFailureToast(message: String) {
        presentToast(message: message, style: .failure)
    }

    /// 图标与全局 BottomToast 一致：成功绿勾、失败橙色感叹号、进行中不显示图标。
    private func presentToast(message: String, style: BottomToast.Style) {
        toastHideWorkItem?.cancel()
        toastLabel.text = message
        // 三种提示共用一个图标视图，每次都要重设图标和颜色
        let showsIcon = style != .progress
        if showsIcon {
            toastIconView.image = style.image
            toastIconView.tintColor = style.tintColor
        }
        // 收起图标后左右留白与右侧一致
        toastIconView.isHidden = !showsIcon
        toastIconWidthConstraint.constant = showsIcon ? 18 : 0
        toastLabelLeadingConstraint.constant = showsIcon ? 8 : 2
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
        showProgressToast(message: "正在处理")
    }

    func render(detail: PostDetail) {
        title = nil
        loginButton.isHidden = true
        showsReplyEntry = detail.isRestricted == false
        if currentHeaderContent?.postID != detail.id || detail.isRestricted { authorFilter = nil }
        resetAuthorFilterAutoLoad()
        // 后续页解析出的正文可能是该页第一楼，已有主楼时沿用，避免把回复当成主楼。
        let previousHeader = detail.page > 1 && !detail.isRestricted && currentHeaderContent?.postID == detail.id
            ? currentHeaderContent : nil
        if (previousHeader?.contentHTML ?? "").isEmpty {
            collectionList.headerSource = .init(post: detail)
            configureHeader(.init(detail: detail, fallback: previousHeader))
        }
        if displayMode == .skeleton { collectionList.coverUntilSettled(timeout: initialContentRevealTimeout) }
        displayMode = .content
        hasRenderedDetailContent = true
        currentPage = max(1, detail.page)
        comments = detail.comments
        loadedCommentPageRanges = [currentPage: 0..<comments.count]
        pagination = detail.pagination
        collectionList.resetPagination()
        collectionList.reload()
        updateLoadMoreCommentsFooter()
        updateReplyButtonVisibility()
        if pendingPageJumpScroll {
            pendingPageJumpScroll = false
            collectionList.scroll(to: currentPage == 1 ? 0 : pageCompletionScrollRow(), position: .top)
        }
        consumeInitialAnchorIfNeeded()
        if authorFilter != nil { scheduleAuthorFilterAutoLoadIfNeeded(newMatchCount: authorFilterMatchedCount) }
    }

    func appendCommentPage(detail: PostDetail) {
        guard hasRenderedDetailContent, !detail.isRestricted else {
            render(detail: detail)
            return
        }
        if loadedCommentPageRanges[detail.page] != nil {
            refreshCurrentCommentPage(detail: detail)
            return
        }
        let oldCommentCount = comments.count
        let oldAuthorFilterBannerText = authorFilterBannerText
        currentPage = max(currentPage, detail.page)
        pagination = detail.pagination
        comments.append(contentsOf: detail.comments)
        loadedCommentPageRanges[detail.page] = oldCommentCount..<comments.count
        collectionList.appendComments(in: oldCommentCount..<comments.count, pageNumber: detail.page,
                                      bannerChanged: oldAuthorFilterBannerText != authorFilterBannerText)
        updateLoadMoreCommentsFooter()
        updateReplyButtonVisibility()
        if let authorFilter { scheduleAuthorFilterAutoLoadIfNeeded(newMatchCount: detail.comments.filter(authorFilter.matches).count) }
    }

    func refreshCurrentCommentPage(detail: PostDetail) {
        guard hasRenderedDetailContent, !detail.isRestricted,
              let oldRange = loadedCommentPageRanges[detail.page],
              oldRange.lowerBound >= 0,
              oldRange.upperBound <= comments.count else {
            render(detail: detail)
            return
        }
        let delta = detail.comments.count - oldRange.count
        let previous = Dictionary(comments[oldRange].map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        comments.replaceSubrange(oldRange, with: detail.comments)
        loadedCommentPageRanges[detail.page] = oldRange.lowerBound..<(oldRange.lowerBound + detail.comments.count)
        shiftLoadedCommentPageRanges(after: detail.page, delta: delta)
        if detail.page == currentPage { pagination = detail.pagination }
        // 只重配内容有变化的楼层：全量重配会清空正文和签名再异步回填，高度先缩后涨，把底部位置顶回去。
        collectionList.reload(refresh: false)
        for comment in detail.comments where previous[comment.id].map({ $0 != comment }) == true {
            collectionList.refresh(commentID: comment.id)
        }
        updateLoadMoreCommentsFooter()
    }

    func updateAuthorRiskWarning(postID: String, isVisible: Bool) {
        if let currentHeaderContent, currentHeaderContent.postID != postID { return }
        let wasVisible = authorRiskWarningPostID == postID
        authorRiskWarningPostID = isVisible ? postID : nil
        guard wasVisible != isVisible, isViewLoaded, displayMode == .content else { return }
        collectionList.refreshHeader()
    }

    func updatePostBody(detail: PostDetail) {
        guard hasRenderedDetailContent else {
            render(detail: detail)
            return
        }
        collectionList.headerSource = .init(post: detail)
        configureHeader(PostDetailHeaderContent(detail: detail))
        collectionList.refreshHeader()
    }

    func updateCommentLike(commentID: String, count: Int?, isClicked: Bool) {
        for index in comments.indices where comments[index].id == commentID {
            comments[index] = comments[index].updatingLikeReaction(count: count, isClicked: isClicked)
        }
        collectionList.refresh(commentID: commentID)
    }

    func updateCommentChickenLeg(commentID: String, count: Int?, isClicked: Bool) {
        for index in comments.indices where comments[index].id == commentID {
            comments[index] = comments[index].updatingChickenLegReaction(count: count, isClicked: isClicked)
        }
        collectionList.refresh(commentID: commentID)
    }

    func updateCommentOppose(commentID: String, count: Int?, isClicked: Bool) {
        for index in comments.indices where comments[index].id == commentID {
            comments[index] = comments[index].updatingOpposeReaction(count: count, isClicked: isClicked)
        }
        collectionList.refresh(commentID: commentID)
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
        title = nil
        loginButton.isHidden = false
        showsReplyEntry = false
        replyComposerMode = .plain
        updateReplyContext(for: .plain)
        dismissReplyEditor()
        updateReplyButtonVisibility()
        hasRenderedDetailContent = true
        displayMode = .content
        let existing = currentHeaderContent
        let headerContent = PostDetailHeaderContent(
            postID: existing?.postID ?? "login-required",
            title: existing?.title ?? "需要登录",
            authorName: existing?.authorName ?? "NodeSeek",
            avatarURL: existing?.avatarURL,
            metadataText: existing?.metadataText,
            contentHTML: message
        )
        configureHeader(headerContent)
        authorFilter = nil
        resetAuthorFilterAutoLoad()
        pagination = nil
        comments = []
        loadedCommentPageRanges.removeAll()
        collectionList.headerSource = .init(html: message, visibleMarkdown: nil)
        collectionList.invalidate()
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
        if touchedView.isDescendant(of: collectionList.view) { return false }
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
