//
//  PostDetailViewController+CommentCopy.swift
//  nodeseek
//
//  Created by Codex on 2026/5/24.
//

import UIKit

extension PostDetailViewController {
    func presentCommentCopySheet(for comment: Comment) {
        let text = CommentCopyTextFormatter.plainText(for: comment, baseURL: baseURL)
        guard text.isEmpty == false else {
            showToast(message: "暂无可复制内容")
            return
        }

        let viewController = CommentCopySheetViewController(
            text: text,
            pasteboardStringWriter: { [weak self] copiedText in
                self?.pasteboardStringWriter(copiedText)
                self?.showToast(message: "已复制")
            }
        )
        present(viewController, animated: true)
    }

    func presentPostBodyCopySheet(for content: PostDetailHeaderContent) {
        let text = CommentCopyTextFormatter.plainText(for: content, baseURL: baseURL)
        guard text.isEmpty == false else {
            showToast(message: "暂无可复制内容")
            return
        }

        let viewController = CommentCopySheetViewController(
            text: text,
            pasteboardStringWriter: { [weak self] copiedText in
                self?.pasteboardStringWriter(copiedText)
                self?.showToast(message: "已复制")
            }
        )
        present(viewController, animated: true)
    }
}
