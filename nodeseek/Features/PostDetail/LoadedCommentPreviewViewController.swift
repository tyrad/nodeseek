//
//  LoadedCommentPreviewViewController.swift
//  nodeseek
//
//  Created by Codex on 2026/5/9.
//

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
    }

    private let comment: Comment
    private let baseURL: URL
    private let showsFullPostButton: Bool
    private let onOpenFullPost: () -> Void
    private let onReveal: () -> Void
    private let preview = DetailFloorPreviewScrollView()
    private let headerView = UIView()
    private let headerSeparator = UIView()
    private let footerStack = UIStackView()
    private let fullPostButton = UIButton(type: .system)
    private let revealButton = UIButton(type: .system)

    init(
        comment: Comment,
        baseURL: URL,
        showsFullPostButton: Bool,
        onOpenFullPost: @escaping () -> Void,
        onReveal: @escaping () -> Void
    ) {
        self.comment = comment
        self.baseURL = baseURL
        self.showsFullPostButton = showsFullPostButton
        self.onOpenFullPost = onOpenFullPost
        self.onReveal = onReveal
        super.init(nibName: nil, bundle: nil)
    }

    static func preferredSize(
        comment: Comment,
        containerSize: CGSize
    ) -> CGSize {
        let containerWidth = containerSize.width > 0 ? containerSize.width : Layout.fallbackContainerWidth
        let containerHeight = containerSize.height > 0 ? containerSize.height : Layout.fallbackContainerHeight
        let width = min(containerWidth, max(containerWidth - 32, Layout.minimumWidth), Layout.maximumWidth)
        let textWidth = max(
            width
                - PostDetailContentLayout.horizontalInset * 2
                - PostDetailContentLayout.avatarSize
                - PostDetailContentLayout.avatarSpacing,
            1
        )
        let bodyHeight = estimatedTextHeight(comment.contentHTML, width: textWidth, font: UIFont.preferredFont(forTextStyle: .body))
        let rawHeight = Layout.headerHeight + Layout.footerHeight + Layout.verticalChrome + bodyHeight
        let maximumHeight = max(Layout.minimumHeight, floor(containerHeight * Layout.maximumHeightRatio))
        return CGSize(
            width: width,
            height: min(max(ceil(rawHeight), Layout.minimumHeight), maximumHeight)
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
        preview.configureHeader = { [comment] cell in
            cell.configureHeader(title: nil, requiredLevel: nil, name: comment.authorName, isPoster: comment.isPoster,
                                 badges: comment.authorBadgeTexts, time: comment.createdAtText, floor: comment.floorText, isHot: comment.isHot)
            cell.configureAuthor(name: comment.authorName, avatarURL: comment.avatarURL, profileURL: nil) { _ in }
        }
        preview.floor.addVotes(like: comment.likeCount, chicken: comment.chickenLegCount, oppose: comment.opposeCount,
                               liked: comment.isLikeClicked, rewarded: comment.isChickenLegClicked,
                               opposed: comment.isOpposeClicked, isOwn: comment.isOwnComment)
        if AuthorDisplayPolicy.isDisplayable(comment.authorName) {
            let indent = PostDetailContentLayout.avatarSize + PostDetailContentLayout.avatarSpacing
            preview.floor.textIndent = indent
            preview.floor.body.isLayoutMarginsRelativeArrangement = true
            preview.floor.body.directionalLayoutMargins = .init(top: 0, leading: indent, bottom: 0, trailing: 0)
        }
        let showsSignature = PostSignatureDisplaySettings.shared.showsSignatures
        preview.loadContent = DetailFloorPreviewScrollView.background { [comment, baseURL] width in
            PostDetailViewController.makeRenderedContent(html: comment.contentHTML, signatureHTML: comment.signatureHTML,
                                                         baseURL: baseURL, maxImageWidth: width, showsSignature: showsSignature)
        }
        preview.onMeasuredHeight = { [weak self] _ in self?.view.setNeedsLayout() }
        configureContent()
        applyCurrentTheme()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let container = presentingViewController?.view, preview.contentSize.height > 0 else { return }
        let chrome = view.safeAreaLayoutGuide.layoutFrame.height - preview.bounds.height
        let desired = chrome + preview.contentSize.height + preview.contentInset.top + preview.contentInset.bottom
        let maximum = max(Layout.minimumHeight, floor(container.safeAreaLayoutGuide.layoutFrame.height * Layout.maximumHeightRatio))
        let height = min(max(Layout.minimumHeight, ceil(desired)), maximum)
        guard preferredContentSize.height != height else { return }
        preferredContentSize.height = height
        if #available(iOS 16.0, *) { sheetPresentationController?.invalidateDetents() }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            footerStack.axis = traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? .vertical : .horizontal
        }
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
        applyCurrentTheme()
    }

    private func applyCurrentTheme() {
        // 弹层使用一层实色阅读背景，避免系统材质与楼层背景叠加降低对比度。
        let readingTraits = UITraitCollection(traitsFrom: [traitCollection, UITraitCollection(userInterfaceLevel: .base)])
        view.backgroundColor = UIColor.systemBackground.resolvedColor(with: readingTraits)
        headerView.backgroundColor = .clear
        preview.backgroundColor = .clear
        preview.floor.contentView.backgroundColor = .clear
        headerSeparator.backgroundColor = .separator
    }

    private func configureContent() {
        headerView.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .secondaryLabel
        closeButton.accessibilityLabel = DetailListStrings.text("close")
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        headerSeparator.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(closeButton)
        headerView.addSubview(headerSeparator)

        var fullPostConfiguration = UIButton.Configuration.bordered()
        fullPostConfiguration.title = DetailListStrings.text("entry-open-full-post")
        fullPostConfiguration.baseForegroundColor = .label
        fullPostConfiguration.cornerStyle = .medium
        fullPostConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
        fullPostButton.configuration = fullPostConfiguration
        fullPostButton.addTarget(self, action: #selector(fullPostTapped), for: .touchUpInside)
        fullPostButton.titleLabel?.adjustsFontSizeToFitWidth = true
        fullPostButton.titleLabel?.minimumScaleFactor = 0.85

        var revealConfiguration = UIButton.Configuration.filled()
        revealConfiguration.title = DetailListStrings.text("preview-show-floor")
        revealConfiguration.baseBackgroundColor = .secondarySystemBackground
        revealConfiguration.baseForegroundColor = .label
        revealConfiguration.cornerStyle = .medium
        revealConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
        revealButton.configuration = revealConfiguration
        revealButton.addTarget(self, action: #selector(revealTapped), for: .touchUpInside)
        revealButton.titleLabel?.adjustsFontSizeToFitWidth = true
        revealButton.titleLabel?.minimumScaleFactor = 0.85

        footerStack.axis = traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? .vertical : .horizontal
        footerStack.alignment = .fill
        footerStack.distribution = .fillEqually
        footerStack.spacing = 10
        footerStack.translatesAutoresizingMaskIntoConstraints = false
        if showsFullPostButton {
            footerStack.addArrangedSubview(fullPostButton)
        }
        footerStack.addArrangedSubview(revealButton)

        preview.alwaysBounceVertical = false
        preview.contentInset = UIEdgeInsets(top: 12, left: 0, bottom: 14, right: 0)
        preview.verticalScrollIndicatorInsets = preview.contentInset
        preview.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(preview)
        view.addSubview(headerView)
        view.addSubview(footerStack)

        NSLayoutConstraint.activate([
            headerView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.heightAnchor.constraint(equalToConstant: Layout.headerHeight),

            headerSeparator.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            headerSeparator.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            headerSeparator.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),
            headerSeparator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),

            preview.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            preview.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            preview.bottomAnchor.constraint(equalTo: footerStack.topAnchor, constant: -12),

            footerStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            footerStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            footerStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            revealButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),

            closeButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -8),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44)
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
