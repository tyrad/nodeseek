//
//  CommentCellNode.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import AsyncDisplayKit
import UIKit

enum PostDetailContentLayout {
    static let horizontalInset: CGFloat = 16
    static let commentTopInset: CGFloat = 14
    static let commentBottomInset: CGFloat = 14
    static let avatarSize: CGFloat = 42
    static let avatarCornerRadius: CGFloat = 9
    static let avatarSpacing: CGFloat = 12
}

final class CommentCellNode: ASCellNode {
    private enum Layout {
        static let headerSpacing: CGFloat = 5
        static let bodySpacing: CGFloat = 10

        static func textColumnWidth(for maxWidth: CGFloat, includingAvatar: Bool) -> CGFloat? {
            guard maxWidth.isFinite, maxWidth > 0 else { return nil }
            let avatarWidth = includingAvatar
                ? PostDetailContentLayout.avatarSize + PostDetailContentLayout.avatarSpacing
                : 0
            let chromeWidth = PostDetailContentLayout.horizontalInset * 2 + avatarWidth
            return max(maxWidth - chromeWidth, 1)
        }
    }

    private let comment: Comment
    private let onImageTapped: ([URL], Int) -> Void
    private let onLinkTapped: (URL) -> Void
    private let onAuthorTapped: (URL) -> Void
    private let onReplyTapped: (Comment) -> Void
    private let onQuoteTapped: (Comment) -> Void
    private let onTextLayoutInvalidated: () -> Void
    private let avatarLoader = AvatarImageLoader.shared
    private weak var avatarImageView: UIImageView?
    private var hasRequestedAvatar = false
    private var hasDisplayableAuthor: Bool {
        AuthorDisplayPolicy.isDisplayable(comment.authorName)
    }
    private var hasAuthorProfileLink: Bool {
        comment.authorProfileURL != nil && hasDisplayableAuthor
    }

