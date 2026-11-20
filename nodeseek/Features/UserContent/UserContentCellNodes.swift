//
//  UserContentCellNodes.swift
//  nodeseek
//
//  Created by Codex on 2026/5/11.
//

import AsyncDisplayKit
import UIKit

final class UserContentSkeletonCellNode: ASCellNode {
    private enum Layout {
        static let contentInset = UIEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)
        static let titleHeight: CGFloat = 18
        static let metaHeight: CGFloat = 13
    }

    private let titlePlaceholder = ASDisplayNode()
    private let metaPlaceholder = ASDisplayNode()
    private let extraPlaceholder = ASDisplayNode()

    private lazy var placeholderNodes = [
        titlePlaceholder,
        metaPlaceholder,
        extraPlaceholder
    ]

    override init() {
        super.init()
        automaticallyManagesSubnodes = true
        selectionStyle = .none
        backgroundColor = .clear
        configurePlaceholders()
    }

    override func didLoad() {
        super.didLoad()
        startPulseAnimation()
    }

    override func didEnterVisibleState() {
        super.didEnterVisibleState()
        startPulseAnimation()
    }

    override func didExitVisibleState() {
        super.didExitVisibleState()
        stopPulseAnimation()
    }

    deinit {
        stopPulseAnimation()
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let bottomStack = ASStackLayoutSpec.horizontal()
        bottomStack.spacing = 8
        bottomStack.children = [metaPlaceholder, extraPlaceholder]

        let stack = ASStackLayoutSpec.vertical()
        stack.spacing = 9
        stack.children = [titlePlaceholder, bottomStack]
        return ASInsetLayoutSpec(insets: Layout.contentInset, child: stack)
    }

    private func configurePlaceholders() {
        titlePlaceholder.style.height = ASDimension(unit: .points, value: Layout.titleHeight)
        titlePlaceholder.style.width = ASDimension(unit: .fraction, value: 0.82)
        titlePlaceholder.cornerRadius = 5

        metaPlaceholder.style.height = ASDimension(unit: .points, value: Layout.metaHeight)
        metaPlaceholder.style.width = ASDimension(unit: .fraction, value: 0.28)
        metaPlaceholder.cornerRadius = 4

        extraPlaceholder.style.height = ASDimension(unit: .points, value: Layout.metaHeight)
        extraPlaceholder.style.width = ASDimension(unit: .fraction, value: 0.18)
        extraPlaceholder.cornerRadius = 4

        for node in placeholderNodes {
            node.backgroundColor = .systemGray5
            node.clipsToBounds = true
        }
    }

    private func startPulseAnimation() {
        for node in placeholderNodes {
            guard node.layer.animation(forKey: "user_content_skeleton_pulse") == nil else { continue }
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = 1.0
            animation.toValue = 0.45
            animation.duration = 0.8
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            node.layer.add(animation, forKey: "user_content_skeleton_pulse")
        }
    }

    private func stopPulseAnimation() {
        for node in placeholderNodes {
            node.layer.removeAnimation(forKey: "user_content_skeleton_pulse")
        }
    }
}

final class UserDiscussionCellNode: ASCellNode {
    private let titleNode = ASTextNode()

    init(record: UserDiscussionRecord) {
        super.init()
        automaticallyManagesSubnodes = true
        backgroundColor = .clear
        selectionStyle = .default
        titleNode.maximumNumberOfLines = 2
        titleNode.attributedText = UserContentText.title(record.title)
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        ASInsetLayoutSpec(insets: UIEdgeInsets(top: 13, left: 18, bottom: 13, right: 18), child: titleNode)
    }
}

final class UserCollectionCellNode: ASCellNode {
    private let titleNode = ASTextNode()

    init(record: UserCollectionRecord) {
        super.init()
        automaticallyManagesSubnodes = true
        backgroundColor = .clear
        selectionStyle = .default
        titleNode.maximumNumberOfLines = 2
        titleNode.accessibilityIdentifier = "user-collection-post-\(record.postID)"
        titleNode.attributedText = UserContentText.title(record.title)
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        ASInsetLayoutSpec(insets: UIEdgeInsets(top: 13, left: 18, bottom: 13, right: 18), child: titleNode)
    }
}

