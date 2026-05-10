//
//  PostSummarySkeletonCellNode.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import AsyncDisplayKit
import UIKit

final class PostSummarySkeletonCellNode: ASCellNode {

    private enum Layout {
        static let verticalSpacing: CGFloat = 8
        static let titleHeight: CGFloat = 18
        static let metaHeight: CGFloat = 13
        static let contentInset = UIEdgeInsets(
            top: PostListCellStyle.Layout.verticalContentInset,
            left: 16,
            bottom: PostListCellStyle.Layout.verticalContentInset,
            right: 12
        )
    }

    private let avatarPlaceholder = ASDisplayNode()
    private let titlePlaceholder = ASDisplayNode()
    private let metaPlaceholder1 = ASDisplayNode()
    private let metaPlaceholder2 = ASDisplayNode()

    private lazy var placeholderNodes: [ASDisplayNode] = [
        avatarPlaceholder,
        titlePlaceholder,
        metaPlaceholder1,
        metaPlaceholder2
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
        let metaStack = ASStackLayoutSpec.horizontal()
        metaStack.spacing = 8
        metaStack.alignItems = .center
        metaStack.children = [metaPlaceholder1, metaPlaceholder2]

        let textStack = ASStackLayoutSpec.vertical()
        textStack.spacing = Layout.verticalSpacing
        textStack.children = [titlePlaceholder, metaStack]
        textStack.style.flexGrow = 1
        textStack.style.flexShrink = 1

        let contentStack = ASStackLayoutSpec.horizontal()
        contentStack.spacing = PostListCellStyle.Layout.horizontalSpacing
        contentStack.alignItems = .center
        contentStack.children = [avatarPlaceholder, textStack]

        return ASInsetLayoutSpec(insets: Layout.contentInset, child: contentStack)
    }

    private func configurePlaceholders() {
        avatarPlaceholder.style.preferredSize = CGSize(
            width: PostListCellStyle.Avatar.skeletonSize,
            height: PostListCellStyle.Avatar.skeletonSize
        )
        avatarPlaceholder.cornerRadius = PostListCellStyle.Avatar.cornerRadius

        titlePlaceholder.style.height = ASDimension(unit: .points, value: Layout.titleHeight)
        titlePlaceholder.style.width = ASDimension(unit: .fraction, value: 0.78)
        titlePlaceholder.cornerRadius = 5

        metaPlaceholder1.style.height = ASDimension(unit: .points, value: Layout.metaHeight)
        metaPlaceholder1.style.width = ASDimension(unit: .fraction, value: 0.32)
        metaPlaceholder1.cornerRadius = 4

        metaPlaceholder2.style.height = ASDimension(unit: .points, value: Layout.metaHeight)
        metaPlaceholder2.style.width = ASDimension(unit: .fraction, value: 0.22)
        metaPlaceholder2.cornerRadius = 4

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