    private let authorButtonNode = ASButtonNode()
    private let posterBadgeNode = ASTextNode()
    private let timeNode = ASTextNode()
    private let floorNode = ASTextNode()
    private let replyButtonNode = ASButtonNode()
    private let quoteButtonNode = ASButtonNode()
    private let separatorNode = ASDisplayNode()
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
                imageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(CommentCellNode.authorTapped)))
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
        comment: Comment,
        renderedBody: [RenderedContentBlock]?,
        onImageTapped: @escaping ([URL], Int) -> Void,
        onLinkTapped: @escaping (URL) -> Void = { _ in },
        onAuthorTapped: @escaping (URL) -> Void = { _ in },
        onReplyTapped: @escaping (Comment) -> Void = { _ in },
        onQuoteTapped: @escaping (Comment) -> Void = { _ in },
        onTextLayoutInvalidated: @escaping () -> Void
    ) {
        self.comment = comment
        self.onImageTapped = onImageTapped
        self.onLinkTapped = onLinkTapped
        self.onAuthorTapped = onAuthorTapped
        self.onReplyTapped = onReplyTapped
        self.onQuoteTapped = onQuoteTapped
        self.onTextLayoutInvalidated = onTextLayoutInvalidated
        self.bodyNodes = DetailContentBlockNodeFactory.makeNodes(
            from: renderedBody ?? [],
            onImageTapped: onImageTapped,
            onLinkTapped: onLinkTapped,
            onTextLayoutInvalidated: onTextLayoutInvalidated
        )
        super.init()
        automaticallyManagesSubnodes = true
        selectionStyle = .none
        backgroundColor = .systemBackground
        separatorNode.backgroundColor = .separator
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
        authorButtonNode.style.flexShrink = 1
        posterBadgeNode.style.flexShrink = 0
        timeNode.style.flexShrink = 1
        floorNode.style.flexShrink = 0
        replyButtonNode.style.flexShrink = 0
        quoteButtonNode.style.flexShrink = 0
        separatorNode.style.height = ASDimension(unit: .points, value: 1 / UIScreen.main.scale)

        let identityStack = ASStackLayoutSpec.horizontal()
        identityStack.spacing = Layout.headerSpacing
        identityStack.alignItems = .center
        var identityChildren: [ASLayoutElement] = []
        if hasDisplayableAuthor {
            identityChildren.append(authorButtonNode)
        }
        if comment.isPoster {
            identityChildren.append(posterBadgeNode)
        }
        if comment.createdAtText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            identityChildren.append(timeNode)
        }
        identityStack.children = identityChildren
        identityStack.style.flexGrow = 1
        identityStack.style.flexShrink = 1

        let headerStack = ASStackLayoutSpec.horizontal()
        headerStack.alignItems = .start
        headerStack.justifyContent = .spaceBetween
        var headerChildren: [ASLayoutElement] = []
        if identityChildren.isEmpty == false {
            headerChildren.append(identityStack)
        }
        var actionChildren: [ASLayoutElement] = []
        if comment.floorText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            actionChildren.append(floorNode)
        }
        actionChildren.append(replyButtonNode)
        actionChildren.append(quoteButtonNode)

        let actionStack = ASStackLayoutSpec.horizontal()
        actionStack.spacing = 8
        actionStack.alignItems = .center
        actionStack.children = actionChildren
        headerChildren.append(actionStack)
        headerStack.children = headerChildren

        var textChildren: [ASLayoutElement] = headerChildren.isEmpty ? [] : [headerStack]
        for bodyNode in bodyNodes {
            textChildren.append(bodyNode)
        }

        let textStack = ASStackLayoutSpec.vertical()
        textStack.spacing = Layout.bodySpacing
        textStack.children = textChildren
        textStack.style.flexGrow = 1
        textStack.style.flexShrink = 1
        if let textColumnWidth = Layout.textColumnWidth(
            for: constrainedSize.max.width,
            includingAvatar: hasDisplayableAuthor
        ) {
            textStack.style.width = ASDimension(unit: .points, value: textColumnWidth)
        }

        let contentStack = ASStackLayoutSpec.horizontal()
        contentStack.spacing = PostDetailContentLayout.avatarSpacing
        contentStack.alignItems = .start
        contentStack.children = hasDisplayableAuthor ? [avatarNode, textStack] : [textStack]

        let rowContent = ASInsetLayoutSpec(
            insets: UIEdgeInsets(
                top: PostDetailContentLayout.commentTopInset,
                left: PostDetailContentLayout.horizontalInset,
                bottom: PostDetailContentLayout.commentBottomInset,
                right: PostDetailContentLayout.horizontalInset
            ),
            child: contentStack
        )

        let stack = ASStackLayoutSpec.vertical()
        stack.children = [rowContent, separatorNode]
        return stack
    }

    private func configureText() {
        authorButtonNode.setAttributedTitle(
            NSAttributedString(
                string: AuthorDisplayPolicy.displayName(from: comment.authorName) ?? "",
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .headline),
                    .foregroundColor: UIColor.label
                ]
            ),
            for: .normal
        )
        authorButtonNode.accessibilityLabel = "查看 \(AuthorDisplayPolicy.displayName(from: comment.authorName) ?? "作者") 的主页"

        posterBadgeNode.maximumNumberOfLines = 1
        posterBadgeNode.attributedText = NSAttributedString(
            string: "楼主",
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .caption2),
                .foregroundColor: UIColor.systemOrange
            ]
        )
        posterBadgeNode.accessibilityLabel = "楼主"

        timeNode.maximumNumberOfLines = 1
        timeNode.truncationMode = .byTruncatingTail
        timeNode.attributedText = NSAttributedString(
            string: comment.createdAtText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .subheadline),
                .foregroundColor: UIColor.secondaryLabel
            ]
        )

        floorNode.maximumNumberOfLines = 1
        floorNode.attributedText = NSAttributedString(
            string: comment.floorText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .subheadline),
                .foregroundColor: UIColor.tertiaryLabel
            ]
        )

        configureActionButton(replyButtonNode, title: "回复", accessibilityLabel: "回复评论")
        configureActionButton(quoteButtonNode, title: "引用", accessibilityLabel: "引用评论")
    }

    private func configureActions() {
        authorButtonNode.isUserInteractionEnabled = hasAuthorProfileLink
        if hasAuthorProfileLink {
            authorButtonNode.addTarget(self, action: #selector(authorTapped), forControlEvents: .touchUpInside)
        }
        replyButtonNode.addTarget(self, action: #selector(replyTapped), forControlEvents: .touchUpInside)
        quoteButtonNode.addTarget(self, action: #selector(quoteTapped), forControlEvents: .touchUpInside)
    }

    private func configureActionButton(_ button: ASButtonNode, title: String, accessibilityLabel: String) {
        button.setAttributedTitle(
            NSAttributedString(
                string: title,
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .subheadline),
                    .foregroundColor: UIColor.secondaryLabel
                ]
            ),
            for: .normal
        )
        button.accessibilityLabel = accessibilityLabel
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

    var debugAuthorAttributedTitle: NSAttributedString? {
        authorButtonNode.attributedTitle(for: .normal)
    }

    var debugPosterBadgeAttributedText: NSAttributedString? {
        comment.isPoster ? posterBadgeNode.attributedText : nil
    }

    @objc private func replyTapped() {
        onReplyTapped(comment)
    }

    @objc private func quoteTapped() {
        onQuoteTapped(comment)
    }

    @objc private func authorTapped() {
        guard let authorProfileURL = comment.authorProfileURL else { return }
        onAuthorTapped(authorProfileURL)
    }

    private func requestAvatarIfNeeded() {
        guard hasDisplayableAuthor else { return }
        guard !hasRequestedAvatar else { return }
        guard let avatarImageView else { return }
        hasRequestedAvatar = true
        avatarLoader.loadAvatar(into: avatarImageView, postID: comment.id, avatarURL: comment.avatarURL)
    }

    private func cancelAvatarLoad() {
        guard let avatarImageView else { return }
        avatarLoader.cancel(on: avatarImageView)
    }
}