final class UserCommentGroupCellNode: ASCellNode {
    private let titleNode = ASTextNode()
    private let replies: [UserCommentReplyNode]

    init(group: UserCommentGroup, traits: UITraitCollection = .current, onOpenComment: @escaping (UserCommentRecord) -> Void) {
        replies = group.comments.map { record in
            UserCommentReplyNode(record: record, traits: traits, onOpenComment: { onOpenComment(record) })
        }
        super.init()
        automaticallyManagesSubnodes = true
        selectionStyle = .default
        backgroundColor = .clear
        titleNode.maximumNumberOfLines = 0
        let title = NSMutableAttributedString(attributedString: UserContentText.title(group.title))
        title.addAttribute(.foregroundColor, value: ReadingColors.text.resolvedColor(with: traits), range: NSRange(location: 0, length: title.length))
        titleNode.attributedText = title
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let stack = ASStackLayoutSpec.vertical()
        stack.spacing = 4
        stack.children = [titleNode] + replies.map { $0 as ASLayoutElement }
        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 12, left: 18, bottom: 8, right: 12),
            child: stack
        )
    }
}

/// 整行可点：点回复文字和点右侧气泡一样跳到对应楼层，点标题仍打开帖子开头。
private final class UserCommentReplyNode: ASControlNode {
    private let textNode = ASTextNode()
    private let commentJumpButton = ASButtonNode()
    private let onOpenComment: () -> Void

    init(
        record: UserCommentRecord,
        traits: UITraitCollection,
        onOpenComment: @escaping () -> Void
    ) {
        self.onOpenComment = onOpenComment
        super.init()
        automaticallyManagesSubnodes = true
        backgroundColor = .clear
        textNode.maximumNumberOfLines = 2
        textNode.attributedText = Self.commentText(record.text, traits: traits)
        configureCommentJumpButton(floorID: record.floorID, traits: traits)
        addTarget(self, action: #selector(openCommentTapped), forControlEvents: .touchUpInside)
        // 整行合并成一个按钮元素，旁白读出楼层和回复内容
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "打开评论 #\(record.floorID)"
        accessibilityValue = textNode.attributedText?.string
    }

    override func didLoad() {
        super.didLoad()
        commentJumpButton.addTarget(self, action: #selector(openCommentTapped), forControlEvents: .touchUpInside)
    }

    override var isHighlighted: Bool {
        didSet { textNode.alpha = isHighlighted ? 0.5 : 1 }
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let textStack = ASStackLayoutSpec.vertical()
        textStack.spacing = 5
        textStack.style.flexGrow = 1
        textStack.style.flexShrink = 1
        textStack.children = [textNode]

        let row = ASStackLayoutSpec.horizontal()
        row.spacing = 10
        row.alignItems = .center
        row.children = [textStack, commentJumpButton]
        return row
    }

    private func configureCommentJumpButton(floorID: Int, traits: UITraitCollection) {
        let configuration = UIImage.SymbolConfiguration(
            font: PostListCellStyle.Typography.metadataFont,
            scale: .medium
        )
        let image = UIImage(systemName: "text.bubble", withConfiguration: configuration)?
            .withTintColor(.secondaryLabel.resolvedColor(with: traits), renderingMode: .alwaysOriginal)
        commentJumpButton.setImage(image, for: .normal)
        commentJumpButton.tintColor = .secondaryLabel
        commentJumpButton.style.preferredSize = CGSize(width: 44, height: 44)
        commentJumpButton.accessibilityLabel = "打开评论 #\(floorID)"
    }

    private static func commentText(_ text: String, traits: UITraitCollection) -> NSAttributedString {
        NSAttributedString(
            string: text.trimmingCharacters(in: .whitespacesAndNewlines),
            attributes: [
                .font: PostListCellStyle.Typography.metadataFont,
                .foregroundColor: UIColor.secondaryLabel.resolvedColor(with: traits)
            ]
        )
    }

    @objc private func openCommentTapped() {
        onOpenComment()
    }
}

enum UserContentText {
    static func title(_ title: String) -> NSAttributedString {
        NSAttributedString(
            string: title,
            attributes: [
                .font: PostListCellStyle.Typography.titleFont,
                .foregroundColor: ReadingColors.text
            ]
        )
    }
}
