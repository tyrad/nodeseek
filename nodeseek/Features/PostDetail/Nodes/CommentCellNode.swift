//
//  CommentCellNode.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import AsyncDisplayKit
import UIKit

enum PostDetailContentLayout {
    static let horizontalInset: CGFloat = 16
    static let commentTopInset: CGFloat = 14
    static let commentBottomInset: CGFloat = 14
    static let avatarSize: CGFloat = 42
    static let avatarCornerRadius: CGFloat = 9
    static let avatarSpacing: CGFloat = 12
}

final class CommentCellNode: ASCellNode {
    private enum Layout {
        static let headerSpacing: CGFloat = 5
        static let bodySpacing: CGFloat = 10

        static func textColumnWidth(for maxWidth: CGFloat, includingAvatar: Bool) -> CGFloat? {
            guard maxWidth.isFinite, maxWidth > 0 else { return nil }
            let avatarWidth = includingAvatar
                ? PostDetailContentLayout.avatarSize + PostDetailContentLayout.avatarSpacing
                : 0
            let chromeWidth = PostDetailContentLayout.horizontalInset * 2 + avatarWidth
            return max(maxWidth - chromeWidth, 1)
        }
    }

    private var comment: Comment
    private let onImageTapped: ([URL], Int) -> Void
    private let onLinkTapped: (URL) -> Void
    private let onAuthorTapped: (URL) -> Void
    private let onLikeTapped: (Comment) -> Void
    private let onChickenLegTapped: (Comment) -> Void
    private let onOpposeTapped: (Comment) -> Void
    private let onReplyTapped: (Comment) -> Void
    private let onQuoteTapped: (Comment) -> Void
    private let onTextLayoutInvalidated: () -> Void
    private let avatarLoader = AvatarImageLoader.shared
    private weak var avatarImageView: UIImageView?
    private var hasRequestedAvatar = false
    private var hasDisplayableAuthor: Bool {
        AuthorDisplayPolicy.isDisplayable(comment.authorName)
    }
    private var hasAuthorProfileLink: Bool {
        comment.authorProfileURL != nil && hasDisplayableAuthor
    }

    private let authorButtonNode = ASButtonNode()
    private let posterBadgeNode = ASTextNode()
    private let authorBadgeNodes: [ASButtonNode]
    private let timeNode = ASTextNode()
    private let hotBadgeNode = ASImageNode()
    private let floorNode = ASTextNode()
    private let likeButtonNode = ASButtonNode()
    private let chickenLegButtonNode = ASButtonNode()
    private let opposeButtonNode = ASButtonNode()
    private let replyButtonNode = ASButtonNode()
    private let quoteButtonNode = ASButtonNode()
    private let separatorNode = ASDisplayNode()
    private let bodyNodes: [ASDisplayNode]
    private(set) var debugActionsAreDisplayedBelowBody = false
    private(set) var debugHeaderTimeIsOnSecondLine = false
    private var lastAppliedUserInterfaceStyle: UIUserInterfaceStyle?

