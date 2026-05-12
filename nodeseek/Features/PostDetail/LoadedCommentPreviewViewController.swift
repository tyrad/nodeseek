//
//  LoadedCommentPreviewViewController.swift
//  nodeseek
//
//  Created by Codex on 2026/5/9.
//

import AsyncDisplayKit
import UIKit

final class LoadedCommentPreviewViewController: UIViewController {
    private enum Layout {
        static let minimumWidth: CGFloat = 320
        static let maximumWidth: CGFloat = 420
        static let minimumHeight: CGFloat = 220
        static let maximumHeightRatio: CGFloat = 0.72
        static let fallbackContainerWidth: CGFloat = 390
        static let fallbackContainerHeight: CGFloat = 844
        static let headerHeight: CGFloat = 56
        static let footerHeight: CGFloat = 86
        static let verticalChrome: CGFloat = 54
        static let estimatedNonTextBlockHeight: CGFloat = 120
    }

    private let comment: Comment
    private let renderedContent: [RenderedContentBlock]?
    private let showsFullPostButton: Bool
    private let onOpenFullPost: () -> Void
    private let onReveal: () -> Void
    private let tableNode = ASTableNode(style: .plain)
    private let headerView = UIView()
    private let headerSeparator = UIView()
    private let footerStack = UIStackView()
    private let fullPostButton = UIButton(type: .system)
    private let revealButton = UIButton(type: .system)

    init(
        comment: Comment,
        renderedContent: [RenderedContentBlock]?,
        showsFullPostButton: Bool,
        onOpenFullPost: @escaping () -> Void,
        onReveal: @escaping () -> Void
    ) {
        self.comment = comment
        self.renderedContent = renderedContent
        self.showsFullPostButton = showsFullPostButton
        self.onOpenFullPost = onOpenFullPost
        self.onReveal = onReveal
        super.init(nibName: nil, bundle: nil)
    }

    static func preferredSize(
        comment: Comment,
        renderedContent: [RenderedContentBlock]?,
        containerSize: CGSize
    ) -> CGSize {
        let containerWidth = containerSize.width > 0 ? containerSize.width : Layout.fallbackContainerWidth
        let containerHeight = containerSize.height > 0 ? containerSize.height : Layout.fallbackContainerHeight
        let width = min(max(containerWidth - 32, Layout.minimumWidth), Layout.maximumWidth)
        let textWidth = max(
            width
                - PostDetailContentLayout.horizontalInset * 2
                - PostDetailContentLayout.avatarSize
                - PostDetailContentLayout.avatarSpacing,
            1
        )
        let bodyHeight = estimatedBodyHeight(
            comment: comment,
            renderedContent: renderedContent,
            width: textWidth
        )
        let rawHeight = Layout.headerHeight + Layout.footerHeight + Layout.verticalChrome + bodyHeight
        let maximumHeight = max(Layout.minimumHeight, floor(containerHeight * Layout.maximumHeightRatio))
        return CGSize(
            width: width,
            height: min(max(ceil(rawHeight), Layout.minimumHeight), maximumHeight)
        )
    }

    private static func estimatedBodyHeight(
        comment: Comment,
        renderedContent: [RenderedContentBlock]?,
        width: CGFloat
    ) -> CGFloat {
        let bodyFont = UIFont.preferredFont(forTextStyle: .body)
        var textHeight: CGFloat = 0
        var extraBlockHeight: CGFloat = 0
        if let renderedContent, renderedContent.isEmpty == false {
            for block in renderedContent {
                switch block {
                case .text(let attributedText):
                    textHeight += estimatedTextHeight(attributedText.string, width: width, font: bodyFont)
                case .image, .iframeLink, .imagePlaceholder, .table, .codeBlock, .unsupported, .quote:
                    extraBlockHeight += Layout.estimatedNonTextBlockHeight
                }
            }
        } else {
            textHeight = estimatedTextHeight(comment.contentHTML, width: width, font: bodyFont)
        }
        return max(
            PostDetailContentLayout.avatarSize,
            textHeight + extraBlockHeight + 96
        )
    }

