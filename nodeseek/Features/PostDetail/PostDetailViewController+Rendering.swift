//
//  PostDetailViewController+Rendering.swift
//  nodeseek
//
//  Created by Codex on 2026/4/30.
//

import AsyncDisplayKit
import DTCoreText
import UIKit

extension PostDetailViewController {
    func scheduleHeaderRender(for content: PostDetailHeaderContent) {
        let generation = renderGeneration
        let html = content.contentHTML
        let signatureHTML = content.signatureHTML
        let showsSignature = PostSignatureDisplaySettings.shared.showsSignatures
        let width = availableHeaderContentWidth
        let baseURL = baseURL
        renderQueue.async { [weak self] in
            let renderedContent = Self.makeRenderedContent(
                html: html,
                signatureHTML: signatureHTML,
                baseURL: baseURL,
                maxImageWidth: width,
                showsSignature: showsSignature
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
        signatureHTML: String? = nil,
        baseURL: URL,
        maxImageWidth: CGFloat,
        showsSignature: Bool = true
    ) -> [RenderedContentBlock]? {
        let renderer = DTCoreTextHTMLContentRenderer()
        let bodyBlocks = renderer.render(
            fragment: html,
            baseURL: baseURL,
            maxImageWidth: maxImageWidth
        )
        let signatureBlocks = showsSignature
            ? renderSignatureBlocks(
                signatureHTML: signatureHTML,
                renderer: renderer,
                baseURL: baseURL,
                maxImageWidth: maxImageWidth
            )
            : []
        let mergedBlocks = mergedBodyBlocks(bodyBlocks, withSignatureBlocks: signatureBlocks)
        return mergedBlocks.isEmpty ? nil : mergedBlocks
    }

    private static func renderSignatureBlocks(
        signatureHTML: String?,
        renderer: DTCoreTextHTMLContentRenderer,
        baseURL: URL,
        maxImageWidth: CGFloat
    ) -> [RenderedContentBlock] {
        guard let signatureHTML = signatureHTML?.trimmingCharacters(in: .whitespacesAndNewlines),
              signatureHTML.isEmpty == false
        else {
            return []
        }

        let blocks = renderer.render(
            fragment: signatureHTML,
            baseURL: baseURL,
            maxImageWidth: maxImageWidth
        )
        return styledSignatureBlocks(blocks)
    }

    private static func styledSignatureBlocks(_ blocks: [RenderedContentBlock]) -> [RenderedContentBlock] {
        blocks.compactMap(styledSignatureBlock)
    }

    private static func styledSignatureBlock(_ block: RenderedContentBlock) -> RenderedContentBlock? {
        switch block {
        case .text(let attributedText):
            let styledText = styledSignatureAttributedText(attributedText)
            return styledText.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : .text(styledText)
        case .quote(let quoteBlock):
            let children = quoteBlock.children.compactMap { child in
                styledSignatureBlock(child)
            }
            return children.isEmpty ? nil : .quote(RenderedQuoteBlock(children: children))
        case .table, .codeBlock, .image, .iframeLink, .imagePlaceholder, .unsupported:
            return block
        }
    }

    private static func styledSignatureAttributedText(_ attributedText: NSAttributedString) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: attributedText)
        guard mutable.length > 0 else { return mutable }
        applySignatureTextAttributes(to: mutable, range: NSRange(location: 0, length: mutable.length))
        return mutable
    }

    private static func mergedBodyBlocks(
        _ bodyBlocks: [RenderedContentBlock],
        withSignatureBlocks signatureBlocks: [RenderedContentBlock]
    ) -> [RenderedContentBlock] {
        guard bodyBlocks.isEmpty == false else { return signatureBlocks }
        guard signatureBlocks.isEmpty == false else { return bodyBlocks }

        var merged = bodyBlocks
        guard let lastIndex = merged.indices.last,
              case let .text(bodyText) = merged[lastIndex],
              case let .text(signatureText) = signatureBlocks[0]
        else {
            merged.append(contentsOf: signatureBlocks)
            return merged
        }

        merged[lastIndex] = .text(mergedTextBlock(bodyText, signature: signatureText))
        merged.append(contentsOf: signatureBlocks.dropFirst())
        return merged
    }

