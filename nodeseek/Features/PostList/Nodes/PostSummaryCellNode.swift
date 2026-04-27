//
//  PostSummaryCellNode.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import AsyncDisplayKit
import UIKit

final class PostSummaryCellNode: ASCellNode {

    private enum Layout {
        static let horizontalSpacing: CGFloat = 12
        static let verticalSpacing: CGFloat = 6
        static let avatarSize: CGFloat = 56
        static let contentInset = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 12)
    }

    private let post: PostSummary
    private let avatarLoader = AvatarImageLoader.shared
    private var hasRequestedAvatar = false

    private lazy var avatarNode: ASDisplayNode = {
        let node = ASDisplayNode(viewBlock: { [weak self] in
            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFill
            imageView.layer.cornerRadius = 10
            imageView.layer.masksToBounds = true
            imageView.backgroundColor = .systemGray5
            self?.avatarImageView = imageView
            return imageView
        })
        node.style.preferredSize = CGSize(width: Layout.avatarSize, height: Layout.avatarSize)
        return node
    }()

    private let titleNode = ASTextNode()
    private let metadataNode = ASTextNode()
    private weak var avatarImageView: UIImageView?

    init(post: PostSummary) {
        self.post = post
        super.init()
        automaticallyManagesSubnodes = true
        selectionStyle = .none
        backgroundColor = .clear
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

    deinit {
        cancelAvatarLoad()
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        titleNode.style.flexShrink = 1
        metadataNode.style.flexShrink = 1

        let textStack = ASStackLayoutSpec.vertical()
        textStack.spacing = Layout.verticalSpacing
        textStack.children = [titleNode, metadataNode]
        textStack.style.flexGrow = 1
        textStack.style.flexShrink = 1

        let contentStack = ASStackLayoutSpec.horizontal()
        contentStack.spacing = Layout.horizontalSpacing
        contentStack.alignItems = .center
        contentStack.children = [avatarNode, textStack]

        return ASInsetLayoutSpec(insets: Layout.contentInset, child: contentStack)
    }

    private func configureText() {
        titleNode.maximumNumberOfLines = 0
        titleNode.attributedText = NSAttributedString(
            string: post.title,
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .headline),
                .foregroundColor: UIColor.label
            ]
        )

        metadataNode.maximumNumberOfLines = 1
        metadataNode.attributedText = NSAttributedString(
            string: Self.metadataText(for: post),
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
        avatarLoader.loadAvatar(into: avatarImageView, postID: post.id, avatarURL: post.avatarURL)
    }

    private func cancelAvatarLoad() {
        guard let avatarImageView else { return }
        avatarLoader.cancel(on: avatarImageView)
    }

    private static func metadataText(for post: PostSummary) -> String {
        var parts = [
            post.authorName,
            post.nodeName ?? "NodeSeek",
            "\(post.replyCount) 回复"
        ]

        if let lastActive = post.lastActivityText?.trimmingCharacters(in: .whitespacesAndNewlines), !lastActive.isEmpty {
            parts.append(lastActive)
        }

        return parts.joined(separator: " · ")
    }
}
