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
        presentReplyEditor(mode: .plain)
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
        presentReplyEditor(action: "回复", for: comment)
    }

    func handleQuote(_ comment: Comment) {
        presentReplyEditor(action: "引用", for: comment)
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
        view.setNeedsLayout()
        view.layoutIfNeeded()
        updateReplyButtonVisibility()
        if view.window != nil {
            replyTextView.becomeFirstResponder()
        }
    }

    func presentReplyEditor(action: String, for comment: Comment) {
        presentReplyEditor(mode: action == "引用" ? .quote(comment) : .reply(comment))
    }

    nonisolated static func trimmedNonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func updateReplyContext(for mode: CommentComposerMode) {
        let contextText: String?
        switch mode {
        case .plain:
            contextText = nil
        case .reply(let comment):
            contextText = replyContextText(action: "回复", comment: comment)
        case .quote(let comment):
            contextText = replyContextText(action: "引用", comment: comment)
        }

        if let contextText, contextText.isEmpty == false {
            replyContextLabel.text = contextText
            replyContextBar.isHidden = false
            replyContextBarHeightConstraint?.constant = 32
        } else {
            replyContextLabel.text = nil
            replyContextBar.isHidden = true
            replyContextBarHeightConstraint?.constant = 0
        }
    }

    func replyContextText(action: String, comment: Comment) -> String {
        let authorName = AuthorDisplayPolicy.displayName(from: comment.authorName) ?? comment.authorName
        let contextParts = [
            action,
            Self.trimmedNonEmpty(authorName),
            comment.floorText.flatMap(Self.trimmedNonEmpty)
        ]
            .compactMap(\.self)
        return contextParts.joined(separator: " ")
    }

    @objc
    func dismissReplyEditor() {
        replyTextView.resignFirstResponder()
        setStickerPickerVisible(false, animated: false)
        replyEditorBackdrop.isHidden = true
        replyEditorContainer.isHidden = true
        replyComposerMode = .plain
        updateReplyContext(for: .plain)
        updateReplyButtonVisibility()
    }

    @objc
    func clearReplyContext() {
        replyComposerMode = .plain
        updateReplyContext(for: .plain)
    }

    @objc
    func sendReplyTapped() {
        guard let content = Self.trimmedNonEmpty(replyTextView.text) else {
            showError(message: "回复内容不能为空。")
            return
        }

        presenter.didTapSendReply(content: resolvedReplyContent(from: content))
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
                await stickerCookieBridge.syncWebViewCookiesToURLSession()
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