    private static func mergedTextBlock(_ body: NSAttributedString, signature: NSAttributedString) -> NSAttributedString {
        let merged = NSMutableAttributedString(attributedString: body)
        let normalizedSignature = NSMutableAttributedString(attributedString: signature)
        trimTrailingWhitespaceAndNewlines(in: merged)
        trimLeadingWhitespaceAndNewlines(in: normalizedSignature)

        if merged.length > 0, normalizedSignature.length > 0 {
            merged.append(NSAttributedString(string: "\n"))
        }
        merged.append(normalizedSignature)
        return merged
    }

    private static func trimLeadingWhitespaceAndNewlines(in attributed: NSMutableAttributedString) {
        guard attributed.length > 0 else { return }
        let source = attributed.string as NSString
        var upperBound = 0
        while upperBound < source.length {
            let character = source.substring(with: NSRange(location: upperBound, length: 1))
            guard character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { break }
            upperBound += 1
        }
        guard upperBound > 0 else { return }
        attributed.deleteCharacters(in: NSRange(location: 0, length: upperBound))
    }

    private static func trimTrailingWhitespaceAndNewlines(in attributed: NSMutableAttributedString) {
        guard attributed.length > 0 else { return }
        let source = attributed.string as NSString
        var lowerBound = source.length
        while lowerBound > 0 {
            let character = source.substring(with: NSRange(location: lowerBound - 1, length: 1))
            guard character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { break }
            lowerBound -= 1
        }
        guard lowerBound < source.length else { return }
        attributed.deleteCharacters(in: NSRange(location: lowerBound, length: source.length - lowerBound))
    }

    private static func applySignatureTextAttributes(
        to mutable: NSMutableAttributedString,
        range: NSRange
    ) {
        mutable.addAttributes(
            [
                .font: AppTypography.signatureFont(),
                .foregroundColor: NodeSeekSignatureStyle.textColor
            ],
            range: range
        )
        mutable.removeAttribute(NSAttributedString.Key(DTTextBlocksAttribute), range: range)
        applySignatureParagraphStyle(to: mutable, range: range)
        mutable.enumerateAttribute(.link, in: range) { value, linkRange, _ in
            guard let value else { return }
            let url: URL?
            if let existingURL = value as? URL {
                url = existingURL
            } else if let string = value as? String {
                url = URL(string: string)
            } else {
                url = nil
            }
            guard let url else { return }
            mutable.addAttributes(NodeSeekSignatureStyle.linkAttributes(url: url), range: linkRange)
        }
    }

    private static func applySignatureParagraphStyle(
        to mutable: NSMutableAttributedString,
        range: NSRange
    ) {
        var didApplyTopSpacing = false
        mutable.enumerateAttribute(.paragraphStyle, in: range) { value, paragraphRange, _ in
            let style = NSMutableParagraphStyle()
            if let baseStyle = value as? NSParagraphStyle {
                style.alignment = baseStyle.alignment
                style.baseWritingDirection = baseStyle.baseWritingDirection
            }
            style.lineSpacing = 2
            style.paragraphSpacing = 0
            style.lineBreakMode = .byWordWrapping

            let paragraphText = (mutable.string as NSString).substring(with: paragraphRange)
            if didApplyTopSpacing == false,
               paragraphText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                style.paragraphSpacingBefore = 6
                didApplyTopSpacing = true
            } else {
                style.paragraphSpacingBefore = 0
            }

            mutable.addAttribute(.paragraphStyle, value: style, range: paragraphRange)
        }
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
                AppLog.info(.rendering, "scheduleAttachmentLayoutRefresh fire visible=\(visibleRows) rows=\(self.tableNode(self.tableNode, numberOfRowsInSection: 0))")
            }
            self.tableNode.relayoutItems()
            self.tableNode.performBatch(animated: false, updates: {})
        }
        attachmentLayoutRefreshWorkItem = workItem
        if NodeSeekDebugConfig.enableDetailRenderDiagnostics {
            AppLog.info(.rendering, "scheduleAttachmentLayoutRefresh queued")
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
        let signatureHTML = comment.signatureHTML
        let showsSignature = PostSignatureDisplaySettings.shared.showsSignatures
        let width = availableCommentContentWidth
        let baseURL = baseURL
        renderQueue.async { [weak self] in
            let renderedContent = Self.makeRenderedContent(
                html: html,
                signatureHTML: signatureHTML,
                baseURL: baseURL,
                maxImageWidth: width,
                showsSignature: showsSignature
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
