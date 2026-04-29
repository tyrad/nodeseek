//
//  PostBodyCellNode.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import AsyncDisplayKit
import DTCoreText
import OSLog
import UIKit

final class PostBodyCellNode: ASCellNode {
    private enum Layout {
        static let contentInset = UIEdgeInsets(
            top: 18,
            left: PostDetailContentLayout.horizontalInset,
            bottom: 14,
            right: PostDetailContentLayout.horizontalInset
        )
        static let verticalSpacing: CGFloat = 12
        static let bodySpacing: CGFloat = 18
    }

    private let content: PostDetailHeaderContent
    private let onImageTapped: ([URL], Int) -> Void
    private let onLinkTapped: (URL) -> Void
    private let onTextLayoutInvalidated: () -> Void
    private let avatarLoader = AvatarImageLoader.shared
    private weak var avatarImageView: UIImageView?
    private var hasRequestedAvatar = false

    private let titleNode = ASTextNode()
    private let subtitleNode = ASTextNode()
    private let bodyNodes: [ASDisplayNode]

    private lazy var avatarNode: ASDisplayNode = {
        let node = ASDisplayNode(viewBlock: { [weak self] in
            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFill
            imageView.backgroundColor = .systemGray5
            imageView.layer.cornerRadius = PostDetailContentLayout.avatarCornerRadius
            imageView.layer.masksToBounds = true
            self?.avatarImageView = imageView
            return imageView
        })
        node.style.preferredSize = CGSize(
            width: PostDetailContentLayout.avatarSize,
            height: PostDetailContentLayout.avatarSize
        )
        return node
    }()

    init(
        content: PostDetailHeaderContent,
        renderedContent: [RenderedContentBlock]?,
        onImageTapped: @escaping ([URL], Int) -> Void,
        onLinkTapped: @escaping (URL) -> Void = { _ in },
        onTextLayoutInvalidated: @escaping () -> Void
    ) {
        self.content = content
        self.onImageTapped = onImageTapped
        self.onLinkTapped = onLinkTapped
        self.onTextLayoutInvalidated = onTextLayoutInvalidated
        self.bodyNodes = DetailContentBlockNodeFactory.makeNodes(
            from: renderedContent ?? [],
            onImageTapped: onImageTapped,
            onLinkTapped: onLinkTapped,
            onTextLayoutInvalidated: onTextLayoutInvalidated
        )
        super.init()
        automaticallyManagesSubnodes = true
        selectionStyle = .none
        backgroundColor = .systemBackground
        configureText()
    }

    override func didLoad() {
        super.didLoad()
        requestAvatarIfNeeded()
    }

    override func didEnterDisplayState() {
        super.didEnterDisplayState()
        requestAvatarIfNeeded()
    }

    override func didExitDisplayState() {
        super.didExitDisplayState()
        cancelAvatarLoad()
        hasRequestedAvatar = false
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        titleNode.style.flexShrink = 1
        subtitleNode.style.flexShrink = 1

        let authorStack = ASStackLayoutSpec.horizontal()
        authorStack.spacing = PostDetailContentLayout.avatarSpacing
        authorStack.alignItems = .center
        authorStack.children = [avatarNode, subtitleNode]

        let stack = ASStackLayoutSpec.vertical()
        stack.spacing = Layout.verticalSpacing
        stack.children = [titleNode, authorStack]

        if bodyNodes.isEmpty == false {
            let contentStack = ASStackLayoutSpec.vertical()
            contentStack.spacing = Layout.verticalSpacing
            contentStack.style.spacingBefore = Layout.bodySpacing - Layout.verticalSpacing
            contentStack.children = bodyNodes
            stack.children?.append(contentStack)
        }

        return ASInsetLayoutSpec(insets: Layout.contentInset, child: stack)
    }

