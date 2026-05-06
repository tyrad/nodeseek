//
//  PostBodyCellNode.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import AsyncDisplayKit
import DTCoreText
import UIKit

final class PostBodyCellNode: ASCellNode {
    private enum Layout {
        static let contentInset = UIEdgeInsets(
            top: 18,
            left: PostDetailContentLayout.horizontalInset,
            bottom: 14,
            right: PostDetailContentLayout.horizontalInset
        )
        static let verticalSpacing: CGFloat = 12
        static let bodySpacing: CGFloat = 18
        static let reactionActionWidth: CGFloat = 52
    }

    private var content: PostDetailHeaderContent
    private let onImageTapped: ([URL], Int) -> Void
    private let onLinkTapped: (URL) -> Void
    private let onAuthorTapped: (URL) -> Void
    private let onLikeTapped: () -> Void
    private let onChickenLegTapped: () -> Void
    private let onOpposeTapped: () -> Void
    private let onFavoriteTapped: () -> Void
    private let onReplyTapped: () -> Void
    private let onCommentTapped: () -> Void
    private let onTextLayoutInvalidated: () -> Void
    private let showsReplyActions: Bool
    private let avatarLoader = AvatarImageLoader.shared
    private weak var avatarImageView: UIImageView?
    private var hasRequestedAvatar = false
    private var hasDisplayableAuthor: Bool {
        AuthorDisplayPolicy.isDisplayable(content.authorName)
    }
    private var hasAuthorProfileLink: Bool {
        content.authorProfileURL != nil && hasDisplayableAuthor
    }

    private let titleNode = ASTextNode()
    private let authorButtonNode = ASButtonNode()
    private let metadataNode = ASTextNode()
    private let likeButtonNode = ASButtonNode()
    private let chickenLegButtonNode = ASButtonNode()
    private let opposeButtonNode = ASButtonNode()
    private let favoriteButtonNode = ASButtonNode()
    private let replyButtonNode = ASButtonNode()
    private let commentButtonNode = ASButtonNode()
    private let bodyNodes: [ASDisplayNode]
    private var lastAppliedUserInterfaceStyle: UIUserInterfaceStyle?
    private var hasReactionActions: Bool {
        [
            content.likeCount,
            content.chickenLegCount,
            content.opposeCount,
            content.favoriteCount
        ].contains { $0 != nil }
    }
    private var hasFooterActions: Bool {
        hasReactionActions || showsReplyActions
    }

