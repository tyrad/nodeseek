//
//  PostDetailAuthorFilterBannerCellNode.swift
//  nodeseek
//
//  Created by Codex on 2026/10/29.
//

import AsyncDisplayKit
import UIKit

final class PostDetailAuthorFilterBannerCellNode: ASCellNode, ThemeRefreshableNode {
    private enum Layout {
        static let contentInset = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        static let containerInset = UIEdgeInsets(top: 0, left: 12, bottom: 8, right: 12)
        static let spacing: CGFloat = 10
        static let buttonHeight: CGFloat = 34
    }

    private let text: String
    private let onClear: () -> Void
    private let containerNode = ASDisplayNode()
    private let iconNode = ASImageNode()
    private let textNode = ASTextNode()
    private let buttonNode = ASButtonNode()
    private let themeTraitObserver = ThemeTraitObserver()

    init(text: String, onClear: @escaping () -> Void) {
        self.text = text
        self.onClear = onClear
        super.init()
        automaticallyManagesSubnodes = true
        selectionStyle = .none
        configureNodes()
        applyCurrentTheme()
    }

    private func configureNodes() {
        containerNode.cornerRadius = 8

        iconNode.contentMode = .scaleAspectFit
        iconNode.style.preferredSize = CGSize(width: 16, height: 16)

        textNode.maximumNumberOfLines = 1
        textNode.truncationMode = .byTruncatingTail

        buttonNode.cornerRadius = 8
        buttonNode.contentEdgeInsets = UIEdgeInsets(top: 7, left: 10, bottom: 7, right: 10)
        buttonNode.accessibilityLabel = "查看全部回复"
        buttonNode.addTarget(self, action: #selector(clearTapped), forControlEvents: .touchUpInside)
    }

    override func didLoad() {
        super.didLoad()
        themeTraitObserver.install(on: self)
    }

    func applyCurrentTheme() {
        backgroundColor = .systemBackground
        containerNode.backgroundColor = .secondarySystemBackground
        let font = UIFont.preferredFont(forTextStyle: .footnote)
        iconNode.image = UIImage(
            systemName: "line.3.horizontal.decrease.circle",
            withConfiguration: UIImage.SymbolConfiguration(font: font)
        )?.withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal)
        textNode.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: UIColor.label
            ]
        )

        buttonNode.backgroundColor = .label
        buttonNode.setAttributedTitle(
            NSAttributedString(
                string: "查看全部",
                attributes: [
                    .font: font,
                    .foregroundColor: UIColor.systemBackground
                ]
            ),
            for: .normal
        )
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        buttonNode.style.height = ASDimension(unit: .points, value: Layout.buttonHeight)
        buttonNode.style.flexShrink = 0
        iconNode.style.flexShrink = 0
        textNode.style.flexGrow = 1
        textNode.style.flexShrink = 1

        let row = ASStackLayoutSpec.horizontal()
        row.alignItems = .center
        row.spacing = Layout.spacing
        row.children = [iconNode, textNode, buttonNode]

        let content = ASInsetLayoutSpec(insets: Layout.contentInset, child: row)
        let background = ASBackgroundLayoutSpec(child: content, background: containerNode)
        return ASInsetLayoutSpec(insets: Layout.containerInset, child: background)
    }

    #if DEBUG
    var debugText: String {
        text
    }

    func debugTapClear() {
        clearTapped()
    }
    #endif

    @objc
    private func clearTapped() {
        onClear()
    }
}
