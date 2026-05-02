//
//  PostBodyCellNode.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import AsyncDisplayKit
import DTCoreText
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
    private let onAuthorTapped: (URL) -> Void
    private let onTextLayoutInvalidated: () -> Void
    private let avatarLoader = AvatarImageLoader.shared
    private weak var avatarImageView: UIImageView?
    private var hasRequestedAvatar = false
    private var hasDisplayableAuthor: Bool {
        AuthorDisplayPolicy.isDisplayable(content.authorName)
    }
    private var hasAuthorProfileLink: Bool {
        content.authorProfileURL != nil && hasDisplayableAuthor
    }

    private let titleNode = ASTextNode()
    private let authorButtonNode = ASButtonNode()
    private let metadataNode = ASTextNode()
    private let bodyNodes: [ASDisplayNode]
    private var lastAppliedUserInterfaceStyle: UIUserInterfaceStyle?

    private lazy var avatarNode: ASDisplayNode = {
        let node = ASDisplayNode(viewBlock: { [weak self] in
            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFill
            imageView.backgroundColor = .systemGray5
            imageView.layer.cornerRadius = PostDetailContentLayout.avatarCornerRadius
            imageView.layer.masksToBounds = true
            imageView.isUserInteractionEnabled = self?.hasAuthorProfileLink == true
            if self?.hasAuthorProfileLink == true {
                imageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(PostBodyCellNode.authorTapped)))
            }
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
        onAuthorTapped: @escaping (URL) -> Void = { _ in },
        onTextLayoutInvalidated: @escaping () -> Void
    ) {
        self.content = content
        self.onImageTapped = onImageTapped
        self.onLinkTapped = onLinkTapped
        self.onAuthorTapped = onAuthorTapped
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
        configureActions()
    }

    override func didLoad() {
        super.didLoad()
        lastAppliedUserInterfaceStyle = view.traitCollection.userInterfaceStyle
        view.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self] (view: UIView, previousTraitCollection: UITraitCollection) in
            guard let self else { return }
            guard previousTraitCollection.userInterfaceStyle != view.traitCollection.userInterfaceStyle else { return }
            self.refreshAppearanceForCurrentTraits()
        }
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
        authorButtonNode.style.flexShrink = 0
        metadataNode.style.flexShrink = 1

        let identityStack = ASStackLayoutSpec.horizontal()
        identityStack.spacing = 5
        identityStack.alignItems = .center
        var identityChildren: [ASLayoutElement] = []
        if hasDisplayableAuthor {
            identityChildren.append(authorButtonNode)
        }
        if Self.metadataText(for: content).isEmpty == false {
            identityChildren.append(metadataNode)
        }
        identityStack.children = identityChildren
        identityStack.style.flexShrink = 1
        identityStack.style.flexGrow = 1

        let authorStack = ASStackLayoutSpec.horizontal()
        authorStack.spacing = PostDetailContentLayout.avatarSpacing
        authorStack.alignItems = .center
        authorStack.children = hasDisplayableAuthor ? [avatarNode, identityStack] : [identityStack]

        let stack = ASStackLayoutSpec.vertical()
        stack.spacing = Layout.verticalSpacing
        stack.children = identityChildren.isEmpty ? [titleNode] : [titleNode, authorStack]

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
        titleNode.attributedText = Self.titleAttributedText(for: content)

        authorButtonNode.setAttributedTitle(
            NSAttributedString(
                string: AuthorDisplayPolicy.displayName(from: content.authorName) ?? "",
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .subheadline),
                    .foregroundColor: UIColor.secondaryLabel
                ]
            ),
            for: .normal
        )
        authorButtonNode.accessibilityLabel = "查看 \(AuthorDisplayPolicy.displayName(from: content.authorName) ?? "作者") 的主页"

        metadataNode.maximumNumberOfLines = 0
        metadataNode.attributedText = NSAttributedString(
            string: Self.metadataText(for: content),
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .subheadline),
                .foregroundColor: UIColor.secondaryLabel
            ]
        )
    }

    private static func titleAttributedText(for content: PostDetailHeaderContent) -> NSAttributedString {
        let titleFont = UIFont.preferredFont(forTextStyle: .title2)
        let result = NSMutableAttributedString(
            string: content.title,
            attributes: [
                .font: titleFont,
                .foregroundColor: UIColor.label
            ]
        )

        guard let requiredReadingLevel = content.requiredReadingLevel else {
            return result
        }

        let badgeFont = UIFont.preferredFont(forTextStyle: .subheadline)
        let badgeColor = UIColor.systemRed
        result.append(NSAttributedString(string: " "))

        if let lockImage = UIImage(
            systemName: "lock.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: badgeFont.pointSize, weight: .semibold)
        )?.withTintColor(badgeColor, renderingMode: .alwaysOriginal) {
            let attachment = NSTextAttachment()
            attachment.image = lockImage
            attachment.bounds = CGRect(
                x: 0,
                y: (titleFont.capHeight - badgeFont.pointSize) / 2,
                width: badgeFont.pointSize,
                height: badgeFont.pointSize
            )
            result.append(NSAttributedString(attachment: attachment))
        }

        result.append(NSAttributedString(
            string: " \(requiredReadingLevel)",
            attributes: [
                .font: badgeFont,
                .foregroundColor: badgeColor,
                .baselineOffset: (titleFont.capHeight - badgeFont.capHeight) / 2
            ]
        ))

        return result
    }

    @discardableResult
    func refreshAppearanceForCurrentTraits() -> Bool {
        let currentStyle = isNodeLoaded ? view.traitCollection.userInterfaceStyle : UITraitCollection.current.userInterfaceStyle
        guard lastAppliedUserInterfaceStyle != currentStyle else { return false }
        lastAppliedUserInterfaceStyle = currentStyle
        configureText()
        setNeedsLayout()
        setNeedsDisplay()
        return true
    }

    var debugTitleAttributedText: NSAttributedString? {
        titleNode.attributedText
    }

    private func configureActions() {
        authorButtonNode.isUserInteractionEnabled = hasAuthorProfileLink
        if hasAuthorProfileLink {
            authorButtonNode.addTarget(self, action: #selector(authorTapped), forControlEvents: .touchUpInside)
        }
    }

    @objc private func authorTapped() {
        guard let authorProfileURL = content.authorProfileURL else { return }
        onAuthorTapped(authorProfileURL)
    }

    private func requestAvatarIfNeeded() {
        guard hasDisplayableAuthor else { return }
        guard !hasRequestedAvatar else { return }
        guard let avatarImageView else { return }
        hasRequestedAvatar = true
        avatarLoader.loadAvatar(into: avatarImageView, postID: content.postID, avatarURL: content.avatarURL)
    }

    private func cancelAvatarLoad() {
        guard let avatarImageView else { return }
        avatarLoader.cancel(on: avatarImageView)
    }

    private static func metadataText(for content: PostDetailHeaderContent) -> String {
        let metadata = content.metadataText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard metadata.isEmpty == false else { return "" }
        return AuthorDisplayPolicy.isDisplayable(content.authorName) ? "· \(metadata)" : metadata
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
        AppLog.info(.rendering, "[\(diagnosticID)] \(message)")
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
