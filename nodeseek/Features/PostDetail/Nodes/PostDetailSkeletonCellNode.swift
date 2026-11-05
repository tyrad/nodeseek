//
//  PostDetailSkeletonCellNode.swift
//  nodeseek
//
//  Created by Codex on 2026/4/28.
//

import AsyncDisplayKit
import UIKit

final class PostDetailSkeletonCellNode: ASCellNode {
    enum Kind {
        case header
        case comment
    }

    private enum Layout {
        static let horizontalInset: CGFloat = 20
        static let commentHorizontalInset: CGFloat = 12
        static let verticalInset: CGFloat = 10
        static let cardInset: CGFloat = 12
        static let avatarSize: CGFloat = 40
        static let avatarCornerRadius: CGFloat = 8
        static let avatarSpacing: CGFloat = 12
        static let lineSpacing: CGFloat = 10
        static let titleHeight: CGFloat = 22
        static let metaHeight: CGFloat = 14
        static let bodyHeight: CGFloat = 16
        static let imageHeight: CGFloat = 180
    }

    private let kind: Kind
    private let avatarPlaceholder = ASDisplayNode()
    private let titlePlaceholder = ASDisplayNode()
    private let metaPlaceholder = ASDisplayNode()
    private let bodyPlaceholder1 = ASDisplayNode()
    private let bodyPlaceholder2 = ASDisplayNode()
    private let bodyPlaceholder3 = ASDisplayNode()
    private let imagePlaceholder = ASDisplayNode()
    private let cardNode = ASDisplayNode()

    private lazy var placeholderNodes: [ASDisplayNode] = [
        avatarPlaceholder,
        titlePlaceholder,
        metaPlaceholder,
        bodyPlaceholder1,
        bodyPlaceholder2,
        bodyPlaceholder3,
        imagePlaceholder
    ]

    init(kind: Kind) {
        self.kind = kind
        super.init()
        automaticallyManagesSubnodes = true
        selectionStyle = .none
        backgroundColor = UIColor.systemBackground
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
        switch kind {
        case .header:
            return headerLayoutSpec()
        case .comment:
            return commentLayoutSpec()
        }
    }

    private func headerLayoutSpec() -> ASLayoutSpec {
        let metaStack = ASStackLayoutSpec.horizontal()
        metaStack.spacing = Layout.avatarSpacing
        metaStack.alignItems = .center
        metaStack.children = [avatarPlaceholder, metaPlaceholder]

        let bodyStack = ASStackLayoutSpec.vertical()
        bodyStack.spacing = Layout.lineSpacing
        bodyStack.children = [
            titlePlaceholder,
            metaStack,
            bodyPlaceholder1,
            bodyPlaceholder2,
            imagePlaceholder
        ]

        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(
                top: Layout.horizontalInset,
                left: Layout.horizontalInset,
                bottom: Layout.horizontalInset,
                right: Layout.horizontalInset
            ),
            child: bodyStack
        )
    }

    private func commentLayoutSpec() -> ASLayoutSpec {
        let textStack = ASStackLayoutSpec.vertical()
        textStack.spacing = Layout.lineSpacing
        textStack.children = [metaPlaceholder, bodyPlaceholder1, bodyPlaceholder2, bodyPlaceholder3]
        textStack.style.flexGrow = 1
        textStack.style.flexShrink = 1

        let contentStack = ASStackLayoutSpec.horizontal()
        contentStack.spacing = Layout.avatarSpacing
        contentStack.alignItems = .start
        contentStack.children = [avatarPlaceholder, textStack]

        let cardContent = ASInsetLayoutSpec(
            insets: UIEdgeInsets(
                top: Layout.cardInset,
                left: Layout.cardInset,
                bottom: Layout.cardInset,
                right: Layout.cardInset
            ),
            child: contentStack
        )
        let background = ASBackgroundLayoutSpec(child: cardContent, background: cardNode)
        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(
                top: Layout.verticalInset,
                left: Layout.commentHorizontalInset,
                bottom: Layout.verticalInset,
                right: Layout.commentHorizontalInset
            ),
            child: background
        )
    }

    private func configurePlaceholders() {
        avatarPlaceholder.style.preferredSize = CGSize(width: Layout.avatarSize, height: Layout.avatarSize)
        avatarPlaceholder.cornerRadius = Layout.avatarCornerRadius

        titlePlaceholder.style.height = ASDimension(unit: .points, value: Layout.titleHeight)
        titlePlaceholder.style.width = ASDimension(unit: .fraction, value: 0.82)
        titlePlaceholder.cornerRadius = 6

        metaPlaceholder.style.height = ASDimension(unit: .points, value: Layout.metaHeight)
        metaPlaceholder.style.width = ASDimension(unit: .fraction, value: kind == .header ? 0.48 : 0.42)
        metaPlaceholder.cornerRadius = 4

        bodyPlaceholder1.style.height = ASDimension(unit: .points, value: Layout.bodyHeight)
        bodyPlaceholder1.style.width = ASDimension(unit: .fraction, value: 0.95)
        bodyPlaceholder1.cornerRadius = 5

        bodyPlaceholder2.style.height = ASDimension(unit: .points, value: Layout.bodyHeight)
        bodyPlaceholder2.style.width = ASDimension(unit: .fraction, value: 0.76)
        bodyPlaceholder2.cornerRadius = 5

        bodyPlaceholder3.style.height = ASDimension(unit: .points, value: Layout.bodyHeight)
        bodyPlaceholder3.style.width = ASDimension(unit: .fraction, value: 0.58)
        bodyPlaceholder3.cornerRadius = 5

        imagePlaceholder.style.height = ASDimension(unit: .points, value: Layout.imageHeight)
        imagePlaceholder.style.width = ASDimension(unit: .fraction, value: 1)
        imagePlaceholder.cornerRadius = 8

        cardNode.backgroundColor = .secondarySystemBackground
        cardNode.cornerRadius = 8

        for node in placeholderNodes {
            node.backgroundColor = UIColor.systemGray5
            node.clipsToBounds = true
        }
    }

    private func startPulseAnimation() {
        for node in placeholderNodes {
            guard node.layer.animation(forKey: "skeleton_pulse") == nil else { continue }
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = 1.0
            animation.toValue = 0.45
            animation.duration = 0.8
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            node.layer.add(animation, forKey: "skeleton_pulse")
        }
    }

    private func stopPulseAnimation() {
        for node in placeholderNodes {
            node.layer.removeAnimation(forKey: "skeleton_pulse")
        }
    }
}
