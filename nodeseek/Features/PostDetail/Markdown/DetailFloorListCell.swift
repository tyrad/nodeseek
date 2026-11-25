import UIKit

final class DetailFloorListCell: UICollectionViewCell, UIContextMenuInteractionDelegate {
    private let separator = UIView()
    private let avatar = UIImageView()
    private let actions = UIStackView()
    private let footer = UIScrollView()
    private let actionSpacer = UIView()
    private var actionButtons: [FloorButton] = []
    private var usedButtonCount = 0

    private final class FloorButton: UIButton {
        var perform: (() -> Void)?
        lazy var minimumWidth = widthAnchor.constraint(greaterThanOrEqualToConstant: 0)

        func prepare() {
            titleLabel?.adjustsFontForContentSizeCategory = true
            setContentHuggingPriority(.required, for: .horizontal)
            setContentCompressionResistancePriority(.required, for: .horizontal)
            NSLayoutConstraint.activate([
                minimumWidth,
                heightAnchor.constraint(greaterThanOrEqualToConstant: PostDetailContentLayout.reactionActionHeight)
            ])
            addTarget(self, action: #selector(tapped), for: .touchUpInside)
        }

        @objc private func tapped() { perform?() }
    }
    private let identity = UIStackView()
    private let header = UIStackView()
    private let floorNumber = UILabel()
    private let timestamp = UILabel()
    private let posterBadge = UILabel()
    private let badgeRow = UIStackView()
    /// 作者标签放不下时折到下一行。
    private let overflowRows = UIStackView()
    private var badgeLabels: [AuthorBadgeLabel] = []
    private let hotBadge = UIImageView()
    private let riskWarning = DetailRiskWarningView()
    private var topInset: NSLayoutConstraint!
    private var headerHeight: NSLayoutConstraint!
    private var bottomInset: CGFloat = 0
    private var authorURL: URL?
    private var openAuthor: ((URL) -> Void)?
    var textIndent: CGFloat = 0
    let stack = UIStackView()
    let heading = UILabel()
    let metadata = UILabel()
    struct FloorAction {
        let title: String
        var image: UIImage?
        let perform: () -> Bool
    }

    private let menuSurface = UIView()
    private weak var anchorHighlight: UIView?
    var floorActions: [FloorAction] = [] {
        didSet {
            for label in [heading, floorNumber, metadata] { label.accessibilityCustomActions = nil }
            let anchor = !heading.isHidden ? heading : !floorNumber.isHidden ? floorNumber : metadata
            anchor.accessibilityCustomActions = floorActions.map { action in
                UIAccessibilityCustomAction(name: action.title) { _ in action.perform() }
            }
            if anchor === metadata && metadata.text?.isEmpty != false {
                metadata.accessibilityLabel = DetailListStrings.text("more")
            }
        }
    }
    /// 主楼计数过万按「万 / 亿」缩写；回复楼层显示原数字。
    var compactCounts = false
    private(set) var body = DetailBlockStack()
    private(set) var request: DetailFloorRequest?
    private(set) var contentInstalled = false
    private var signatureLoading = false
    /// 正文和签名都已装入，楼层高度不会再因异步内容变化。
    var isSettled: Bool { contentInstalled && !signatureLoading }
    private(set) var copyText: String?
    var onNative: (([DetailLayoutBlock]) -> Void)?
    private var signatureStack: DetailBlockStack?
    private var signatureTask: Task<Void, Never>?
    var renderTask: Task<Void, Never>?
    var didInstall: (() -> Void)?
    final class Receiver {
        private weak var cell: DetailFloorListCell?

        init(_ cell: DetailFloorListCell) { self.cell = cell }

