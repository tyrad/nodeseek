//
//  PostDetailViewController+Rendering.swift
//  nodeseek
//
//  Created by Codex on 2026/4/30.
//

import AsyncDisplayKit
import OSLog
import UIKit

extension PostDetailViewController {
    func scheduleHeaderRender(for content: PostDetailHeaderContent) {
        let generation = renderGeneration
        let html = content.contentHTML
        let width = availableHeaderContentWidth
        let baseURL = baseURL
        renderQueue.async { [weak self] in
            let renderedContent = Self.makeRenderedContent(
                html: html,
                baseURL: baseURL,
                maxImageWidth: width
            )
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.renderGeneration == generation else { return }
                guard self.currentHeaderContent?.postID == content.postID else { return }
                self.configureHeader(content, renderedContent: renderedContent)
                self.scheduleHeaderReload()
            }
        }
    }

    static func makeRenderedContent(
        html: String,
        baseURL: URL,
        maxImageWidth: CGFloat
    ) -> [RenderedContentBlock]? {
        let blocks = DTCoreTextHTMLContentRenderer().render(fragment: html, baseURL: baseURL, maxImageWidth: maxImageWidth)
        return blocks.isEmpty ? nil : blocks
    }

    var availableHeaderContentWidth: CGFloat {
        let width = tableNode.view.bounds.width > 0 ? tableNode.view.bounds.width : view.bounds.width
        return max((width > 0 ? width : 320) - Layout.horizontalInset * 2, 1)
    }

    var availableCommentContentWidth: CGFloat {
        let width = tableNode.view.bounds.width > 0 ? tableNode.view.bounds.width : view.bounds.width
        let contentWidth = (width > 0 ? width : 320)
            - PostDetailContentLayout.horizontalInset * 2
            - PostDetailContentLayout.avatarSize
            - PostDetailContentLayout.avatarSpacing
        return max(contentWidth, 1)
    }

    func scheduleAttachmentLayoutRefresh() {
        attachmentLayoutRefreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isViewLoaded else { return }
            if NodeSeekDebugConfig.enableDetailRenderDiagnostics {
                let visibleRows = self.tableNode.indexPathsForVisibleRows().map { "\($0.section):\($0.row)" }.joined(separator: ",")
                Self.detailRenderLogger.info(
                    "scheduleAttachmentLayoutRefresh fire visible=\(visibleRows, privacy: .public) rows=\(self.tableNode(self.tableNode, numberOfRowsInSection: 0), privacy: .public)"
                )
            }
            self.tableNode.relayoutItems()
            self.tableNode.performBatch(animated: false, updates: {})
        }
        attachmentLayoutRefreshWorkItem = workItem
        if NodeSeekDebugConfig.enableDetailRenderDiagnostics {
            Self.detailRenderLogger.info("scheduleAttachmentLayoutRefresh queued")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
    }

    func preheatCommentRender(for comments: [Comment]) {
        for comment in comments {
            scheduleCommentRenderIfNeeded(for: comment)
        }
    }

    func scheduleCommentRenderIfNeeded(for comment: Comment) {
        let commentID = comment.id
        guard renderedCommentIDs.contains(commentID) == false else { return }
        guard commentRenderInFlight.insert(commentID).inserted else { return }

        let generation = renderGeneration
        let html = comment.contentHTML
        let width = availableCommentContentWidth
        let baseURL = baseURL
        renderQueue.async { [weak self] in
            let renderedContent = Self.makeRenderedContent(
                html: html,
                baseURL: baseURL,
                maxImageWidth: width
            )
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.renderGeneration == generation else { return }
                self.commentRenderInFlight.remove(commentID)
                self.renderedCommentIDs.insert(commentID)
                if let renderedContent {
                    self.commentRenderedCache[commentID] = renderedContent
                } else {
                    self.commentRenderedCache.removeValue(forKey: commentID)
                }
                self.scheduleCommentReload(commentID: commentID)
            }
        }
    }
}