    private lazy var avatarNode: ASDisplayNode = {
        let node = ASDisplayNode(viewBlock: { [weak self] in
            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFill
            imageView.backgroundColor = .systemGray5
            imageView.layer.cornerRadius = PostDetailContentLayout.avatarCornerRadius
            imageView.layer.masksToBounds = true
            imageView.isUserInteractionEnabled = self?.hasAuthorProfileLink == true
            if self?.hasAuthorProfileLink == true {
                imageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(CommentCellNode.authorTapped)))
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
        comment: Comment,
        renderedBody: [RenderedContentBlock]?,
        onImageTapped: @escaping ([URL], Int) -> Void,
        onLinkTapped: @escaping (URL) -> Void = { _ in },
        onAuthorTapped: @escaping (URL) -> Void = { _ in },
        onLikeTapped: @escaping (Comment) -> Void = { _ in },
        onChickenLegTapped: @escaping (Comment) -> Void = { _ in },
        onOpposeTapped: @escaping (Comment) -> Void = { _ in },
        onReplyTapped: @escaping (Comment) -> Void = { _ in },
        onQuoteTapped: @escaping (Comment) -> Void = { _ in },
        onTextLayoutInvalidated: @escaping () -> Void,
        imageSizeProvider: @escaping (URL) -> CGSize? = { _ in nil },
        onImageSizeResolved: @escaping (URL, CGSize) -> Void = { _, _ in },
        onImageHeightReduced: @escaping () -> Void = {}
    ) {
        self.comment = comment
        self.onImageTapped = onImageTapped
        self.onLinkTapped = onLinkTapped
        self.onAuthorTapped = onAuthorTapped
        self.onLikeTapped = onLikeTapped
        self.onChickenLegTapped = onChickenLegTapped
        self.onOpposeTapped = onOpposeTapped
        self.onReplyTapped = onReplyTapped
        self.onQuoteTapped = onQuoteTapped
        self.onTextLayoutInvalidated = onTextLayoutInvalidated
        self.authorBadgeNodes = comment.authorBadgeTexts.map { Self.makeAuthorBadgeNode(text: $0) }
        self.bodyNodes = DetailContentBlockNodeFactory.makeNodes(
            from: renderedBody ?? [],
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
        separatorNode.backgroundColor = .separator
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
        authorButtonNode.style.flexShrink = 1
        posterBadgeNode.style.flexShrink = 0
        authorBadgeNodes.forEach { $0.style.flexShrink = 0 }
        timeNode.style.flexShrink = 1
        hotBadgeNode.style.preferredSize = CGSize(width: 13, height: 13)
        hotBadgeNode.style.flexShrink = 0
        floorNode.style.flexShrink = 0
        likeButtonNode.style.flexShrink = 0
        chickenLegButtonNode.style.flexShrink = 0
        opposeButtonNode.style.flexShrink = 0
        replyButtonNode.style.flexShrink = 0
        quoteButtonNode.style.flexShrink = 0
        separatorNode.style.height = ASDimension(unit: .points, value: 1 / UIScreen.main.scale)

        let identityStack = ASStackLayoutSpec.horizontal()
        identityStack.spacing = Layout.headerSpacing
        identityStack.alignItems = .center
        var identityChildren: [ASLayoutElement] = []
        if hasDisplayableAuthor {
            identityChildren.append(authorButtonNode)
        }
        if comment.isPoster {
            identityChildren.append(posterBadgeNode)
        }
        identityChildren.append(contentsOf: authorBadgeNodes)
        identityStack.children = identityChildren
        identityStack.style.flexGrow = 1
        identityStack.style.flexShrink = 1

        let headerStack = ASStackLayoutSpec.horizontal()
        headerStack.alignItems = .start
        headerStack.justifyContent = .spaceBetween
        var headerChildren: [ASLayoutElement] = []
        if identityChildren.isEmpty == false {
            headerChildren.append(identityStack)
        }
        if comment.floorText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            let floorStack = ASStackLayoutSpec.horizontal()
            floorStack.spacing = 4
            floorStack.alignItems = .center
            floorStack.children = comment.isHot ? [hotBadgeNode, floorNode] : [floorNode]
            floorStack.style.flexShrink = 0
            headerChildren.append(floorStack)
        }
        headerStack.children = headerChildren

        let hasTime = comment.createdAtText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let headerBlockStack = ASStackLayoutSpec.vertical()
        headerBlockStack.spacing = 3
        var headerBlockChildren: [ASLayoutElement] = []
        if headerChildren.isEmpty == false {
            headerBlockChildren.append(headerStack)
        }
        if hasTime {
            headerBlockChildren.append(timeNode)
        }
        headerBlockStack.children = headerBlockChildren
        debugHeaderTimeIsOnSecondLine = headerChildren.isEmpty == false && hasTime

        var textChildren: [ASLayoutElement] = headerBlockChildren.isEmpty ? [] : [headerBlockStack]
        for bodyNode in bodyNodes {
            textChildren.append(bodyNode)
        }
        textChildren.append(makeFooterActionStack())
        debugActionsAreDisplayedBelowBody = true

        let textStack = ASStackLayoutSpec.vertical()
        textStack.spacing = Layout.bodySpacing
        textStack.children = textChildren
        textStack.style.flexGrow = 1
        textStack.style.flexShrink = 1
        if let textColumnWidth = Layout.textColumnWidth(
            for: constrainedSize.max.width,
            includingAvatar: hasDisplayableAuthor
        ) {
            textStack.style.width = ASDimension(unit: .points, value: textColumnWidth)
        }

        let contentStack = ASStackLayoutSpec.horizontal()
        contentStack.spacing = PostDetailContentLayout.avatarSpacing
        contentStack.alignItems = .start
        contentStack.children = hasDisplayableAuthor ? [avatarNode, textStack] : [textStack]

        let rowContent = ASInsetLayoutSpec(
            insets: UIEdgeInsets(
                top: PostDetailContentLayout.commentTopInset,
                left: PostDetailContentLayout.horizontalInset,
                bottom: PostDetailContentLayout.commentBottomInset,
                right: PostDetailContentLayout.horizontalInset
            ),
            child: contentStack
        )

        let stack = ASStackLayoutSpec.vertical()
        stack.children = [rowContent, separatorNode]
        return stack
    }

    private func configureText() {
        authorButtonNode.setAttributedTitle(
            NSAttributedString(
                string: AuthorDisplayPolicy.displayName(from: comment.authorName) ?? "",
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .headline),
                    .foregroundColor: UIColor.label
                ]
            ),
            for: .normal
        )
        authorButtonNode.accessibilityLabel = "查看 \(AuthorDisplayPolicy.displayName(from: comment.authorName) ?? "作者") 的主页"

