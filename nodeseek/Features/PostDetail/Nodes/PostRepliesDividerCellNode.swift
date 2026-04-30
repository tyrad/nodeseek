//
//  PostRepliesDividerCellNode.swift
//  nodeseek
//
//  Created by Codex on 2026/4/30.
//

import AsyncDisplayKit
import UIKit

final class PostRepliesDividerCellNode: ASCellNode {
    private enum Layout {
        static let height: CGFloat = 8
    }

    private let dividerNode = ASDisplayNode()

    override init() {
        super.init()
        automaticallyManagesSubnodes = true
        selectionStyle = .none
        backgroundColor = .systemBackground
        dividerNode.backgroundColor = .secondarySystemBackground
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        dividerNode.style.height = ASDimension(unit: .points, value: Layout.height)
        if constrainedSize.max.width.isFinite {
            dividerNode.style.width = ASDimension(unit: .points, value: constrainedSize.max.width)
        }
        return ASInsetLayoutSpec(insets: .zero, child: dividerNode)
    }
}