        func install(_ request: DetailFloorRequest, _ layout: sending DetailFloorLayout) {
            cell?.install(request, layout)
        }
    }
    private(set) lazy var receiver = Receiver(self)

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .systemBackground
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        let inset = PostDetailContentLayout.horizontalInset
        topInset = stack.topAnchor.constraint(equalTo: contentView.topAnchor)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: inset),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -inset),
            topInset
        ])
        heading.font = .preferredFont(forTextStyle: .headline)
        metadata.font = .preferredFont(forTextStyle: .subheadline)
        metadata.textColor = .secondaryLabel
        for label in [heading, metadata, floorNumber, timestamp] {
            label.numberOfLines = 0
            label.adjustsFontForContentSizeCategory = true
        }
        floorNumber.textColor = .tertiaryLabel
        floorNumber.textAlignment = .natural
        floorNumber.setContentHuggingPriority(.required, for: .horizontal)
        timestamp.textColor = .secondaryLabel
        // 把菜单装在正文的同级视图上，文字和媒体的触摸不会进入菜单的识别器。
        menuSurface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        menuSurface.frame = contentView.bounds
        menuSurface.addInteraction(UIContextMenuInteraction(delegate: self))
        menuSurface.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapNearBodyLink(_:))))
        contentView.insertSubview(menuSurface, at: 0)
        avatar.widthAnchor.constraint(equalToConstant: PostDetailContentLayout.avatarSize).isActive = true
        avatar.heightAnchor.constraint(equalToConstant: PostDetailContentLayout.avatarSize).isActive = true
        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true
        avatar.backgroundColor = .secondarySystemBackground
        avatar.layer.cornerRadius = PostDetailContentLayout.avatarCornerRadius
        avatar.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(showAuthor)))
        avatar.addInteraction(UIContextMenuInteraction(delegate: self))
        // E2E 按这些标识定位作者，不要改名。
        avatar.accessibilityIdentifier = "comment-author-avatar"
        metadata.accessibilityIdentifier = "comment-author-name"
        metadata.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(showAuthor)))
        metadata.addInteraction(UIContextMenuInteraction(delegate: self))
        // 作者名、楼主、状态标签各自独立，作者名过长时先换行，标签保持完整。
        metadata.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        posterBadge.accessibilityIdentifier = "detail-poster-badge"
        posterBadge.text = DetailListStrings.text("poster")
        posterBadge.textColor = .systemOrange
        posterBadge.adjustsFontForContentSizeCategory = true
        badgeRow.spacing = 5
        badgeRow.alignment = .center
        hotBadge.accessibilityIdentifier = "detail-hot-badge"
        hotBadge.isAccessibilityElement = true
        hotBadge.accessibilityLabel = DetailListStrings.text("hot-comment")
        hotBadge.contentMode = .scaleAspectFit
        hotBadge.image = UIImage(systemName: "flame.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
        hotBadge.tintColor = .systemOrange
        for view in [posterBadge, badgeRow, hotBadge] as [UIView] {
            view.setContentHuggingPriority(.required, for: .horizontal)
            view.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        identity.spacing = 5
        identity.alignment = .center
        identity.addArrangedSubview(metadata)
        identity.addArrangedSubview(posterBadge)
        identity.addArrangedSubview(badgeRow)
        identity.addArrangedSubview(UIView())
        identity.addArrangedSubview(hotBadge)
        identity.setCustomSpacing(4, after: hotBadge)
        identity.addArrangedSubview(floorNumber)
        header.axis = .vertical
        header.distribution = .equalCentering
        header.spacing = 3
        header.addArrangedSubview(identity)
        overflowRows.axis = .vertical
        overflowRows.alignment = .leading
        overflowRows.spacing = 3
        overflowRows.isHidden = true
        header.addArrangedSubview(overflowRows)
        header.addArrangedSubview(timestamp)
        header.isLayoutMarginsRelativeArrangement = true
        headerHeight = header.heightAnchor.constraint(greaterThanOrEqualToConstant: 28)
        headerHeight.isActive = true
        stack.addArrangedSubview(heading)
        stack.addArrangedSubview(header)
        stack.addArrangedSubview(body)
        body.axis = .vertical
        body.spacing = 8
        riskWarning.isHidden = true
        stack.addArrangedSubview(riskWarning)

        contentView.addSubview(avatar)
        avatar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            avatar.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            avatar.topAnchor.constraint(equalTo: header.topAnchor)
        ])
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator
        contentView.addSubview(separator)
        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / max(1, traitCollection.displayScale))
        ])
        actions.spacing = PostDetailContentLayout.reactionActionSpacing
        actions.addArrangedSubview(actionSpacer)
        actions.translatesAutoresizingMaskIntoConstraints = false
        footer.showsHorizontalScrollIndicator = false
        footer.addSubview(actions)
        stack.addArrangedSubview(footer)
        NSLayoutConstraint.activate([
            actions.leadingAnchor.constraint(equalTo: footer.contentLayoutGuide.leadingAnchor),
            actions.trailingAnchor.constraint(equalTo: footer.contentLayoutGuide.trailingAnchor),
            actions.topAnchor.constraint(equalTo: footer.contentLayoutGuide.topAnchor),
            actions.bottomAnchor.constraint(equalTo: footer.contentLayoutGuide.bottomAnchor),
            actions.heightAnchor.constraint(equalTo: footer.frameLayoutGuide.heightAnchor),
            actions.widthAnchor.constraint(greaterThanOrEqualTo: footer.frameLayoutGuide.widthAnchor)
        ])
        let fit = actions.widthAnchor.constraint(equalTo: footer.frameLayoutGuide.widthAnchor)
        fit.priority = .defaultLow
        fit.isActive = true
        footer.isHidden = true
    }

    func configureHeader(title: String?, requiredLevel: Int?, name: String, isPoster: Bool = false, badges: [String], time: String?,
                         floor: String?, isHot: Bool = false, showsRiskWarning: Bool = false) {
        let isReply = title == nil
        let hasAuthor = AuthorDisplayPolicy.isDisplayable(name)
        let metrics = UIFontMetrics(forTextStyle: .subheadline)
        let small = metrics.scaledFont(for: AppTypography.commentMetadataFont(), compatibleWith: traitCollection)
        let badgeFont = metrics.scaledFont(for: AppTypography.commentBadgeFont(), compatibleWith: traitCollection)
        let authorFont = metrics.scaledFont(for: isReply ? AppTypography.commentAuthorFont() : AppTypography.detailMetadataFont(), compatibleWith: traitCollection)
        let author = NSMutableAttributedString(string: hasAuthor ? name : "", attributes: [
            .font: authorFont, .foregroundColor: isReply ? ReadingColors.text : UIColor.secondaryLabel
        ])
        // 主楼没有状态标签时，发布信息跟在作者名后；有标签时移到第二行。
        if !isReply, badges.isEmpty, let time, !time.isEmpty {
            author.append(NSAttributedString(string: (author.length == 0 ? "" : "  · ") + time,
                                             attributes: [.font: authorFont, .foregroundColor: UIColor.secondaryLabel]))
        }
        metadata.accessibilityLabel = nil
        metadata.attributedText = author
        metadata.isHidden = author.length == 0
        posterBadge.font = badgeFont
        posterBadge.isHidden = !isPoster
        while badgeLabels.count < badges.count {
            let label = AuthorBadgeLabel()
            badgeLabels.append(label)
            badgeRow.addArrangedSubview(label)
        }
        for (index, label) in badgeLabels.enumerated() {
            label.isHidden = index >= badges.count
            if index < badges.count { label.configure(badges[index], font: badgeFont) }
        }
        riskWarning.isHidden = !showsRiskWarning
        floorNumber.font = small
        floorNumber.text = floor
        floorNumber.isHidden = floor?.isEmpty != false
        timestamp.font = small
        timestamp.text = time
        timestamp.isHidden = time?.isEmpty != false || (!isReply && badges.isEmpty)
        hotBadge.isHidden = !isHot || floorNumber.isHidden
        header.directionalLayoutMargins = .init(top: 0, leading: hasAuthor ? PostDetailContentLayout.avatarSize + PostDetailContentLayout.avatarSpacing : 0, bottom: 0, trailing: 0)
        wrapBadges(Array(badgeLabels.prefix(badges.count)))
        headerHeight.constant = !isReply && hasAuthor ? PostDetailContentLayout.avatarSize : 0
        header.isHidden = !isReply && !hasAuthor && badges.isEmpty && metadata.isHidden
        separator.isHidden = !isReply
        heading.isHidden = isReply
        let titleFont = UIFontMetrics(forTextStyle: .headline).scaledFont(for: AppTypography.detailTitleFont(), compatibleWith: traitCollection)
        heading.font = titleFont
        heading.attributedText = title.map { title in
            let text = NSMutableAttributedString(string: title, attributes: [.font: titleFont, .foregroundColor: ReadingColors.text])
            if let requiredLevel {
                text.append(NSAttributedString(string: " 🔒 \(requiredLevel)", attributes: [.font: authorFont, .foregroundColor: UIColor.systemRed]))
            }
            return text
        }
        topInset.constant = isReply ? PostDetailContentLayout.commentTopInset : 18
        bottomInset = isReply ? PostDetailContentLayout.commentBottomInset : 14
        stack.spacing = isReply ? 8 : 12
        stack.setCustomSpacing(header.isHidden ? 18 : stack.spacing, after: heading)
        stack.setCustomSpacing(isReply ? 8 : 18, after: header)
        body.spacing = stack.spacing
    }

    func configureAuthor(name: String, avatarURL: URL?, profileURL: URL?, open: @escaping (URL) -> Void) {
        avatar.isHidden = !AuthorDisplayPolicy.isDisplayable(name)
        avatar.isUserInteractionEnabled = profileURL != nil
        metadata.isUserInteractionEnabled = profileURL != nil
        authorURL = profileURL
        openAuthor = open
        // 名字可点开主页，读屏说明用途。
        if profileURL != nil, let display = AuthorDisplayPolicy.displayName(from: name) {
            metadata.accessibilityLabel = String(format: DetailListStrings.text("view-profile"), display)
            metadata.accessibilityTraits = .button
        } else {
            metadata.accessibilityTraits = .staticText
        }
        if !avatar.isHidden { ImageLoad.url(avatarURL).toAvatar(requestID: request?.id ?? name).into(avatar) }
    }

    /// 作者标签按作者栏实际宽度折行：第一行跟在作者名、楼主之后，右侧留出热评和楼层号。
    private func wrapBadges(_ labels: [AuthorBadgeLabel]) {
        // 作者栏与正文同在楼层内容区，左侧再让出头像；主楼正文不缩进，不能直接用正文宽度。
        let contentWidth = request.map { $0.appearance.width + textIndent } ?? stack.bounds.width
        let width = contentWidth - header.directionalLayoutMargins.leading
        let spacing = identity.spacing
        func size(_ view: UIView) -> CGFloat { view.isHidden ? 0 : ceil(view.intrinsicContentSize.width) + spacing }
        var used = size(metadata) + size(posterBadge) + size(hotBadge) + size(floorNumber)
        var lineHasContent = !metadata.isHidden || !posterBadge.isHidden
        var lines: [[AuthorBadgeLabel]] = [[]]
        for label in labels {
            let w = ceil(label.intrinsicContentSize.width)
            // 行首的标签即使超宽也放下，避免空行。
            if lineHasContent, used + w > width {
                lines.append([])
                used = 0
            }
            lines[lines.count - 1].append(label)
            used += w + spacing
            lineHasContent = true
        }
        lines[0].forEach(badgeRow.addArrangedSubview)
        badgeRow.isHidden = lines[0].isEmpty
        overflowRows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for line in lines.dropFirst() {
            let row = UIStackView(arrangedSubviews: line)
            row.spacing = spacing
            row.alignment = .center
            overflowRows.addArrangedSubview(row)
        }
        overflowRows.isHidden = lines.count == 1
    }

    @objc private func showAuthor() {
        if let authorURL { openAuthor?(authorURL) }
    }

    // 行末和段落边缘可能落在菜单背景上。仅补单击；长按仍由选字或楼层菜单处理。
    @objc private func tapNearBodyLink(_ tap: UITapGestureRecognizer) {
        openLink(near: tap.location(in: contentView))
    }

    /// 点在正文、签名文字之外的空白处时，找附近的链接。签名在正文下方，点到签名顶部以下时先按签名的放大点击区找。
    func openLink(near point: CGPoint) {
        if let signatureStack, point.y >= signatureStack.convert(signatureStack.bounds, to: contentView).minY {
            for case let text as DetailSelectableTextView in allSubviews(of: signatureStack)
            where !text.isHidden && text.activateLink(at: contentView.convert(point, to: text)) {
                return
            }
        }
        let padding = DetailSelectableTextView.linkHitPadding
        var closest: (url: URL, distance: CGFloat)?
        func visit(_ view: UIView) {
            let point = contentView.convert(point, to: view)
            guard !view.isHidden, view.alpha > 0.01,
                  view.bounds.insetBy(dx: -padding, dy: -padding).contains(point),
                  !view.clipsToBounds || view.bounds.contains(point) else { return }
            if let text = view as? DetailSelectableTextView {
                if let hit = text.linkHit(at: point), hit.distance < closest?.distance ?? .infinity {
                    closest = hit
                }
            } else {
                for child in view.subviews { visit(child) }
            }
        }
        visit(body)
        if let closest { body.onLink?(closest.url) }
    }

    private func allSubviews(of view: UIView) -> [UIView] {
        view.subviews + view.subviews.flatMap(allSubviews)
    }

    func flashAnchorHighlight() {
        clearAnchorHighlight()
        let overlay = UIView(frame: contentView.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.isUserInteractionEnabled = false
        overlay.accessibilityIdentifier = "detail-anchor-highlight"
        overlay.backgroundColor = NodeSeekLinkStyle.color.withAlphaComponent(0.16)
        contentView.addSubview(overlay)
        anchorHighlight = overlay
        UIView.animate(withDuration: 0.35, delay: 0.8, options: [.curveEaseOut, .allowUserInteraction]) {
            overlay.alpha = 0
        } completion: { _ in overlay.removeFromSuperview() }
    }

    func clearAnchorHighlight() {
        anchorHighlight?.removeFromSuperview()
        anchorHighlight = nil
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else { return nil }
        guard !floorActions.isEmpty else { return hit }
        if let text = hit as? DetailSelectableTextView {
            return text.handlesTouch(at: convert(point, to: text)) ? text : menuSurface
        }
        if !avatar.isHidden, avatar.bounds.contains(convert(point, to: avatar)) { return hit }
        if hit === metadata && metadata.isUserInteractionEnabled { return hit }
        if hit === self || hit === contentView || hit === stack || hit === heading || hit.isDescendant(of: header) {
            return menuSurface
        }
        if (hit === actionSpacer || hit === actions || hit === footer),
           footer.contentSize.width <= footer.bounds.width + 1 {
            return menuSurface
        }
        var container: UIView? = hit
        while let view = container as? UIStackView {
            if view === body || view === signatureStack { return menuSurface }
            container = view.superview
        }
        return hit
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        if interaction.view === menuSurface {
            guard let request, !floorActions.isEmpty else { return nil }
            let actions = floorActions
            return UIContextMenuConfiguration(identifier: request.id as NSString, previewProvider: nil) { _ in
                UIMenu(children: actions.map { action in UIAction(title: action.title, image: action.image) { _ in _ = action.perform() } })
            }
        }
        guard interaction.view === avatar || interaction.view === metadata, let authorURL else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: { UserProfileRouter.makeViewController(profileURL: authorURL) })
    }

    private func floorPreview(_ interaction: UIContextMenuInteraction, _ configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        guard interaction.view === menuSurface, let request,
              configuration.identifier as? String == request.id, contentView.window != nil else { return nil }
        // 手势挂在空白层上，系统浮起和放回的快照应包含整层回复。
        return UITargetedPreview(view: contentView)
    }

    @available(iOS 16.0, *)
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configuration: UIContextMenuConfiguration,
                                highlightPreviewForItemWithIdentifier identifier: NSCopying) -> UITargetedPreview? {
        floorPreview(interaction, configuration)
    }

    @available(iOS 16.0, *)
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configuration: UIContextMenuConfiguration,
                                dismissalPreviewForItemWithIdentifier identifier: NSCopying) -> UITargetedPreview? {
        floorPreview(interaction, configuration)
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        floorPreview(interaction, configuration)
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        floorPreview(interaction, configuration)
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionCommitAnimating) {
        guard interaction.view === avatar || interaction.view === metadata else { return }
        animator.addCompletion { [weak self] in self?.showAuthor() }
    }

    func addVotes(like: Int?, chicken: Int?, oppose: Int?, liked: Bool, rewarded: Bool, opposed: Bool, isOwn: Bool,
                  onLike: @escaping () -> Void, onChicken: @escaping () -> Void, onOppose: @escaping () -> Void) {
        if !isOwn || (like ?? 0) > 0 {
            addAction("like", symbol: liked ? "hand.thumbsup.fill" : "hand.thumbsup", count: like, selected: liked, enabled: !isOwn, perform: onLike)
        }
        if !isOwn || (chicken ?? 0) > 0 {
            addAction("chicken", symbol: "fork.knife", count: chicken, selected: rewarded, enabled: !isOwn, perform: onChicken)
        }
        if !isOwn || (oppose ?? 0) > 0 {
            addAction("oppose", symbol: opposed ? "hand.thumbsdown.fill" : "hand.thumbsdown", count: oppose, selected: opposed, enabled: !isOwn, perform: onOppose)
        }
    }

    func addAction(_ key: String, symbol: String, count: Int? = nil, selected: Bool = false, enabled: Bool = true,
                   label: String? = nil, identifier: String? = nil, perform: @escaping () -> Void) {
        let button: FloorButton
        if usedButtonCount < actionButtons.count {
            button = actionButtons[usedButtonCount]
        } else {
            button = FloorButton(type: .system)
            button.prepare()
            actionButtons.append(button)
            actions.addArrangedSubview(button)
        }
        usedButtonCount += 1
        button.isHidden = false
        button.perform = perform
        let config = UIImage.SymbolConfiguration(pointSize: PostDetailContentLayout.reactionSymbolPointSize, weight: .regular)
        let icon = key == "chicken" ? UIImage(named: "ChickenLeg") : UIImage(systemName: symbol)
        button.setImage(icon?.applyingSymbolConfiguration(config)?.withRenderingMode(.alwaysTemplate), for: .normal)
        // 系统按钮默认会把符号按自身样式再放大一档，固定为 14pt 才与正文配套。
        button.setPreferredSymbolConfiguration(config, forImageIn: .normal)
        button.isEnabled = enabled
        footer.isHidden = false
        button.setTitle(count.flatMap { $0 > 0 ? " " + (compactCounts ? PostBodyCellNode.reactionCountText($0) : String($0)) : nil }, for: .normal)
        button.titleLabel?.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: AppTypography.commentActionFont(), compatibleWith: traitCollection)
        button.minimumWidth.constant = (count ?? 0) > 0 ? PostDetailContentLayout.reactionActionMinWidth : PostDetailContentLayout.reactionIconOnlyWidth
        button.accessibilityLabel = DetailListStrings.text(label ?? key)
        button.accessibilityIdentifier = identifier
        button.accessibilityValue = count.map { String($0) }
        button.tintColor = selected ? (key == "chicken" || key == "favorite" ? .systemOrange : .systemRed) : UIColor.secondaryLabel.withAlphaComponent(PostDetailContentLayout.inactiveReactionAlpha)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { renderTask?.cancel(); signatureTask?.cancel() }

    override func prepareForReuse() {
        super.prepareForReuse()
        clear()
    }

    func clear() {
        clearAnchorHighlight()
        renderTask?.cancel()
        renderTask = nil
        signatureTask?.cancel()
        signatureTask = nil
        signatureLoading = false
        signatureStack?.removeFromSuperview()
        signatureStack = nil
        onNative = nil
        AvatarImageLoader.shared.cancel(on: avatar)
        avatar.image = nil
        authorURL = nil
        openAuthor = nil
        for button in actionButtons.prefix(usedButtonCount) {
            button.perform = nil
            button.minimumWidth.constant = 0
            button.isHidden = true
        }
        usedButtonCount = 0
        footer.isHidden = true
        footer.contentOffset = .zero
        contentInstalled = false
        request = nil
        copyText = nil
        didInstall = nil
        body.removeFromSuperview()
        body = DetailBlockStack()
        body.axis = .vertical
        body.spacing = 8
        stack.insertArrangedSubview(body, at: 2)
        floorActions = []
        accessibilityIdentifier = nil
    }

    func bind(_ request: DetailFloorRequest) {
        // diffable 重配可跳过 prepareForReuse；首次绑定和刚完成复用的空楼层无需再拆一次视图。
        if self.request != nil { clear() }
        self.request = request
        body.appearance = request.appearance
        copyText = request.source.visibleMarkdown
        accessibilityIdentifier = request.id
    }

    func installPageSummary(_ request: DetailFloorRequest, hasAvatar: Bool) {
        body.isHidden = true
        if !hasAvatar {
            avatar.isHidden = true
            header.directionalLayoutMargins.leading = 0
            headerHeight.constant = 0
        }
        install(request, .native([]))
    }

    private func install(_ delivered: DetailFloorRequest, _ layout: consuming DetailFloorLayout) {
        guard request == delivered else { return }
        contentInstalled = true
        body.removeAllBlocks()
        switch layout {
        case .native(let blocks):
            onNative?(blocks)
            body.append(blocks, to: body, width: delivered.appearance.width)
        case .webpage(let blocks):
            #if DEBUG
            body.appendMarkdownFallbackNotice(for: delivered.source)
            #endif
            body.appendLegacy(blocks, to: body, width: delivered.appearance.width)
            copyText = copyText ?? CommentCopyTextFormatter.plainText(from: blocks, includingStickerCodes: true)
        }
        body.refreshPlayback()
        didInstall?()
    }

    /// 正文与签名的动图都按是否在可视区内播放。
    func refreshPlayback() {
        body.refreshPlayback()
        signatureStack?.refreshPlayback()
    }

    /// 签名用 TextKit 排版，字号单独给出；结构不支持时退回网页渲染。
    func loadSignature(_ html: String, pointSize: CGFloat, for floor: DetailFloorRequest) {
        let appearance = DetailTextAppearance(width: floor.appearance.width, pointSize: pointSize,
                                              scale: floor.appearance.scale, dark: floor.appearance.dark)
        let request = DetailFloorRequest(id: floor.id, version: floor.version, source: .init(html: html, visibleMarkdown: nil),
                                         appearance: appearance, baseURL: floor.baseURL)
        signatureLoading = true
        signatureTask = body.renderer.startSignature(request) { [weak self] _, layout in
            guard let self, self.request == floor else { return }
            self.signatureLoading = false
            let signature = DetailBlockStack()
            signature.axis = .vertical
            signature.spacing = 4
            signature.onLink = self.body.onLink
            signature.onSignatureLinks = self.body.onSignatureLinks
            // 签名里每个链接至少 72×48 的点击区。
            signature.linkTargetSize = CGSize(width: 72, height: 48)
            signature.onPhotos = self.body.onPhotos
            signature.onStickerSizeChange = self.body.onStickerSizeChange
            signature.imageSize = self.body.imageSize
            signature.onImageSize = self.body.onImageSize
            signature.onSizeChange = self.body.onSizeChange
            signature.viewport = self.body.viewport
            self.signatureStack = signature
            signature.accessibilityIdentifier = "detail-signature"
            signature.isLayoutMarginsRelativeArrangement = true
            signature.directionalLayoutMargins = .init(top: 0, leading: self.textIndent, bottom: 0, trailing: 0)
            self.stack.insertArrangedSubview(signature, at: 3)
            switch layout {
            case .native(let blocks):
                signature.append(blocks, to: signature, width: floor.appearance.width)
            case .webpage(let blocks):
                signature.appendLegacy(PostDetailViewController.styledSignatureBlocks(blocks), to: signature, width: floor.appearance.width)
            }
            signature.refreshPlayback()
            self.didInstall?()
        }
    }

    func measuredHeight(width: CGFloat) -> CGFloat {
        let size = CGSize(width: width - 2 * PostDetailContentLayout.horizontalInset, height: UIView.layoutFittingCompressedSize.height)
        let measured = stack.systemLayoutSizeFitting(size, withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        return ceil(measured.height + topInset.constant + bottomInset)
    }
}

