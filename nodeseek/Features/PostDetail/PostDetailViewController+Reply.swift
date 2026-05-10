//
//  PostDetailViewController+Reply.swift
//  nodeseek
//
//  Created by Codex on 2026/4/30.
//

import UIKit

extension PostDetailViewController {
    @objc
    func replyButtonTapped() {
        ensureNodeSeekLoggedIn { [weak self] in
            self?.presentCommentEditor()
        }
    }

    @objc
    func dismissKeyboardFromBackgroundTap(_ recognizer: UITapGestureRecognizer) {
        view.endEditing(true)
    }

    @objc
    func keyboardWillChangeFrame(_ notification: Notification) {
        animateKeyboardTransition(with: notification)
    }

    @objc
    func keyboardWillHide(_ notification: Notification) {
        animateKeyboardTransition(with: notification)
    }

    func animateKeyboardTransition(with notification: Notification) {
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.25
        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }
    }

    func handleReply(to comment: Comment) {
        ensureNodeSeekLoggedIn { [weak self] in
            self?.presentReplyEditor(action: "回复", for: comment)
        }
    }

    func handleReply(toPostHeader header: PostDetailHeaderContent) {
        let comment = Comment(
            id: header.postID,
            anchorID: "0",
            authorName: header.authorName,
            isPoster: true,
            avatarURL: header.avatarURL,
            authorProfileURL: header.authorProfileURL,
            floorText: "#0",
            createdAtText: header.metadataText,
            contentHTML: header.contentHTML
        )
        ensureNodeSeekLoggedIn { [weak self] in
            self?.presentReplyEditor(action: "回复", for: comment)
        }
    }

    func handleQuote(_ comment: Comment) {
        ensureNodeSeekLoggedIn { [weak self] in
            self?.presentReplyEditor(action: "引用", for: comment)
        }
    }

    func updateReplyButtonVisibility() {
        replyButton.isHidden = showsReplyEntry == false || displayMode != .content || replyEditorContainer.isHidden == false
    }

    func presentReplyEditor(mode: CommentComposerMode) {
        guard showsReplyEntry, displayMode == .content else { return }
        replyComposerMode = mode
        updateReplyContext(for: mode)
        replyEditorBackdrop.isHidden = false
        replyEditorContainer.isHidden = false
        view.bringSubviewToFront(replyEditorBackdrop)
        view.bringSubviewToFront(replyEditorContainer)
        replyEditorContainer.setNeedsLayout()
        replyEditorContainer.layoutIfNeeded()
        updateReplyButtonVisibility()
        if view.window != nil {
            replyTextView.becomeFirstResponder()
        }
    }

    func presentReplyEditor(action: String, for comment: Comment) {
        let mode: CommentComposerMode = action == "引用" ? .quote([comment]) : .reply([comment])
        presentReplyEditor(mode: mergedReplyComposerMode(with: mode))
    }

    func presentCommentEditor() {
        presentReplyEditor(mode: replyComposerMode)
    }

    func ensureNodeSeekLoggedIn(_ action: @escaping @MainActor () -> Void) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let account = await accountRefresher.refreshIfNeeded(force: false, maxAge: 60)
            if account?.isLoggedIn == true {
                action()
                return
            }

            showToast(message: "请先登录 NodeSeek")
            presentNodeSeekLogin {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let account = await accountRefresher.refreshIfNeeded(force: true, maxAge: 0)
                    if account?.isLoggedIn == true {
                        action()
                    } else {
                        showError(message: "请先登录 NodeSeek 后再继续。")
                    }
                }
            }
        }
    }

    func presentNodeSeekLogin(onClose: @escaping @MainActor () -> Void) {
        let loginViewController = LoginWebViewController(onClose: onClose)
        if let navigationController {
            navigationController.pushViewController(loginViewController, animated: true)
            return
        }
        present(UINavigationController(rootViewController: loginViewController), animated: true)
    }

    nonisolated static func trimmedNonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func updateReplyContext(for mode: CommentComposerMode) {
        let rows: [String]
        switch mode {
        case .plain:
            rows = []
        case .reply(let comments):
            rows = replyContextRows(action: "回复", comments: comments)
        case .quote(let comments):
            rows = replyContextRows(action: "引用", comments: comments)
        case .combined(let replies, let quotes):
            rows = replyContextRows(action: "回复", comments: replies)
                + replyContextRows(action: "引用", comments: quotes)
        }

        rebuildReplyContextRows(rows)
        if rows.isEmpty == false {
            replyContextBar.isHidden = false
            replyContextBarHeightConstraint?.constant = replyContextBarHeight(rowCount: rows.count)
        } else {
            replyContextLabel.text = nil
            replyContextBar.isHidden = true
            replyContextBarHeightConstraint?.constant = 0
        }
    }

    func mergedReplyComposerMode(with incomingMode: CommentComposerMode) -> CommentComposerMode {
        switch (replyComposerMode, incomingMode) {
        case (.reply(let existing), .reply(let incoming)):
            return .reply(commentsByAppendingUnique(existing: existing, incoming: incoming))
        case (.quote(let existing), .quote(let incoming)):
            return .quote(commentsByAppendingUnique(existing: existing, incoming: incoming))
        case (.reply(let existingReplies), .quote(let incomingQuotes)):
            return .combined(replies: existingReplies, quotes: incomingQuotes)
        case (.quote(let existingQuotes), .reply(let incomingReplies)):
            return .combined(replies: incomingReplies, quotes: existingQuotes)
        case (.combined(let replies, let quotes), .reply(let incomingReplies)):
            return .combined(
                replies: commentsByAppendingUnique(existing: replies, incoming: incomingReplies),
                quotes: quotes
            )
        case (.combined(let replies, let quotes), .quote(let incomingQuotes)):
            return .combined(
                replies: replies,
                quotes: commentsByAppendingUnique(existing: quotes, incoming: incomingQuotes)
            )
        default:
            return incomingMode
        }
    }

    func commentsByAppendingUnique(existing: [Comment], incoming: [Comment]) -> [Comment] {
        var seenIDs = Set(existing.map(\.id))
        var comments = existing
        for comment in incoming where seenIDs.insert(comment.id).inserted {
            comments.append(comment)
        }
        return comments
    }

    func replyContextRows(action: String, comments: [Comment]) -> [String] {
        let targetTexts = comments.map(replyContextTargetText(comment:))
            .filter { $0.isEmpty == false }
        guard targetTexts.isEmpty == false else { return [] }

        return targetTexts.map { "\(action) \($0)" }
    }

    func replyContextTargetText(comment: Comment) -> String {
        let authorName = AuthorDisplayPolicy.displayName(from: comment.authorName) ?? comment.authorName
        let contextParts = [
            Self.trimmedNonEmpty(authorName),
            comment.floorText.flatMap(Self.trimmedNonEmpty)
        ]
            .compactMap(\.self)
        return contextParts.joined(separator: " ")
    }

    func rebuildReplyContextRows(_ rows: [String]) {
        for view in replyContextStackView.arrangedSubviews {
            replyContextStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for (index, text) in rows.enumerated() {
            let rowView = makeReplyContextRow(text: text, index: index)
            replyContextStackView.addArrangedSubview(rowView)
        }
    }

    func makeReplyContextRow(text: String, index: Int) -> UIView {
        let rowStackView = UIStackView()
        rowStackView.axis = .horizontal
        rowStackView.alignment = .center
        rowStackView.distribution = .fill
        rowStackView.spacing = 6
        rowStackView.accessibilityIdentifier = "post-detail-reply-context-row-\(index)"

        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.text = text
        label.accessibilityIdentifier = index == 0
            ? "post-detail-reply-context-label"
            : "post-detail-reply-context-label-\(index)"
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "xmark")
        configuration.baseForegroundColor = .tertiaryLabel
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: 2, bottom: 2, trailing: 2)
        button.configuration = configuration
        button.tag = index
        button.accessibilityIdentifier = "post-detail-reply-context-remove-button-\(index)"
        button.accessibilityLabel = "取消引用"
        button.addTarget(self, action: #selector(removeReplyContextTarget(_:)), for: .touchUpInside)
        button.widthAnchor.constraint(equalToConstant: 24).isActive = true
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true

        rowStackView.addArrangedSubview(label)
        rowStackView.addArrangedSubview(button)
        return rowStackView
    }

    func replyContextBarHeight(rowCount: Int) -> CGFloat {
        min(replyContextBarMaximumHeight, max(32, CGFloat(rowCount) * 26 + 8))
    }

    @objc
    func dismissReplyEditor() {
        replyTextView.resignFirstResponder()
        setStickerPickerVisible(false, animated: false)
        replyEditorBackdrop.isHidden = true
        replyEditorContainer.isHidden = true
        updateReplyButtonVisibility()
    }

    @objc
    func clearReplyContext() {
        replyComposerMode = .plain
        updateReplyContext(for: .plain)
    }

    @objc
    func removeReplyContextTarget(_ sender: UIButton) {
        let index = sender.tag
        switch replyComposerMode {
        case .plain:
            return
        case .reply(let comments):
            replyComposerMode = modeByRemovingTarget(at: index, from: comments, makeMode: CommentComposerMode.reply)
        case .quote(let comments):
            replyComposerMode = modeByRemovingTarget(at: index, from: comments, makeMode: CommentComposerMode.quote)
        case .combined(let replies, let quotes):
            replyComposerMode = combinedModeByRemovingTarget(at: index, replies: replies, quotes: quotes)
        }
        updateReplyContext(for: replyComposerMode)
    }

    func modeByRemovingTarget(
        at index: Int,
        from comments: [Comment],
        makeMode: ([Comment]) -> CommentComposerMode
    ) -> CommentComposerMode {
        guard comments.indices.contains(index) else { return makeMode(comments) }
        var nextComments = comments
        nextComments.remove(at: index)
        return nextComments.isEmpty ? .plain : makeMode(nextComments)
    }

    func combinedModeByRemovingTarget(at index: Int, replies: [Comment], quotes: [Comment]) -> CommentComposerMode {
        if replies.indices.contains(index) {
            var nextReplies = replies
            nextReplies.remove(at: index)
            return modeFor(replies: nextReplies, quotes: quotes)
        }

        let quoteIndex = index - replies.count
        guard quotes.indices.contains(quoteIndex) else {
            return modeFor(replies: replies, quotes: quotes)
        }
        var nextQuotes = quotes
        nextQuotes.remove(at: quoteIndex)
        return modeFor(replies: replies, quotes: nextQuotes)
    }

    func modeFor(replies: [Comment], quotes: [Comment]) -> CommentComposerMode {
        switch (replies.isEmpty, quotes.isEmpty) {
        case (true, true):
            return .plain
        case (false, true):
            return .reply(replies)
        case (true, false):
            return .quote(quotes)
        case (false, false):
            return .combined(replies: replies, quotes: quotes)
        }
    }

    @objc
    func sendReplyTapped() {
        guard let content = Self.trimmedNonEmpty(replyTextView.text) else {
            showError(message: "回复内容不能为空。")
            return
        }

        ensureNodeSeekLoggedIn { [weak self] in
            guard let self else { return }
            presenter.didTapSendReply(content: resolvedReplyContent(from: content))
        }
    }

    func resolvedReplyContent(from text: String) -> String {
        CommentComposerContentBuilder.content(
            text: text,
            mode: replyComposerMode,
            postURL: resolvedDetailURL() ?? baseURL
        )
    }

    @objc
    func toggleStickerPicker() {
        let shouldShow = replyStickerPickerView.isHidden
        if shouldShow {
            replyTextView.resignFirstResponder()
            Task { [weak self] in
                guard let self else { return }
                await stickerCookieSession.prepareMediaRequest()
                setStickerPickerVisible(true, animated: true)
            }
            return
        }
        setStickerPickerVisible(false, animated: true)
    }

    func insertStickerToken(_ token: String) {
        let result = StickerTokenInsertion.inserting(
            token: token,
            into: replyTextView.text ?? "",
            selectedRange: replyTextView.selectedRange
        )
        replyTextView.text = result.text
        replyTextView.selectedRange = result.selectedRange
    }

    func setStickerPickerVisible(_ isVisible: Bool, animated: Bool) {
        replyStickerPickerView.isHidden = false
        replyStickerPickerHeightConstraint?.constant = isVisible ? 260 : 0
        replyStickerButton.tintColor = isVisible ? .systemBlue : nil

        let animations = {
            self.replyStickerPickerView.alpha = isVisible ? 1 : 0
            self.view.layoutIfNeeded()
        }

        let completion: (Bool) -> Void = { _ in
            self.replyStickerPickerView.isHidden = isVisible == false
        }

        if animated {
            UIView.animate(
                withDuration: 0.22,
                delay: 0,
                options: [.curveEaseInOut, .beginFromCurrentState],
                animations: animations,
                completion: completion
            )
        } else {
            animations()
            completion(true)
        }
    }
}
