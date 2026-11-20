import UIKit

final class DetailFloorListCell: UICollectionViewCell, UIContextMenuInteractionDelegate {
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
        let perform: () -> Bool
    }

    private let menuSurface = UIView()
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
    private(set) var body = DetailBlockStack()
    private(set) var request: DetailFloorRequest?
    private(set) var contentInstalled = false
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
        contentView.insertSubview(menuSurface, at: 0)
        avatar.widthAnchor.constraint(equalToConstant: PostDetailContentLayout.avatarSize).isActive = true
        avatar.heightAnchor.constraint(equalToConstant: PostDetailContentLayout.avatarSize).isActive = true
        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true
        avatar.backgroundColor = .secondarySystemBackground
        avatar.layer.cornerRadius = PostDetailContentLayout.avatarCornerRadius
        avatar.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(showAuthor)))
        avatar.addInteraction(UIContextMenuInteraction(delegate: self))
        metadata.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(showAuthor)))
        identity.spacing = 5
        identity.alignment = .center
        identity.addArrangedSubview(metadata)
        identity.addArrangedSubview(UIView())
        identity.addArrangedSubview(floorNumber)
        header.axis = .vertical
        header.distribution = .equalCentering
        header.spacing = 3
        header.addArrangedSubview(identity)
        header.addArrangedSubview(timestamp)
        header.isLayoutMarginsRelativeArrangement = true
        headerHeight = header.heightAnchor.constraint(greaterThanOrEqualToConstant: 28)
        headerHeight.isActive = true
        stack.addArrangedSubview(heading)
        stack.addArrangedSubview(header)
        stack.addArrangedSubview(body)
        body.axis = .vertical
        body.spacing = 8

        contentView.addSubview(avatar)
        avatar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            avatar.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            avatar.topAnchor.constraint(equalTo: header.topAnchor)
        ])
        let separator = UIView()
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

    func configureHeader(title: String?, name: String, badges: [String], time: String?, floor: String?) {
        let isReply = title == nil
        let hasAuthor = AuthorDisplayPolicy.isDisplayable(name)
        let metrics = UIFontMetrics(forTextStyle: .subheadline)
        let small = metrics.scaledFont(for: AppTypography.commentMetadataFont(), compatibleWith: traitCollection)
        let authorFont = metrics.scaledFont(for: isReply ? AppTypography.commentAuthorFont() : AppTypography.detailMetadataFont(), compatibleWith: traitCollection)
        let author = NSMutableAttributedString(string: hasAuthor ? name : "", attributes: [
            .font: authorFont, .foregroundColor: isReply ? ReadingColors.text : UIColor.secondaryLabel
        ])
        let details = badges + (!isReply && badges.isEmpty ? [time].compactMap { $0 } : [])
        for detail in details where !detail.isEmpty {
            author.append(NSAttributedString(string: (author.length == 0 ? "" : "  ") + detail,
                                             attributes: [.font: small, .foregroundColor: UIColor.secondaryLabel]))
        }
        metadata.accessibilityLabel = nil
        metadata.attributedText = author
        floorNumber.font = small
        floorNumber.text = floor
        floorNumber.isHidden = floor?.isEmpty != false
        timestamp.font = small
        timestamp.text = time
        timestamp.isHidden = time?.isEmpty != false || (!isReply && badges.isEmpty)
        header.directionalLayoutMargins = .init(top: 0, leading: hasAuthor ? PostDetailContentLayout.avatarSize + PostDetailContentLayout.avatarSpacing : 0, bottom: 0, trailing: 0)
        headerHeight.constant = !isReply && hasAuthor ? PostDetailContentLayout.avatarSize : 0
        heading.text = title
        heading.isHidden = isReply
        heading.font = UIFontMetrics(forTextStyle: .headline).scaledFont(for: AppTypography.detailTitleFont(), compatibleWith: traitCollection)
        topInset.constant = isReply ? PostDetailContentLayout.commentTopInset : 18
        bottomInset = isReply ? PostDetailContentLayout.commentBottomInset : 14
        stack.spacing = isReply ? 8 : 12
        stack.setCustomSpacing(isReply ? 8 : 18, after: header)
        body.spacing = stack.spacing
    }

    func configureAuthor(name: String, avatarURL: URL?, profileURL: URL?, open: @escaping (URL) -> Void) {
        avatar.isHidden = !AuthorDisplayPolicy.isDisplayable(name)
        avatar.isUserInteractionEnabled = profileURL != nil
        metadata.isUserInteractionEnabled = profileURL != nil
        authorURL = profileURL
        openAuthor = open
        if !avatar.isHidden { ImageLoad.url(avatarURL).toAvatar(requestID: request?.id ?? name).into(avatar) }
    }

    @objc private func showAuthor() {
        if let authorURL { openAuthor?(authorURL) }
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
            if view === body { return menuSurface }
            container = view.superview
        }
        return hit
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        if interaction.view === menuSurface {
            guard !floorActions.isEmpty else { return nil }
            let actions = floorActions
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
                UIMenu(children: actions.map { action in UIAction(title: action.title) { _ in _ = action.perform() } })
            }
        }
        guard interaction.view === avatar, let authorURL else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: { UserProfileRouter.makeViewController(profileURL: authorURL) })
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionCommitAnimating) {
        guard interaction.view === avatar else { return }
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

    func addAction(_ key: String, symbol: String, count: Int? = nil, selected: Bool = false, enabled: Bool = true, perform: @escaping () -> Void) {
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
        button.isEnabled = enabled
        footer.isHidden = false
        button.setTitle(count.flatMap { $0 > 0 ? " " + $0.formatted() : nil }, for: .normal)
        button.titleLabel?.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: AppTypography.commentActionFont(), compatibleWith: traitCollection)
        button.minimumWidth.constant = (count ?? 0) > 0 ? PostDetailContentLayout.reactionActionMinWidth : PostDetailContentLayout.reactionIconOnlyWidth
        button.accessibilityLabel = DetailListStrings.text(key)
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
        renderTask?.cancel()
        renderTask = nil
        signatureTask?.cancel()
        signatureTask = nil
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

    private func install(_ delivered: DetailFloorRequest, _ layout: consuming DetailFloorLayout) {
        guard request == delivered else { return }
        contentInstalled = true
        body.arrangedSubviews.forEach { $0.removeFromSuperview() }
        switch layout {
        case .native(let blocks):
            onNative?(blocks)
            body.append(blocks, to: body, width: delivered.appearance.width)
        case .webpage(let blocks):
            body.appendLegacy(blocks, to: body, width: delivered.appearance.width)
            copyText = copyText ?? CommentCopyTextFormatter.plainText(from: blocks, includingStickerCodes: true)
        }
        body.refreshPlayback()
        didInstall?()
    }

    func loadSignature(_ html: String, for floor: DetailFloorRequest) {
        let request = DetailFloorRequest(id: floor.id, version: floor.version, source: .init(html: html, visibleMarkdown: nil),
                                         appearance: floor.appearance, baseURL: floor.baseURL)
        signatureTask = body.renderer.start(request) { [weak self] _, layout in
            guard let self, self.request == floor, case .webpage(let blocks) = layout else { return }
            let signature = DetailBlockStack()
            signature.axis = .vertical
            signature.spacing = 4
            signature.onLink = self.body.onLink
            signature.onSignatureLinks = self.body.onSignatureLinks
            signature.onPhotos = self.body.onPhotos
            signature.onSizeChange = self.body.onSizeChange
            signature.viewport = self.body.viewport
            self.signatureStack = signature
            signature.isLayoutMarginsRelativeArrangement = true
            signature.directionalLayoutMargins = .init(top: 0, leading: self.textIndent, bottom: 0, trailing: 0)
            self.stack.insertArrangedSubview(signature, at: 3)
            signature.appendLegacy(PostDetailViewController.styledSignatureBlocks(blocks), to: signature, width: floor.appearance.width)
            self.didInstall?()
        }
    }

    func measuredHeight(width: CGFloat) -> CGFloat {
        let size = CGSize(width: width - 2 * PostDetailContentLayout.horizontalInset, height: UIView.layoutFittingCompressedSize.height)
        let measured = stack.systemLayoutSizeFitting(size, withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        return ceil(measured.height + topInset.constant + bottomInset)
    }
}

enum DetailListStrings {
    static func text(_ key: String) -> String { NSLocalizedString(key, tableName: "DetailPrototype", comment: "") }
}