/// 作者状态标签，样式同 `AuthorStatusBadgeNode`：禁言、封禁标红，其余用分隔线色描边。
final class AuthorBadgeLabel: UILabel {
    private let insets = UIEdgeInsets(top: 2, left: 5, bottom: 2, right: 5)
    private var isMuted = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "detail-author-badge"
        adjustsFontForContentSizeCategory = true
        layer.cornerRadius = 4
        layer.borderWidth = 1
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ text: String, font: UIFont) {
        self.text = text
        self.font = font
        accessibilityLabel = text
        isMuted = text.contains("禁言") || text.contains("封禁")
        applyColors()
    }

    private func applyColors() {
        textColor = isMuted ? .systemRed : .label
        layer.borderColor = (isMuted ? UIColor.systemRed : UIColor.separator).resolvedColor(with: traitCollection).cgColor
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyColors()
    }

    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }
}

/// 楼主等级过低时的交易提醒卡片，样式同 `PostAuthorRiskWarningNode`。
final class DetailRiskWarningView: UIView {
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "detail-risk-warning"
        backgroundColor = UIColor.systemOrange.withAlphaComponent(0.12)
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        clipsToBounds = true
        let icon = UIImageView(image: UIImage(systemName: "exclamationmark.shield.fill"))
        icon.tintColor = .systemOrange
        icon.isAccessibilityElement = false
        label.text = PostAuthorRiskWarningNode.message
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.numberOfLines = 0
        for view in [icon, label] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            icon.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            icon.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -12)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

enum DetailListStrings {
    static func text(_ key: String) -> String { NSLocalizedString(key, tableName: "DetailPrototype", comment: "") }
}
