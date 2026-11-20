import UIKit

final class DetailFloorListCell: UICollectionViewCell, UIContextMenuInteractionDelegate {
    private let avatar = UIImageView()
    private let actions = UIStackView()
    private var authorURL: URL?
    private var openAuthor: ((URL) -> Void)?
    var textIndent: CGFloat = 0
    let stack = UIStackView()
    let heading = UILabel()
    let metadata = UILabel()
    let menuButton = UIButton(type: .system)
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
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: inset),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -inset),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8)
        ])
        heading.font = .preferredFont(forTextStyle: .headline)
        metadata.font = .preferredFont(forTextStyle: .subheadline)
        metadata.textColor = .secondaryLabel
        for label in [heading, metadata] {
            label.numberOfLines = 0
            label.adjustsFontForContentSizeCategory = true
        }
        menuButton.setImage(UIImage(systemName: "ellipsis.circle"), for: .normal)
        menuButton.showsMenuAsPrimaryAction = true
        menuButton.accessibilityLabel = DetailListStrings.text("more")
        menuButton.widthAnchor.constraint(equalToConstant: 44).isActive = true
        menuButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        avatar.widthAnchor.constraint(equalToConstant: PostDetailContentLayout.avatarSize).isActive = true
        avatar.heightAnchor.constraint(equalToConstant: PostDetailContentLayout.avatarSize).isActive = true
        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true
        avatar.backgroundColor = .secondarySystemBackground
        avatar.layer.cornerRadius = PostDetailContentLayout.avatarCornerRadius
        avatar.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(showAuthor)))
        avatar.addInteraction(UIContextMenuInteraction(delegate: self))
        let header = UIStackView(arrangedSubviews: [avatar, metadata, menuButton])
        header.spacing = PostDetailContentLayout.avatarSpacing
        header.alignment = .center
        stack.addArrangedSubview(heading)
        stack.addArrangedSubview(header)
        stack.addArrangedSubview(body)
        body.axis = .vertical
        body.spacing = 8
        actions.distribution = .fillEqually
        stack.addArrangedSubview(actions)
    }

    func configureAuthor(name: String, avatarURL: URL?, profileURL: URL?, open: @escaping (URL) -> Void) {
        avatar.isHidden = !AuthorDisplayPolicy.isDisplayable(name)
        avatar.isUserInteractionEnabled = profileURL != nil
        authorURL = profileURL
        openAuthor = open
        if !avatar.isHidden { ImageLoad.url(avatarURL).toAvatar(requestID: request?.id ?? name).into(avatar) }
    }

    @objc private func showAuthor() {
        if let authorURL { openAuthor?(authorURL) }
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let authorURL else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: { UserProfileRouter.makeViewController(profileURL: authorURL) })
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionCommitAnimating) {
        animator.addCompletion { [weak self] in self?.showAuthor() }
    }

    func addAction(_ key: String, symbol: String, count: Int? = nil, selected: Bool = false, perform: @escaping () -> Void) {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: symbol), for: .normal)
        if let count, count > 0 { button.setTitle(" " + count.formatted(), for: .normal) }
        button.titleLabel?.font = AppTypography.commentActionFont()
        button.accessibilityLabel = DetailListStrings.text(key)
        button.accessibilityValue = count.map { String($0) }
        button.tintColor = selected ? .systemOrange : .secondaryLabel
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
        button.addAction(UIAction { _ in perform() }, for: .touchUpInside)
        actions.addArrangedSubview(button)
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
        actions.arrangedSubviews.forEach { $0.removeFromSuperview() }
        contentInstalled = false
        request = nil
        copyText = nil
        didInstall = nil
        body.removeFromSuperview()
        body = DetailBlockStack()
        body.axis = .vertical
        body.spacing = 8
        stack.insertArrangedSubview(body, at: 2)
        menuButton.menu = nil
        accessibilityIdentifier = nil
    }

    func bind(_ request: DetailFloorRequest) {
        clear()
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
        return ceil(measured.height) + 16
    }
}

enum DetailListStrings {
    static func text(_ key: String) -> String { NSLocalizedString(key, tableName: "DetailPrototype", comment: "") }
}