    private lazy var avatarNode: ASDisplayNode = {
        let node = ASDisplayNode(viewBlock: { [weak self] in
            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFill
            imageView.backgroundColor = .systemGray5
            imageView.layer.cornerRadius = PostDetailContentLayout.avatarCornerRadius
            imageView.layer.masksToBounds = true
            imageView.isUserInteractionEnabled = self?.hasAuthorProfileLink == true
            if self?.hasAuthorProfileLink == true {
                imageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(PostBodyCellNode.authorTapped)))
            }
            self?.avatarImageView = imageView
            return imageView
        })
        node.style.preferredSize = CGSize(
            width: PostDetailContentLayout.avatarSize,
            height: PostDetailContentLayout.avatarSize
        )
        return node
    }()

    init(
        content: PostDetailHeaderContent,
        renderedContent: [RenderedContentBlock]?,
        onImageTapped: @escaping ([URL], Int) -> Void,
        onLinkTapped: @escaping (URL) -> Void = { _ in },
        onAuthorTapped: @escaping (URL) -> Void = { _ in },
        onLikeTapped: @escaping () -> Void = {},
        onChickenLegTapped: @escaping () -> Void = {},
        onOpposeTapped: @escaping () -> Void = {},
        onFavoriteTapped: @escaping () -> Void = {},
        onReplyTapped: @escaping () -> Void = {},
        onCommentTapped: @escaping () -> Void = {},
        showsReplyActions: Bool = true,
        onTextLayoutInvalidated: @escaping () -> Void,
        imageSizeProvider: @escaping (URL) -> CGSize? = { _ in nil },
        onImageSizeResolved: @escaping (URL, CGSize) -> Void = { _, _ in },
        onImageHeightReduced: @escaping () -> Void = {}
    ) {
        self.content = content
        self.onImageTapped = onImageTapped
        self.onLinkTapped = onLinkTapped
        self.onAuthorTapped = onAuthorTapped
        self.onLikeTapped = onLikeTapped
        self.onChickenLegTapped = onChickenLegTapped
        self.onOpposeTapped = onOpposeTapped
        self.onFavoriteTapped = onFavoriteTapped
        self.onReplyTapped = onReplyTapped
        self.onCommentTapped = onCommentTapped
        self.showsReplyActions = showsReplyActions
        self.onTextLayoutInvalidated = onTextLayoutInvalidated
        self.bodyNodes = DetailContentBlockNodeFactory.makeNodes(
            from: renderedContent ?? [],
            onImageTapped: onImageTapped,
            onLinkTapped: onLinkTapped,
            onTextLayoutInvalidated: onTextLayoutInvalidated,
            imageSizeProvider: imageSizeProvider,
            onImageSizeResolved: onImageSizeResolved,
            onImageHeightReduced: onImageHeightReduced
        )
        super.init()
        automaticallyManagesSubnodes = true
        selectionStyle = .none
        backgroundColor = .systemBackground
        configureText()
        configureActions()
    }

    override func didLoad() {
        super.didLoad()
        lastAppliedUserInterfaceStyle = view.traitCollection.userInterfaceStyle
        view.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self] (view: UIView, previousTraitCollection: UITraitCollection) in
            guard let self else { return }
            guard previousTraitCollection.userInterfaceStyle != view.traitCollection.userInterfaceStyle else { return }
            self.refreshAppearanceForCurrentTraits()
        }
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

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        titleNode.style.flexShrink = 1
        authorButtonNode.style.flexShrink = 0
        metadataNode.style.flexShrink = 1

        let identityStack = ASStackLayoutSpec.horizontal()
        identityStack.spacing = 5
        identityStack.alignItems = .center
        var identityChildren: [ASLayoutElement] = []
        if hasDisplayableAuthor {
            identityChildren.append(authorButtonNode)
        }
        if Self.metadataText(for: content).isEmpty == false {
            identityChildren.append(metadataNode)
        }
        identityStack.children = identityChildren
        identityStack.style.flexShrink = 1
        identityStack.style.flexGrow = 1

        let authorStack = ASStackLayoutSpec.horizontal()
        authorStack.spacing = PostDetailContentLayout.avatarSpacing
        authorStack.alignItems = .center
        authorStack.children = hasDisplayableAuthor ? [avatarNode, identityStack] : [identityStack]

        let stack = ASStackLayoutSpec.vertical()
        stack.spacing = Layout.verticalSpacing
        stack.children = identityChildren.isEmpty ? [titleNode] : [titleNode, authorStack]

        if bodyNodes.isEmpty == false {
            let contentStack = ASStackLayoutSpec.vertical()
            contentStack.spacing = Layout.verticalSpacing
            contentStack.style.spacingBefore = Layout.bodySpacing - Layout.verticalSpacing
            contentStack.children = bodyNodes
            stack.children?.append(contentStack)
        }
        if hasFooterActions {
            stack.children?.append(makeFooterActionStack())
        }

        return ASInsetLayoutSpec(insets: Layout.contentInset, child: stack)
    }

    private func configureText() {
        titleNode.maximumNumberOfLines = 0
        titleNode.attributedText = Self.titleAttributedText(for: content)

        authorButtonNode.setAttributedTitle(
            NSAttributedString(
                string: AuthorDisplayPolicy.displayName(from: content.authorName) ?? "",
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .subheadline),
                    .foregroundColor: UIColor.secondaryLabel
                ]
            ),
            for: .normal
        )
        authorButtonNode.accessibilityLabel = "查看 \(AuthorDisplayPolicy.displayName(from: content.authorName) ?? "作者") 的主页"

        metadataNode.maximumNumberOfLines = 0
        metadataNode.attributedText = NSAttributedString(
            string: Self.metadataText(for: content),
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .subheadline),
                .foregroundColor: UIColor.secondaryLabel
            ]
        )

        configureLikeActionButton(count: content.likeCount, isClicked: content.isLikeClicked)
        configureChickenLegActionButton(count: content.chickenLegCount, isClicked: content.isChickenLegClicked)
        configureOpposeActionButton(count: content.opposeCount, isClicked: content.isOpposeClicked)
        configureFavoriteActionButton(count: content.favoriteCount, isCollected: content.isFavoriteCollected)
        configureActionButton(replyButtonNode, systemImageName: "arrowshape.turn.up.left", accessibilityLabel: "回复楼主")
        configureActionButton(commentButtonNode, systemImageName: "text.bubble", accessibilityLabel: "评论帖子")
    }

    private static func titleAttributedText(for content: PostDetailHeaderContent) -> NSAttributedString {
        let titleFont = UIFont.preferredFont(forTextStyle: .title2)
        let result = NSMutableAttributedString(
            string: content.title,
            attributes: [
                .font: titleFont,
                .foregroundColor: UIColor.label
            ]
        )

        guard let requiredReadingLevel = content.requiredReadingLevel else {
            return result
        }

        let badgeFont = UIFont.preferredFont(forTextStyle: .subheadline)
        let badgeColor = UIColor.systemRed
        result.append(NSAttributedString(
            string: " 🔒 \(requiredReadingLevel)",
            attributes: [
                .font: badgeFont,
                .foregroundColor: badgeColor
            ]
        ))

        return result
    }

    @discardableResult
    func refreshAppearanceForCurrentTraits() -> Bool {
        let currentStyle = isNodeLoaded ? view.traitCollection.userInterfaceStyle : UITraitCollection.current.userInterfaceStyle
        guard lastAppliedUserInterfaceStyle != currentStyle else { return false }
        lastAppliedUserInterfaceStyle = currentStyle
        configureText()
        setNeedsLayout()
        setNeedsDisplay()
        return true
    }

    var debugTitleAttributedText: NSAttributedString? {
        titleNode.attributedText
    }

    private func configureActions() {
        authorButtonNode.isUserInteractionEnabled = hasAuthorProfileLink
        if hasAuthorProfileLink {
            authorButtonNode.addTarget(self, action: #selector(authorTapped), forControlEvents: .touchUpInside)
        }
        likeButtonNode.addTarget(self, action: #selector(likeTapped), forControlEvents: .touchUpInside)
        chickenLegButtonNode.addTarget(self, action: #selector(chickenLegTapped), forControlEvents: .touchUpInside)
        opposeButtonNode.addTarget(self, action: #selector(opposeTapped), forControlEvents: .touchUpInside)
        favoriteButtonNode.addTarget(self, action: #selector(favoriteTapped), forControlEvents: .touchUpInside)
        replyButtonNode.addTarget(self, action: #selector(replyTapped), forControlEvents: .touchUpInside)
        commentButtonNode.addTarget(self, action: #selector(commentTapped), forControlEvents: .touchUpInside)
    }

    private func makeFooterActionStack() -> ASLayoutSpec {
        let spacer = ASLayoutSpec()
        spacer.style.flexGrow = 1

        let actionStack = ASStackLayoutSpec.horizontal()
        actionStack.spacing = 4
        actionStack.alignItems = .center
        var actionChildren: [ASLayoutElement] = [spacer]
        if hasReactionActions {
            actionChildren.append(contentsOf: [
                likeButtonNode,
                chickenLegButtonNode,
                opposeButtonNode,
                favoriteButtonNode
            ])
        }
        if showsReplyActions {
            actionChildren.append(contentsOf: [
                replyButtonNode,
                commentButtonNode
            ])
        }
        actionStack.children = actionChildren
        return actionStack
    }

    private func configureActionButton(
        _ button: ASButtonNode,
        systemImageName: String,
        accessibilityLabel: String,
        count: Int? = nil,
        color: UIColor = UIColor.secondaryLabel.withAlphaComponent(0.72)
    ) {
        let configuration = UIImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let image = UIImage(systemName: systemImageName, withConfiguration: configuration)?
            .withTintColor(color, renderingMode: .alwaysOriginal)
        button.setImage(image, for: .normal)
        let displayCount = count.flatMap { $0 > 0 ? $0 : nil }
        button.contentSpacing = displayCount == nil ? 0 : 4
        button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        if let displayCount {
            let countText = Self.reactionCountText(displayCount)
            let font = UIFont.preferredFont(forTextStyle: .caption1)
            button.setAttributedTitle(
                NSAttributedString(
                    string: countText,
                    attributes: [
                        .font: font,
                        .foregroundColor: color
                    ]
                ),
                for: .normal
            )
            button.style.preferredSize = CGSize(width: Self.actionButtonWidth(for: countText, font: font), height: 32)
            button.accessibilityLabel = "\(accessibilityLabel) \(displayCount)"
        } else {
            button.setAttributedTitle(nil, for: .normal)
            button.style.preferredSize = CGSize(width: 40, height: 32)
            button.accessibilityLabel = accessibilityLabel
        }
    }

    private static func reactionCountText(_ count: Int) -> String {
        let safeCount = max(0, count)
        if safeCount < 10_000 {
            return "\(safeCount)"
        }
        if safeCount < 100_000_000 {
            return compactCountText(safeCount, divisor: 10_000, unit: "万")
        }
        return compactCountText(safeCount, divisor: 100_000_000, unit: "亿")
    }

    private static func compactCountText(_ count: Int, divisor: Int, unit: String) -> String {
        let integerPart = count / divisor
        let decimalPart = (count % divisor) * 10 / divisor
        if integerPart >= 100 || decimalPart == 0 {
            return "\(integerPart)\(unit)"
        }
        return "\(integerPart).\(decimalPart)\(unit)"
    }

    private static func actionButtonWidth(for countText: String, font: UIFont) -> CGFloat {
        let textWidth = (countText as NSString).size(withAttributes: [.font: font]).width
        return max(Layout.reactionActionWidth, ceil(15 + 4 + textWidth + 16))
    }

    private static func favoriteActionColor(isCollected: Bool) -> UIColor {
        return isCollected ? .systemYellow : UIColor.secondaryLabel.withAlphaComponent(0.72)
    }

    private static func likeActionColor(isClicked: Bool) -> UIColor {
        isClicked ? .systemRed : UIColor.secondaryLabel.withAlphaComponent(0.72)
    }

    private static func chickenLegActionColor(isClicked: Bool) -> UIColor {
        isClicked ? .systemOrange : UIColor.secondaryLabel.withAlphaComponent(0.72)
    }

    private static func opposeActionColor(isClicked: Bool) -> UIColor {
        isClicked ? .systemRed : UIColor.secondaryLabel.withAlphaComponent(0.72)
    }

    private func configureLikeActionButton(count: Int?, isClicked: Bool) {
        configureActionButton(
            likeButtonNode,
            systemImageName: isClicked ? "hand.thumbsup.fill" : "hand.thumbsup",
            accessibilityLabel: "点赞",
            count: count,
            color: Self.likeActionColor(isClicked: isClicked)
        )
        likeButtonNode.style.preferredSize = CGSize(width: Layout.reactionActionWidth, height: 32)
    }

    private func configureOpposeActionButton(count: Int?, isClicked: Bool) {
        configureActionButton(
            opposeButtonNode,
            systemImageName: isClicked ? "hand.thumbsdown.fill" : "hand.thumbsdown",
            accessibilityLabel: "反对",
            count: count,
            color: Self.opposeActionColor(isClicked: isClicked)
        )
        opposeButtonNode.style.preferredSize = CGSize(width: Layout.reactionActionWidth, height: 32)
    }

    private func configureChickenLegActionButton(count: Int?, isClicked: Bool) {
        configureActionButton(
            chickenLegButtonNode,
            systemImageName: "fork.knife",
            accessibilityLabel: "加鸡腿",
            count: count,
            color: Self.chickenLegActionColor(isClicked: isClicked)
        )
        chickenLegButtonNode.style.preferredSize = CGSize(width: Layout.reactionActionWidth, height: 32)
    }

    private func configureFavoriteActionButton(count: Int?, isCollected: Bool) {
        configureActionButton(
            favoriteButtonNode,
            systemImageName: isCollected ? "star.fill" : "star",
            accessibilityLabel: "收藏",
            count: count,
            color: Self.favoriteActionColor(isCollected: isCollected)
        )
        favoriteButtonNode.style.preferredSize = CGSize(width: Layout.reactionActionWidth, height: 32)
    }

    private func updateFavoriteActionPresentation(count: Int?, isCollected: Bool) {
        let color = Self.favoriteActionColor(isCollected: isCollected)
        let configuration = UIImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let image = UIImage(systemName: isCollected ? "star.fill" : "star", withConfiguration: configuration)?
            .withTintColor(color, renderingMode: .alwaysOriginal)
        favoriteButtonNode.setImage(image, for: .normal)

        let displayCount = count.flatMap { $0 > 0 ? $0 : nil }
        if let displayCount {
            let countText = Self.reactionCountText(displayCount)
            let font = UIFont.preferredFont(forTextStyle: .caption1)
            favoriteButtonNode.setAttributedTitle(
                NSAttributedString(
                    string: countText,
                    attributes: [
                        .font: font,
                        .foregroundColor: color
                    ]
                ),
                for: .normal
            )
            favoriteButtonNode.accessibilityLabel = "收藏 \(displayCount)"
            favoriteButtonNode.contentSpacing = 4
        } else {
            favoriteButtonNode.setAttributedTitle(nil, for: .normal)
            favoriteButtonNode.accessibilityLabel = "收藏"
            favoriteButtonNode.contentSpacing = 0
        }
    }

    private func updateLikeActionPresentation(count: Int?, isClicked: Bool) {
        let color = Self.likeActionColor(isClicked: isClicked)
        let configuration = UIImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let image = UIImage(systemName: isClicked ? "hand.thumbsup.fill" : "hand.thumbsup", withConfiguration: configuration)?
            .withTintColor(color, renderingMode: .alwaysOriginal)
        likeButtonNode.setImage(image, for: .normal)

        let displayCount = count.flatMap { $0 > 0 ? $0 : nil }
        if let displayCount {
            let countText = Self.reactionCountText(displayCount)
            let font = UIFont.preferredFont(forTextStyle: .caption1)
            likeButtonNode.setAttributedTitle(
                NSAttributedString(
                    string: countText,
                    attributes: [
                        .font: font,
                        .foregroundColor: color
                    ]
                ),
                for: .normal
            )
            likeButtonNode.accessibilityLabel = "点赞 \(displayCount)"
            likeButtonNode.contentSpacing = 4
        } else {
            likeButtonNode.setAttributedTitle(nil, for: .normal)
            likeButtonNode.accessibilityLabel = "点赞"
            likeButtonNode.contentSpacing = 0
        }
    }

    private func updateChickenLegActionPresentation(count: Int?, isClicked: Bool) {
        let color = Self.chickenLegActionColor(isClicked: isClicked)
        let configuration = UIImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let image = UIImage(systemName: "fork.knife", withConfiguration: configuration)?
            .withTintColor(color, renderingMode: .alwaysOriginal)
        chickenLegButtonNode.setImage(image, for: .normal)

        let displayCount = count.flatMap { $0 > 0 ? $0 : nil }
        if let displayCount {
            let countText = Self.reactionCountText(displayCount)
            let font = UIFont.preferredFont(forTextStyle: .caption1)
            chickenLegButtonNode.setAttributedTitle(
                NSAttributedString(
                    string: countText,
                    attributes: [
                        .font: font,
                        .foregroundColor: color
                    ]
                ),
                for: .normal
            )
            chickenLegButtonNode.accessibilityLabel = "加鸡腿 \(displayCount)"
            chickenLegButtonNode.contentSpacing = 4
        } else {
            chickenLegButtonNode.setAttributedTitle(nil, for: .normal)
            chickenLegButtonNode.accessibilityLabel = "加鸡腿"
            chickenLegButtonNode.contentSpacing = 0
        }
    }

    private func updateOpposeActionPresentation(count: Int?, isClicked: Bool) {
        let color = Self.opposeActionColor(isClicked: isClicked)
        let configuration = UIImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let image = UIImage(systemName: isClicked ? "hand.thumbsdown.fill" : "hand.thumbsdown", withConfiguration: configuration)?
            .withTintColor(color, renderingMode: .alwaysOriginal)
        opposeButtonNode.setImage(image, for: .normal)

        let displayCount = count.flatMap { $0 > 0 ? $0 : nil }
        if let displayCount {
            let countText = Self.reactionCountText(displayCount)
            let font = UIFont.preferredFont(forTextStyle: .caption1)
            opposeButtonNode.setAttributedTitle(
                NSAttributedString(
                    string: countText,
                    attributes: [
                        .font: font,
                        .foregroundColor: color
                    ]
                ),
                for: .normal
            )
            opposeButtonNode.accessibilityLabel = "反对 \(displayCount)"
            opposeButtonNode.contentSpacing = 4
        } else {
            opposeButtonNode.setAttributedTitle(nil, for: .normal)
            opposeButtonNode.accessibilityLabel = "反对"
            opposeButtonNode.contentSpacing = 0
        }
    }

    func updateLikeReaction(count: Int?, isClicked: Bool) {
        let nextContent = content.updatingLikeReaction(count: count, isClicked: isClicked)
        guard nextContent != content else { return }
        content = nextContent
        updateLikeActionPresentation(count: content.likeCount, isClicked: content.isLikeClicked)
    }

    func updateChickenLegReaction(count: Int?, isClicked: Bool) {
        let nextContent = content.updatingChickenLegReaction(count: count, isClicked: isClicked)
        guard nextContent != content else { return }
        content = nextContent
        updateChickenLegActionPresentation(count: content.chickenLegCount, isClicked: content.isChickenLegClicked)
    }

    func updateOpposeReaction(count: Int?, isClicked: Bool) {
        let nextContent = content.updatingOpposeReaction(count: count, isClicked: isClicked)
        guard nextContent != content else { return }
        content = nextContent
        updateOpposeActionPresentation(count: content.opposeCount, isClicked: content.isOpposeClicked)
    }

    func updateFavoriteReaction(count: Int?, isCollected: Bool) {
        let nextContent = content.updatingFavoriteReaction(count: count, isCollected: isCollected)
        guard nextContent != content else { return }
        content = nextContent
        updateFavoriteActionPresentation(count: content.favoriteCount, isCollected: content.isFavoriteCollected)
    }

    @objc private func authorTapped() {
        guard let authorProfileURL = content.authorProfileURL else { return }
        onAuthorTapped(authorProfileURL)
    }

    @objc private func likeTapped() {
        onLikeTapped()
    }

    @objc private func chickenLegTapped() {
        onChickenLegTapped()
    }

    @objc private func opposeTapped() {
        onOpposeTapped()
    }

    @objc private func favoriteTapped() {
        onFavoriteTapped()
    }

    @objc private func replyTapped() {
        onReplyTapped()
    }

    @objc private func commentTapped() {
        onCommentTapped()
    }

    private func requestAvatarIfNeeded() {
        guard hasDisplayableAuthor else { return }
        guard !hasRequestedAvatar else { return }
        guard let avatarImageView else { return }
        hasRequestedAvatar = true
        avatarLoader.loadAvatar(into: avatarImageView, postID: content.postID, avatarURL: content.avatarURL)
    }

    private func cancelAvatarLoad() {
        guard let avatarImageView else { return }
        avatarLoader.cancel(on: avatarImageView)
    }

    private static func metadataText(for content: PostDetailHeaderContent) -> String {
        let metadata = content.metadataText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard metadata.isEmpty == false else { return "" }
        return AuthorDisplayPolicy.isDisplayable(content.authorName) ? "· \(metadata)" : metadata
    }

    var debugFooterActionAccessibilityLabels: [String] {
        let reactionLabels = hasReactionActions
            ? [
                likeButtonNode,
                chickenLegButtonNode,
                opposeButtonNode,
                favoriteButtonNode
            ].map { $0.accessibilityLabel ?? "" }
            : []
        let replyLabels = showsReplyActions
            ? [
                replyButtonNode,
                commentButtonNode
            ].map { $0.accessibilityLabel ?? "" }
            : []
        return reactionLabels + replyLabels
    }

    var debugReactionActionTitles: [String?] {
        [
            likeButtonNode,
            chickenLegButtonNode,
            opposeButtonNode,
            favoriteButtonNode
        ].map { $0.attributedTitle(for: .normal)?.string }
    }

    var debugFavoriteActionColor: UIColor {
        Self.favoriteActionColor(isCollected: content.isFavoriteCollected)
    }

    var debugLikeActionColor: UIColor {
        Self.likeActionColor(isClicked: content.isLikeClicked)
    }

    var debugChickenLegActionColor: UIColor {
        Self.chickenLegActionColor(isClicked: content.isChickenLegClicked)
    }

    var debugOpposeActionColor: UIColor {
        Self.opposeActionColor(isClicked: content.isOpposeClicked)
    }

    var debugFavoriteActionIsSubmitting: Bool {
        content.isFavoriteSubmitting
    }

    func debugTapFavoriteAction() {
        favoriteTapped()
    }

    func debugTapLikeAction() {
        likeTapped()
    }

    func debugTapChickenLegAction() {
        chickenLegTapped()
    }

    func debugTapOpposeAction() {
        opposeTapped()
    }

    func debugTapReplyAction() {
        replyTapped()
    }

    func debugTapCommentAction() {
        commentTapped()
    }
}

extension ASCellNode {
    func flashAnchorHighlight() {
        guard isNodeLoaded else { return }
        let originalColor = view.backgroundColor ?? UIColor.systemBackground
        view.backgroundColor = UIColor(red: 15 / 255, green: 128 / 255, blue: 85 / 255, alpha: 0.12)
        UIView.animate(
            withDuration: 0.35,
            delay: 0.8,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            self.view.backgroundColor = originalColor
        }
    }
}

final class DetailRichTextNode: ASDisplayNode {
    nonisolated private static let defaultMeasureWidth: CGFloat = 320

    private let attributedText: NSMutableAttributedString
    private let attributedTextLock = NSLock()
    private let onImageTapped: ([URL], Int) -> Void
    private let onLinkTapped: (URL) -> Void
    private let onLayoutInvalidated: () -> Void
    private let imageSizeProvider: (URL) -> CGSize?
    private let onImageSizeResolved: (URL, CGSize) -> Void
    private let forcedMinimumHeight: CGFloat
    private let diagnosticID = String(UUID().uuidString.prefix(8))

    init(
        attributedText: NSAttributedString,
        forcedMinimumHeight: CGFloat = 0,
        imageSizeProvider: @escaping (URL) -> CGSize? = { _ in nil },
        onImageSizeResolved: @escaping (URL, CGSize) -> Void = { _, _ in },
        onImageTapped: @escaping ([URL], Int) -> Void,
        onLinkTapped: @escaping (URL) -> Void = { _ in },
        onLayoutInvalidated: @escaping () -> Void
    ) {
        self.attributedText = NSMutableAttributedString(attributedString: attributedText)
        self.forcedMinimumHeight = forcedMinimumHeight
        self.imageSizeProvider = imageSizeProvider
        self.onImageSizeResolved = onImageSizeResolved
        self.onImageTapped = onImageTapped
        self.onLinkTapped = onLinkTapped
        self.onLayoutInvalidated = onLayoutInvalidated
        super.init()
        setViewBlock {
            DetailRichTextView()
        }
        style.flexShrink = 1
        style.flexGrow = 1
        logDiagnostics("init length=\(attributedText.length) attachments=\(Self.attachmentDiagnostics(in: attributedText))")
    }

    override func didLoad() {
        super.didLoad()
        guard let richTextView = view as? DetailRichTextView else { return }
        richTextView.configure(
            attributedText,
            onImageTapped: onImageTapped,
            onLinkTapped: onLinkTapped,
            onLayoutInvalidated: onLayoutInvalidated,
            onAttachmentLayoutUpdated: { [weak self] url, originalSize, displaySize in
                guard let self else { return }
                let didUpdate = self.updateAttachmentLayout(
                    matching: url,
                    originalSize: originalSize,
                    displaySize: displaySize
                )
                if didUpdate {
                    self.onImageSizeResolved(url, originalSize)
                }
            }
        )
    }

    @discardableResult
    func updateAttachmentLayout(
        matching url: URL,
        originalSize: CGSize,
        displaySize: CGSize
        ) -> Bool {
        guard originalSize.width > 0,
              originalSize.height > 0,
              displaySize.width > 0,
              displaySize.height > 0 else {
            return false
        }

        var didUpdate = false
        attributedTextLock.lock()
        attributedText.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributedText.length)
        ) { value, _, _ in
            guard let attachment = value as? DTTextAttachment,
                  attachment.contentURL == url else {
                return
            }

            attachment.originalSize = originalSize
            attachment.displaySize = displaySize
            didUpdate = true
        }
        attributedTextLock.unlock()

        if didUpdate {
            logDiagnostics(
                "node attachment updated url=\(url.absoluteString) original=\(Self.string(from: originalSize)) display=\(Self.string(from: displaySize))"
            )
            invalidateCalculatedLayout()
            setNeedsLayout()
        } else {
            logDiagnostics(
                "node attachment update missed url=\(url.absoluteString) original=\(Self.string(from: originalSize)) display=\(Self.string(from: displaySize)) attachments=\(Self.attachmentDiagnostics(in: attributedText))"
            )
        }
        return didUpdate
    }

    override func calculateSizeThatFits(_ constrainedSize: CGSize) -> CGSize {
        let width = Self.resolvedMeasureWidth(constrainedSize.width)
        attributedTextLock.lock()
        Self.applyCachedAttachmentSizes(
            to: attributedText,
            maxWidth: width,
            imageSizeProvider: imageSizeProvider
        )
        let measuredText = NSAttributedString(attributedString: attributedText)
        attributedTextLock.unlock()

        guard width > 0, measuredText.length > 0 else {
            return .zero
        }

        let boundingRect = measuredText.boundingRect(
            with: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let boundingHeight = ceil(max(boundingRect.height, 1))
        let dtCoreTextHeight = Self.dtCoreTextHeight(for: measuredText, width: width)
        let usesBoundingHeightFallback = Self.requiresBoundingHeightFallback(in: measuredText)
        let height = Self.resolvedMeasuredHeight(
            dtCoreTextHeight: dtCoreTextHeight,
            boundingHeight: boundingHeight,
            usesBoundingHeightFallback: usesBoundingHeightFallback
        )
        logDiagnostics(
            "measure width=\(Self.numberString(width)) bounding=\(Self.numberString(boundingHeight)) dt=\(dtCoreTextHeight.map(Self.numberString) ?? "nil") result=\(Self.numberString(height)) attachments=\(Self.attachmentDiagnostics(in: measuredText))"
        )
        return CGSize(width: width, height: ceil(max(height, forcedMinimumHeight)))
    }

    nonisolated static func resolvedMeasureWidth(_ width: CGFloat) -> CGFloat {
        guard width.isFinite, width > 0 else {
            return defaultMeasureWidth
        }
        return width
    }

    nonisolated static func resolvedMeasuredHeight(
        dtCoreTextHeight: CGFloat?,
        boundingHeight: CGFloat,
        usesBoundingHeightFallback: Bool
    ) -> CGFloat {
        if usesBoundingHeightFallback,
           let dtCoreTextHeight,
           dtCoreTextHeight.isFinite,
           dtCoreTextHeight > 0 {
            return ceil(max(dtCoreTextHeight, boundingHeight))
        }

        if let dtCoreTextHeight,
           dtCoreTextHeight.isFinite,
           dtCoreTextHeight > 0 {
            return ceil(dtCoreTextHeight)
        }

        return ceil(max(boundingHeight, 1))
    }

    private static func requiresBoundingHeightFallback(in attributedText: NSAttributedString) -> Bool {
        guard attributedText.length > 0 else { return false }
        var requiresFallback = false
        attributedText.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributedText.length)
        ) { value, _, stop in
            guard let attachment = value as? DTTextAttachment else { return }
            if Self.isStickerAttachment(attachment) == false {
                requiresFallback = true
                stop.pointee = true
            }
        }
        return requiresFallback
    }

    private static func isStickerAttachment(_ attachment: DTTextAttachment) -> Bool {
        if DetailAttachmentAttributes.hasClass("sticker", in: attachment.attributes) {
            return true
        }
        if let contentURL = attachment.contentURL {
            return DetailImageKind.resolved(
                isSticker: contentURL.absoluteString.lowercased().contains("sticker"),
                imageURL: contentURL
            ) == .sticker
        }
        return false
    }

    private static func applyCachedAttachmentSizes(
        to attributedText: NSMutableAttributedString,
        maxWidth: CGFloat,
        imageSizeProvider: (URL) -> CGSize?
    ) {
        guard maxWidth > 0, attributedText.length > 0 else { return }
        attributedText.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributedText.length)
        ) { value, range, _ in
            guard let attachment = value as? DTTextAttachment,
                  let contentURL = attachment.contentURL,
                  let originalSize = imageSizeProvider(contentURL),
                  originalSize.width > 0,
                  originalSize.height > 0 else {
                return
            }
            let isFixedQuoteImage = (attributedText.attribute(
                DetailAttachmentAttributes.fixedQuoteImage,
                at: range.location,
                effectiveRange: nil
            ) as? Bool) == true
            if isFixedQuoteImage {
                attachment.originalSize = originalSize
                return
            }

            let isSticker = Self.isStickerAttachment(attachment)
            let imageKind = DetailImageKind.resolved(isSticker: isSticker, imageURL: contentURL)
            let displaySize = DetailImageLayout.presentation(
                for: originalSize,
                maxWidth: imageKind == .sticker ? min(maxWidth, DetailImageLayout.fixedStickerWidth) : maxWidth,
                kind: imageKind
            ).size
            guard displaySize.width > 0, displaySize.height > 0 else { return }
            attachment.originalSize = originalSize
            attachment.displaySize = displaySize
        }
    }

    nonisolated private static func dtCoreTextHeight(for attributedText: NSAttributedString, width: CGFloat) -> CGFloat? {
        guard width > 0, attributedText.length > 0 else { return nil }
        let unknownHeight: CGFloat = 16_777_215
        let layouter = DTCoreTextLayouter(attributedString: attributedText)
        let layoutFrame = layouter?.layoutFrame(
            with: CGRect(x: 0, y: 0, width: width, height: unknownHeight),
            range: NSRange(location: 0, length: 0)
        )
        guard let height = layoutFrame?.frame.maxY,
              height.isFinite,
              height > 0 else {
            return nil
        }
        return ceil(height)
    }

    private func logDiagnostics(_ message: String) {
        guard NodeSeekDebugConfig.enableDetailRenderDiagnostics else { return }
        AppLog.info(.rendering, "[\(diagnosticID)] \(message)")
    }

    nonisolated private static func attachmentDiagnostics(in attributedText: NSAttributedString) -> String {
        guard attributedText.length > 0 else { return "[]" }
        var parts: [String] = []
        attributedText.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributedText.length)
        ) { value, _, _ in
            guard let attachment = value as? DTTextAttachment else { return }
            let url = attachment.contentURL?.absoluteString ?? "nil"
            parts.append(
                "url=\(url),original=\(string(from: attachment.originalSize)),display=\(string(from: attachment.displaySize))"
            )
        }
        if parts.count > 6 {
            return "[\(parts.prefix(6).joined(separator: " | ")) | ... total=\(parts.count)]"
        }
        return "[\(parts.joined(separator: " | "))]"
    }

    nonisolated private static func string(from size: CGSize) -> String {
        "\(numberString(size.width))x\(numberString(size.height))"
    }

    nonisolated private static func numberString(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }
}
