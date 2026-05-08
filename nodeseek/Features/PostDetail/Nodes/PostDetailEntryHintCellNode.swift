//
//  PostDetailEntryHintCellNode.swift
//  nodeseek
//
//  Created by Codex on 2026/5/8.
//

import AsyncDisplayKit
import UIKit

final class PostDetailEntryHintCellNode: ASCellNode, ThemeRefreshableNode {
    private enum Layout {
        static let contentInset = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        static let containerInset = UIEdgeInsets(top: 0, left: 12, bottom: 8, right: 12)
        static let spacing: CGFloat = 10
        static let buttonHeight: CGFloat = 34
    }

    private let page: Int
    private let onOpenFullPost: () -> Void
    private let containerNode = ASDisplayNode()
    private let textNode = ASTextNode()
    private let buttonNode = ASButtonNode()
    private let themeTraitObserver = ThemeTraitObserver()

    init(page: Int, onOpenFullPost: @escaping () -> Void) {
        self.page = max(1, page)
        self.onOpenFullPost = onOpenFullPost
        super.init()
        automaticallyManagesSubnodes = true
        selectionStyle = .none
        configureNodes()
        applyCurrentTheme()
    }

    private func configureNodes() {
        containerNode.cornerRadius = 8

        textNode.maximumNumberOfLines = 1
        textNode.truncationMode = .byTruncatingTail

        buttonNode.cornerRadius = 8
        buttonNode.contentEdgeInsets = UIEdgeInsets(top: 7, left: 10, bottom: 7, right: 10)
        buttonNode.accessibilityLabel = "查看完整帖子"
        buttonNode.addTarget(self, action: #selector(openFullPostTapped), forControlEvents: .touchUpInside)
    }

    override func didLoad() {
        super.didLoad()
        themeTraitObserver.install(on: self)
    }

    func applyCurrentTheme() {
        backgroundColor = .systemBackground
        containerNode.backgroundColor = .secondarySystemBackground
        textNode.attributedText = NSAttributedString(
            string: "当前从第 \(page) 页进入",
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .footnote),
                .foregroundColor: UIColor.secondaryLabel
            ]
        )

        let buttonFont = UIFont.preferredFont(forTextStyle: .footnote)
        buttonNode.backgroundColor = .label
        buttonNode.setAttributedTitle(
            NSAttributedString(
                string: "查看完整帖子",
                attributes: [
                    .font: buttonFont,
                    .foregroundColor: UIColor.systemBackground
                ]
            ),
            for: .normal
        )
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        buttonNode.style.height = ASDimension(unit: .points, value: Layout.buttonHeight)
        buttonNode.style.flexShrink = 0
        textNode.style.flexGrow = 1
        textNode.style.flexShrink = 1

        let row = ASStackLayoutSpec.horizontal()
        row.alignItems = .center
        row.spacing = Layout.spacing
        row.children = [textNode, buttonNode]

        let content = ASInsetLayoutSpec(insets: Layout.contentInset, child: row)
        let background = ASBackgroundLayoutSpec(child: content, background: containerNode)
        return ASInsetLayoutSpec(insets: Layout.containerInset, child: background)
    }

    @objc
    private func openFullPostTapped() {
        onOpenFullPost()
    }
}
