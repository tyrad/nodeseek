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
    /// 跳页后列表从中间页开始：文案说明起始页，按钮改为原地回到第 1 页。
    private let isAfterPageJump: Bool
    private let onOpenFullPost: () -> Void
    private let containerNode = ASDisplayNode()
    private let textNode = ASTextNode()
    private let buttonNode = ASButtonNode()
    private let themeTraitObserver = ThemeTraitObserver()

    init(page: Int, isAfterPageJump: Bool = false, onOpenFullPost: @escaping () -> Void) {
        self.page = max(1, page)
        self.isAfterPageJump = isAfterPageJump
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
        buttonNode.accessibilityLabel = buttonTitle
        buttonNode.addTarget(self, action: #selector(openFullPostTapped), forControlEvents: .touchUpInside)
    }

    override func didLoad() {
        super.didLoad()
        themeTraitObserver.install(on: self)
    }

    func applyCurrentTheme() {
        backgroundColor = UIColor.systemBackground
        containerNode.backgroundColor = .secondarySystemBackground
        textNode.attributedText = NSAttributedString(
            string: isAfterPageJump ? "当前从第 \(page) 页开始" : "当前从第 \(page) 页进入",
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .footnote),
                .foregroundColor: UIColor.secondaryLabel
            ]
        )

        let buttonFont = UIFont.preferredFont(forTextStyle: .footnote)
        buttonNode.backgroundColor = .label
        buttonNode.setAttributedTitle(
            NSAttributedString(
                string: buttonTitle,
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

    private var buttonTitle: String {
        isAfterPageJump ? "回到第 1 页" : "查看完整帖子"
    }

    @objc
    private func openFullPostTapped() {
        onOpenFullPost()
    }
}
