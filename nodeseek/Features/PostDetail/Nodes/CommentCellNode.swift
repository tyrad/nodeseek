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

        static func textColumnWidth(for maxWidth: CGFloat) -> CGFloat? {
            guard maxWidth.isFinite, maxWidth > 0 else { return nil }
            let chromeWidth = PostDetailContentLayout.horizontalInset * 2
                + PostDetailContentLayout.avatarSize
                + PostDetailContentLayout.avatarSpacing
            return max(maxWidth - chromeWidth, 1)
        }
    }

    private let comment: Comment
    private let onImageTapped: ([URL], Int) -> Void
    private let onLinkTapped: (URL) -> Void
    private let onTextLayoutInvalidated: () -> Void
    private let avatarLoader = AvatarImageLoader.shared
    private weak var avatarImageView: UIImageView?
    private var hasRequestedAvatar = false

    private let authorNode = ASTextNode()
    private let timeNode = ASTextNode()
    private let floorNode = ASTextNode()
    private let separatorNode = ASDisplayNode()
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
        comment: Comment,
        renderedBody: [RenderedContentBlock]?,
        onImageTapped: @escaping ([URL], Int) -> Void,
        onLinkTapped: @escaping (URL) -> Void = { _ in },
        onTextLayoutInvalidated: @escaping () -> Void
    ) {
        self.comment = comment
        self.onImageTapped = onImageTapped
        self.onLinkTapped = onLinkTapped
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
        authorNode.style.flexShrink = 1
        timeNode.style.flexShrink = 1
        floorNode.style.flexShrink = 0
        separatorNode.style.height = ASDimension(unit: .points, value: 1 / UIScreen.main.scale)

        let identityStack = ASStackLayoutSpec.horizontal()
        identityStack.spacing = Layout.headerSpacing
        identityStack.alignItems = .center
        identityStack.children = [authorNode, timeNode]
        identityStack.style.flexGrow = 1
        identityStack.style.flexShrink = 1

        let headerStack = ASStackLayoutSpec.horizontal()
        headerStack.alignItems = .start
        headerStack.justifyContent = .spaceBetween
        headerStack.children = [identityStack, floorNode]

        var textChildren: [ASLayoutElement] = [headerStack]
        for bodyNode in bodyNodes {
            textChildren.append(bodyNode)
        }

        let textStack = ASStackLayoutSpec.vertical()
        textStack.spacing = Layout.bodySpacing
        textStack.children = textChildren
        textStack.style.flexGrow = 1
        textStack.style.flexShrink = 1
        if let textColumnWidth = Layout.textColumnWidth(for: constrainedSize.max.width) {
            textStack.style.width = ASDimension(unit: .points, value: textColumnWidth)
        }

        let contentStack = ASStackLayoutSpec.horizontal()
        contentStack.spacing = PostDetailContentLayout.avatarSpacing
        contentStack.alignItems = .start
        contentStack.children = [avatarNode, textStack]

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
        authorNode.maximumNumberOfLines = 1
        authorNode.truncationMode = .byTruncatingTail
        authorNode.attributedText = NSAttributedString(
            string: comment.authorName,
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .headline),
                .foregroundColor: UIColor.label
            ]
        )

        timeNode.maximumNumberOfLines = 1
        timeNode.truncationMode = .byTruncatingTail
        timeNode.attributedText = NSAttributedString(
            string: comment.createdAtText ?? "",
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .subheadline),
                .foregroundColor: UIColor.secondaryLabel
            ]
        )

        floorNode.maximumNumberOfLines = 1
        floorNode.attributedText = NSAttributedString(
            string: comment.floorText ?? "",
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .subheadline),
                .foregroundColor: UIColor.tertiaryLabel
            ]
        )
    }

    private func requestAvatarIfNeeded() {
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