        posterBadgeNode.maximumNumberOfLines = 1
        posterBadgeNode.attributedText = NSAttributedString(
            string: "楼主",
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .caption2),
                .foregroundColor: UIColor.systemOrange
            ]
        )
        posterBadgeNode.accessibilityLabel = "楼主"

        hotBadgeNode.image = UIImage(
            systemName: "flame.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        )?.withTintColor(.systemOrange, renderingMode: .alwaysOriginal)
        hotBadgeNode.contentMode = .scaleAspectFit
        hotBadgeNode.accessibilityLabel = "热门评论"

        timeNode.maximumNumberOfLines = 1
        timeNode.truncationMode = .byTruncatingTail
        timeNode.attributedText = NSAttributedString(
            string: comment.createdAtText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .subheadline),
                .foregroundColor: UIColor.secondaryLabel
            ]
        )

        floorNode.maximumNumberOfLines = 1
        floorNode.attributedText = NSAttributedString(
            string: comment.floorText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .subheadline),
                .foregroundColor: UIColor.tertiaryLabel
            ]
        )

        configureLikeActionButton(count: comment.likeCount, isClicked: comment.isLikeClicked)
        configureChickenLegActionButton(count: comment.chickenLegCount, isClicked: comment.isChickenLegClicked)
        configureOpposeActionButton(count: comment.opposeCount, isClicked: comment.isOpposeClicked)
        configureActionButton(replyButtonNode, systemImageName: "arrowshape.turn.up.left", accessibilityLabel: "回复评论")
        configureActionButton(quoteButtonNode, systemImageName: "quote.bubble", accessibilityLabel: "引用评论")
    }

    private func configureActions() {
        authorButtonNode.isUserInteractionEnabled = hasAuthorProfileLink
        if hasAuthorProfileLink {
            authorButtonNode.addTarget(self, action: #selector(authorTapped), forControlEvents: .touchUpInside)
        }
        likeButtonNode.addTarget(self, action: #selector(likeTapped), forControlEvents: .touchUpInside)
        chickenLegButtonNode.addTarget(self, action: #selector(chickenLegTapped), forControlEvents: .touchUpInside)
        opposeButtonNode.addTarget(self, action: #selector(opposeTapped), forControlEvents: .touchUpInside)
        replyButtonNode.addTarget(self, action: #selector(replyTapped), forControlEvents: .touchUpInside)
        quoteButtonNode.addTarget(self, action: #selector(quoteTapped), forControlEvents: .touchUpInside)
    }

    private static func makeAuthorBadgeNode(text: String) -> ASButtonNode {
        let node = ASButtonNode()
        let font = UIFont.preferredFont(forTextStyle: .caption2)
        node.setAttributedTitle(
            NSAttributedString(
                string: text,
                attributes: [
                    .font: font,
                    .foregroundColor: UIColor.label
                ]
            ),
            for: .normal
        )
        node.contentEdgeInsets = UIEdgeInsets(top: 2, left: 5, bottom: 2, right: 5)
        node.cornerRadius = 4
        node.borderWidth = 1
        node.borderColor = UIColor.separator.cgColor
        node.isUserInteractionEnabled = false
        node.accessibilityLabel = text
        return node
    }

    private func makeFooterActionStack() -> ASLayoutSpec {
        let spacer = ASLayoutSpec()
        spacer.style.flexGrow = 1

        let actionStack = ASStackLayoutSpec.horizontal()
        actionStack.spacing = 8
        actionStack.alignItems = .center
        actionStack.children = [
            spacer,
            likeButtonNode,
            chickenLegButtonNode,
            opposeButtonNode,
            replyButtonNode,
            quoteButtonNode
        ]
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
            button.accessibilityLabel = "\(accessibilityLabel) \(countText)"
        } else {
            button.setAttributedTitle(nil, for: .normal)
            button.style.preferredSize = CGSize(width: 40, height: 32)
            button.accessibilityLabel = accessibilityLabel
        }
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
    }

    private func configureOpposeActionButton(count: Int?, isClicked: Bool) {
        configureActionButton(
            opposeButtonNode,
            systemImageName: isClicked ? "hand.thumbsdown.fill" : "hand.thumbsdown",
            accessibilityLabel: "反对",
            count: count,
            color: Self.opposeActionColor(isClicked: isClicked)
        )
    }

    private func configureChickenLegActionButton(count: Int?, isClicked: Bool) {
        configureActionButton(
            chickenLegButtonNode,
            systemImageName: "fork.knife",
            accessibilityLabel: "加鸡腿",
            count: count,
            color: Self.chickenLegActionColor(isClicked: isClicked)
        )
    }

    func updateLikeReaction(count: Int?, isClicked: Bool) {
        let nextComment = comment.updatingLikeReaction(count: count, isClicked: isClicked)
        guard nextComment != comment else { return }
        comment = nextComment
        configureLikeActionButton(count: comment.likeCount, isClicked: comment.isLikeClicked)
        setNeedsLayout()
    }

    func updateChickenLegReaction(count: Int?, isClicked: Bool) {
        let nextComment = comment.updatingChickenLegReaction(count: count, isClicked: isClicked)
        guard nextComment != comment else { return }
        comment = nextComment
        configureChickenLegActionButton(count: comment.chickenLegCount, isClicked: comment.isChickenLegClicked)
        setNeedsLayout()
    }

    func updateOpposeReaction(count: Int?, isClicked: Bool) {
        let nextComment = comment.updatingOpposeReaction(count: count, isClicked: isClicked)
        guard nextComment != comment else { return }
        comment = nextComment
        configureOpposeActionButton(count: comment.opposeCount, isClicked: comment.isOpposeClicked)
        setNeedsLayout()
    }

    private static func reactionCountText(_ count: Int) -> String {
        "\(max(0, count))"
    }

    private static func actionButtonWidth(for countText: String, font: UIFont) -> CGFloat {
        let textWidth = (countText as NSString).size(withAttributes: [.font: font]).width
        return max(52, ceil(15 + 4 + textWidth + 16))
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

    var debugAuthorAttributedTitle: NSAttributedString? {
        authorButtonNode.attributedTitle(for: .normal)
    }

    var debugPosterBadgeAttributedText: NSAttributedString? {
        comment.isPoster ? posterBadgeNode.attributedText : nil
    }

    var debugAuthorBadgeTexts: [String] {
        authorBadgeNodes.compactMap { $0.attributedTitle(for: .normal)?.string }
    }

    var debugAuthorBadgeBorderWidths: [CGFloat] {
        authorBadgeNodes.map(\.borderWidth)
    }

    var debugAuthorBadgeTitleColors: [UIColor] {
        authorBadgeNodes.compactMap {
            $0.attributedTitle(for: .normal)?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        }
    }

    var debugHotBadgeImage: UIImage? {
        comment.isHot ? hotBadgeNode.image : nil
    }

    var debugHeaderTopLineText: String {
        var parts: [String] = []
        if let authorName = AuthorDisplayPolicy.displayName(from: comment.authorName) {
            parts.append(authorName)
        }
        if comment.isPoster {
            parts.append(posterBadgeNode.attributedText?.string ?? "")
        }
        parts.append(contentsOf: debugAuthorBadgeTexts)
        if let floorText = comment.floorText?.trimmingCharacters(in: .whitespacesAndNewlines),
           floorText.isEmpty == false {
            parts.append(floorText)
        }
        return parts.filter { $0.isEmpty == false }.joined(separator: " ")
    }

    var debugHeaderTimeLineText: String {
        timeNode.attributedText?.string ?? ""
    }

    var debugReplyActionTitle: String? {
        replyButtonNode.attributedTitle(for: .normal)?.string
    }

    var debugQuoteActionTitle: String? {
        quoteButtonNode.attributedTitle(for: .normal)?.string
    }

    var debugReplyActionImage: UIImage? {
        replyButtonNode.image(for: .normal)
    }

    var debugQuoteActionImage: UIImage? {
        quoteButtonNode.image(for: .normal)
    }

    var debugFooterActionAccessibilityLabels: [String] {
        [
            likeButtonNode,
            chickenLegButtonNode,
            opposeButtonNode,
            replyButtonNode,
            quoteButtonNode
        ].map { $0.accessibilityLabel ?? "" }
    }

    var debugReactionActionTitles: [String?] {
        [
            likeButtonNode,
            chickenLegButtonNode,
            opposeButtonNode
        ].map { $0.attributedTitle(for: .normal)?.string }
    }

    var debugLikeActionColor: UIColor {
        Self.likeActionColor(isClicked: comment.isLikeClicked)
    }

    var debugChickenLegActionColor: UIColor {
        Self.chickenLegActionColor(isClicked: comment.isChickenLegClicked)
    }

    var debugOpposeActionColor: UIColor {
        Self.opposeActionColor(isClicked: comment.isOpposeClicked)
    }

    @objc private func replyTapped() {
        onReplyTapped(comment)
    }

    @objc private func likeTapped() {
        onLikeTapped(comment)
    }

    @objc private func chickenLegTapped() {
        onChickenLegTapped(comment)
    }

    @objc private func opposeTapped() {
        onOpposeTapped(comment)
    }

    @objc private func quoteTapped() {
        onQuoteTapped(comment)
    }

    @objc private func authorTapped() {
        guard let authorProfileURL = comment.authorProfileURL else { return }
        onAuthorTapped(authorProfileURL)
    }

    private func requestAvatarIfNeeded() {
        guard hasDisplayableAuthor else { return }
        guard !hasRequestedAvatar else { return }
        guard let avatarImageView else { return }
        hasRequestedAvatar = true
        avatarLoader.loadAvatar(into: avatarImageView, postID: comment.id, avatarURL: comment.avatarURL)
    }

    private func cancelAvatarLoad() {
        guard let avatarImageView else { return }
        avatarLoader.cancel(on: avatarImageView)
    }
}