    private static func estimatedTextHeight(_ text: String, width: CGFloat, font: UIFont) -> CGFloat {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedText.isEmpty == false else {
            return font.lineHeight
        }
        let rect = (normalizedText as NSString).boundingRect(
            with: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return ceil(rect.height)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.layer.cornerRadius = 12
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
        tableNode.dataSource = self
        tableNode.delegate = self
        configureContent()
        applyCurrentTheme()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
        applyCurrentTheme()
    }

    private func applyCurrentTheme() {
        view.backgroundColor = .systemBackground
        headerView.backgroundColor = .systemBackground
        tableNode.view.backgroundColor = .systemBackground
        headerSeparator.backgroundColor = .separator
    }

    private func configureContent() {
        headerView.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .secondaryLabel
        closeButton.accessibilityLabel = "关闭"
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        headerSeparator.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(closeButton)
        headerView.addSubview(headerSeparator)

        var fullPostConfiguration = UIButton.Configuration.bordered()
        fullPostConfiguration.title = "查看完整帖子"
        fullPostConfiguration.baseForegroundColor = .label
        fullPostConfiguration.cornerStyle = .medium
        fullPostConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
        fullPostButton.configuration = fullPostConfiguration
        fullPostButton.addTarget(self, action: #selector(fullPostTapped), for: .touchUpInside)
        fullPostButton.titleLabel?.adjustsFontSizeToFitWidth = true
        fullPostButton.titleLabel?.minimumScaleFactor = 0.85

        var revealConfiguration = UIButton.Configuration.filled()
        revealConfiguration.title = "查看原楼"
        revealConfiguration.baseBackgroundColor = .secondarySystemBackground
        revealConfiguration.baseForegroundColor = .label
        revealConfiguration.cornerStyle = .medium
        revealConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
        revealButton.configuration = revealConfiguration
        revealButton.addTarget(self, action: #selector(revealTapped), for: .touchUpInside)
        revealButton.titleLabel?.adjustsFontSizeToFitWidth = true
        revealButton.titleLabel?.minimumScaleFactor = 0.85

        footerStack.axis = .horizontal
        footerStack.alignment = .fill
        footerStack.distribution = .fillEqually
        footerStack.spacing = 10
        footerStack.translatesAutoresizingMaskIntoConstraints = false
        if showsFullPostButton {
            footerStack.addArrangedSubview(fullPostButton)
        }
        footerStack.addArrangedSubview(revealButton)

        tableNode.view.separatorStyle = .none
        tableNode.view.alwaysBounceVertical = false
        tableNode.contentInset = UIEdgeInsets(top: 12, left: 0, bottom: 14, right: 0)
        tableNode.view.verticalScrollIndicatorInsets = tableNode.contentInset
        tableNode.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableNode.view)
        view.addSubview(headerView)
        view.addSubview(footerStack)

        NSLayoutConstraint.activate([
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.heightAnchor.constraint(equalToConstant: Layout.headerHeight),

            headerSeparator.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            headerSeparator.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            headerSeparator.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),
            headerSeparator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),

            tableNode.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableNode.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableNode.view.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            tableNode.view.bottomAnchor.constraint(equalTo: footerStack.topAnchor, constant: -12),

            footerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            footerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            footerStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            footerStack.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),

            closeButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -8),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    @objc
    private func closeTapped() {
        dismiss(animated: true)
    }

    @objc
    private func fullPostTapped() {
        onOpenFullPost()
    }

    @objc
    private func revealTapped() {
        onReveal()
    }
}

extension LoadedCommentPreviewViewController: ASTableDataSource, ASTableDelegate {
    func tableNode(_ tableNode: ASTableNode, numberOfRowsInSection section: Int) -> Int {
        1
    }

    func tableNode(_ tableNode: ASTableNode, nodeBlockForRowAt indexPath: IndexPath) -> ASCellNodeBlock {
        let comment = comment
        let renderedContent = renderedContent
        return { [weak self] in
            CommentCellNode(
                comment: comment,
                renderedBody: renderedContent,
                onImageTapped: { _, _ in },
                onLinkTapped: { _ in },
                onAuthorTapped: { _ in },
                onLikeTapped: { _ in },
                onChickenLegTapped: { _ in },
                onOpposeTapped: { _ in },
                onReplyTapped: { _ in },
                onQuoteTapped: { _ in },
                onTextLayoutInvalidated: {
                    self?.tableNode.relayoutItems()
                }
            )
        }
    }
}