    private func configureText() {
        titleNode.maximumNumberOfLines = 0
        titleNode.attributedText = NSAttributedString(
            string: content.title,
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .title2),
                .foregroundColor: UIColor.label
            ]
        )

        subtitleNode.maximumNumberOfLines = 0
        subtitleNode.attributedText = NSAttributedString(
            string: [content.authorName, content.metadataText].compactMap(\.self).joined(separator: " · "),
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .subheadline),
                .foregroundColor: UIColor.secondaryLabel
            ]
        )
    }

    private func requestAvatarIfNeeded() {
        guard !hasRequestedAvatar else { return }
        guard let avatarImageView else { return }
        hasRequestedAvatar = true
        avatarLoader.loadAvatar(into: avatarImageView, postID: content.postID, avatarURL: content.avatarURL)
    }

    private func cancelAvatarLoad() {
        guard let avatarImageView else { return }
        avatarLoader.cancel(on: avatarImageView)
    }
}

extension ASCellNode {
    func flashAnchorHighlight() {
        guard isNodeLoaded else { return }
        let originalColor = view.backgroundColor ?? UIColor.systemBackground
        view.backgroundColor = UIColor(red: 15 / 255, green: 128 / 255, blue: 85 / 255, alpha: 0.12)
        UIView.animate(
            withDuration: 0.35,
            delay: 0.8,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            self.view.backgroundColor = originalColor
        }
    }
}

final class DetailRichTextNode: ASDisplayNode {
    nonisolated private static let defaultMeasureWidth: CGFloat = 320
    private static let logger = Logger(subsystem: "com.nodeseek.app", category: "DetailRichTextNode")

    private let attributedText: NSMutableAttributedString
    private let attributedTextLock = NSLock()
    private let onImageTapped: ([URL], Int) -> Void
    private let onLinkTapped: (URL) -> Void
    private let onLayoutInvalidated: () -> Void
    private let forcedMinimumHeight: CGFloat
    private let diagnosticID = String(UUID().uuidString.prefix(8))

    init(
        attributedText: NSAttributedString,
        forcedMinimumHeight: CGFloat = 0,
        onImageTapped: @escaping ([URL], Int) -> Void,
        onLinkTapped: @escaping (URL) -> Void = { _ in },
        onLayoutInvalidated: @escaping () -> Void
    ) {
        self.attributedText = NSMutableAttributedString(attributedString: attributedText)
        self.forcedMinimumHeight = forcedMinimumHeight
        self.onImageTapped = onImageTapped
        self.onLinkTapped = onLinkTapped
        self.onLayoutInvalidated = onLayoutInvalidated
        super.init()
        setViewBlock {
            DetailRichTextView()
        }
        style.flexShrink = 1
        style.flexGrow = 1
        logDiagnostics("init length=\(attributedText.length) attachments=\(Self.attachmentDiagnostics(in: attributedText))")
    }

    override func didLoad() {
        super.didLoad()
        guard let richTextView = view as? DetailRichTextView else { return }
        richTextView.configure(
            attributedText,
            onImageTapped: onImageTapped,
            onLinkTapped: onLinkTapped,
            onLayoutInvalidated: onLayoutInvalidated,
            onAttachmentLayoutUpdated: { [weak self] url, originalSize, displaySize in
                self?.updateAttachmentLayout(
                    matching: url,
                    originalSize: originalSize,
                    displaySize: displaySize
                )
            }
        )
    }

    @discardableResult
    func updateAttachmentLayout(
        matching url: URL,
        originalSize: CGSize,
        displaySize: CGSize
        ) -> Bool {
        guard originalSize.width > 0,
              originalSize.height > 0,
              displaySize.width > 0,
              displaySize.height > 0 else {
            return false
        }

        var didUpdate = false
        attributedTextLock.lock()
        attributedText.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributedText.length)
        ) { value, _, _ in
            guard let attachment = value as? DTTextAttachment,
                  attachment.contentURL == url else {
                return
            }

            attachment.originalSize = originalSize
            attachment.displaySize = displaySize
            didUpdate = true
        }
        attributedTextLock.unlock()

        if didUpdate {
            logDiagnostics(
                "node attachment updated url=\(url.absoluteString) original=\(Self.string(from: originalSize)) display=\(Self.string(from: displaySize))"
            )
            invalidateCalculatedLayout()
            setNeedsLayout()
        } else {
            logDiagnostics(
                "node attachment update missed url=\(url.absoluteString) original=\(Self.string(from: originalSize)) display=\(Self.string(from: displaySize)) attachments=\(Self.attachmentDiagnostics(in: attributedText))"
            )
        }
        return didUpdate
    }

    override func calculateSizeThatFits(_ constrainedSize: CGSize) -> CGSize {
        let width = Self.resolvedMeasureWidth(constrainedSize.width)
        attributedTextLock.lock()
        let measuredText = NSAttributedString(attributedString: attributedText)
        attributedTextLock.unlock()

        guard width > 0, measuredText.length > 0 else {
            return .zero
        }

        let boundingRect = measuredText.boundingRect(
            with: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let boundingHeight = ceil(max(boundingRect.height, 1))
        let dtCoreTextHeight = Self.dtCoreTextHeight(for: measuredText, width: width)
        let height = Self.resolvedMeasuredHeight(
            dtCoreTextHeight: dtCoreTextHeight,
            boundingHeight: boundingHeight
        )
        logDiagnostics(
            "measure width=\(Self.numberString(width)) bounding=\(Self.numberString(boundingHeight)) dt=\(dtCoreTextHeight.map(Self.numberString) ?? "nil") result=\(Self.numberString(height)) attachments=\(Self.attachmentDiagnostics(in: measuredText))"
        )
        return CGSize(width: width, height: ceil(max(height, forcedMinimumHeight)))
    }

    nonisolated static func resolvedMeasureWidth(_ width: CGFloat) -> CGFloat {
        guard width.isFinite, width > 0 else {
            return defaultMeasureWidth
        }
        return width
    }

    nonisolated static func resolvedMeasuredHeight(
        dtCoreTextHeight: CGFloat?,
        boundingHeight: CGFloat
    ) -> CGFloat {
        if let dtCoreTextHeight,
           dtCoreTextHeight.isFinite,
           dtCoreTextHeight > 0 {
            return ceil(dtCoreTextHeight)
        }

        return ceil(max(boundingHeight, 1))
    }

    nonisolated private static func dtCoreTextHeight(for attributedText: NSAttributedString, width: CGFloat) -> CGFloat? {
        guard width > 0, attributedText.length > 0 else { return nil }
        let unknownHeight: CGFloat = 16_777_215
        let layouter = DTCoreTextLayouter(attributedString: attributedText)
        let layoutFrame = layouter?.layoutFrame(
            with: CGRect(x: 0, y: 0, width: width, height: unknownHeight),
            range: NSRange(location: 0, length: 0)
        )
        guard let height = layoutFrame?.frame.maxY,
              height.isFinite,
              height > 0 else {
            return nil
        }
        return ceil(height)
    }

    private func logDiagnostics(_ message: String) {
        guard NodeSeekDebugConfig.enableDetailRenderDiagnostics else { return }
        Self.logger.info("[\(self.diagnosticID, privacy: .public)] \(message, privacy: .public)")
    }

    nonisolated private static func attachmentDiagnostics(in attributedText: NSAttributedString) -> String {
        guard attributedText.length > 0 else { return "[]" }
        var parts: [String] = []
        attributedText.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributedText.length)
        ) { value, _, _ in
            guard let attachment = value as? DTTextAttachment else { return }
            let url = attachment.contentURL?.absoluteString ?? "nil"
            parts.append(
                "url=\(url),original=\(string(from: attachment.originalSize)),display=\(string(from: attachment.displaySize))"
            )
        }
        if parts.count > 6 {
            return "[\(parts.prefix(6).joined(separator: " | ")) | ... total=\(parts.count)]"
        }
        return "[\(parts.joined(separator: " | "))]"
    }

    nonisolated private static func string(from size: CGSize) -> String {
        "\(numberString(size.width))x\(numberString(size.height))"
    }

    nonisolated private static func numberString(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }
}
