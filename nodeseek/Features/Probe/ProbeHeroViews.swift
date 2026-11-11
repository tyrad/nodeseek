import UIKit

/// 顶部卡片铺在液态玻璃上，文字和圆环都用系统颜色，深浅模式自动适配。
private enum ProbeHeroPalette {
    static let primary = UIColor.label
    static let secondary = UIColor.secondaryLabel
    static let track = UIColor.tertiarySystemFill
    static let divider = UIColor.separator
}

/// 带内边距的小标签，用于状态胶囊和底部“离线 / 最忙”标记。
final class ProbeTagLabel: UILabel {
    var insets = UIEdgeInsets(top: 3, left: 8, bottom: 3, right: 8) {
        didSet { if insets != oldValue { invalidateIntrinsicContentSize() } }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerCurve = .continuous
        clipsToBounds = true
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }
}

/// 小圆环：中间写百分比，颜色跟随指标，超过阈值变橙、变红。
final class ProbeRingView: UIView {
    static let diameter: CGFloat = 40
    private let track = CAShapeLayer()
    private let progress = CAShapeLayer()
    private let valueLabel = UILabel()
    private var trackColor: UIColor = .tertiarySystemFill
    private var progressColor: UIColor = .systemBlue

    private(set) var fraction: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        for layer in [track, progress] {
            layer.fillColor = nil
            layer.lineWidth = 4
            layer.lineCap = .round
            self.layer.addSublayer(layer)
        }
        valueLabel.textAlignment = .center
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.7
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(valueLabel)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.diameter),
            heightAnchor.constraint(equalToConstant: Self.diameter),
            valueLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -10),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(percent: Double?, metric: ProbeStyle.Metric, textColor: UIColor, trackColor: UIColor) {
        self.trackColor = trackColor
        progressColor = ProbeStyle.color(for: metric, percent: percent)
        fraction = CGFloat(min(max((percent ?? 0) / 100, 0), 1))
        let text = NSMutableAttributedString(string: percent.map { ProbeFormat.percent($0, decimals: 0) } ?? "—", attributes: [
            .font: ProbeStyle.digits(12, .semibold), .foregroundColor: textColor,
        ])
        if percent != nil {
            text.append(NSAttributedString(string: "%", attributes: [
                .font: UIFont.systemFont(ofSize: 8, weight: .semibold), .foregroundColor: textColor,
            ]))
        }
        valueLabel.attributedText = text
        // 刷新时不做弧长动画，避免每 10 秒全部圆环跳一下。
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progress.strokeEnd = fraction
        applyColors()
        CATransaction.commit()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = track.lineWidth / 2
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let path = UIBezierPath(arcCenter: CGPoint(x: rect.midX, y: rect.midY), radius: rect.width / 2,
                                startAngle: -.pi / 2, endAngle: .pi * 1.5, clockwise: true).cgPath
        track.path = path
        progress.path = path
        applyColors()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyColors()
    }

    private func applyColors() {
        track.strokeColor = trackColor.resolvedColor(with: traitCollection).cgColor
        progress.strokeColor = progressColor.resolvedColor(with: traitCollection).cgColor

    }
}

/// 底部一行按下时变淡。
private final class ProbeHeroFooterControl: UIControl {
    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.5 : 1 }
    }
}

/// 一个探针的汇总卡：名称与状态、类型地址与刷新时间、在线数、三项平均用量，以及“现在该看哪台”。
final class ProbeHeroCardView: UIView {
    var onSpotlight: ((String) -> Void)?

    private let titleLabel = ProbeStyle.label(.systemFont(ofSize: 17, weight: .bold))
    private let statusTag = ProbeTagLabel()
    private let metaLabel = ProbeStyle.label(.systemFont(ofSize: 12, weight: .regular))
    private let countLabel = UILabel()
    private let rings = (0..<3).map { _ in ProbeRingView() }
    private let ringCaptions = (0..<3).map { _ in ProbeStyle.label(.systemFont(ofSize: 10, weight: .medium)) }
    private let divider = UIView()
    private let footer = ProbeHeroFooterControl()
    private let footerTag = ProbeTagLabel()
    private let footerTitle = ProbeStyle.label(.systemFont(ofSize: 14, weight: .semibold))
    private let footerDetail = ProbeStyle.label(ProbeStyle.mono(12, .medium))
    private let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
    private let glassView = UIVisualEffectView()
    private static let tagInsets = UIEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)
    private var spotlightID: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        if #available(iOS 26.0, *) {
            let glass = UIGlassEffect(style: .regular)
            glass.isInteractive = true
            glassView.effect = glass
        } else {
            glassView.effect = UIBlurEffect(style: .systemThinMaterial)
        }
        // 圆角裁在玻璃上，不裁卡片本身，避免把玻璃边缘的高光裁掉。
        glassView.layer.cornerRadius = ProbeStyle.cardRadius
        glassView.layer.cornerCurve = .continuous
        glassView.clipsToBounds = true
        glassView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glassView)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusTag.font = .systemFont(ofSize: 11, weight: .semibold)
        metaLabel.lineBreakMode = .byTruncatingMiddle
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        footerTag.font = .systemFont(ofSize: 11, weight: .semibold)
        footerTag.insets = Self.tagInsets
        footerTitle.lineBreakMode = .byTruncatingTail
        footerTitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        footerDetail.setContentCompressionResistancePriority(.required, for: .horizontal)
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        chevron.setContentHuggingPriority(.required, for: .horizontal)

        let titleRow = UIStackView(arrangedSubviews: [titleLabel, UIView(), statusTag])
        titleRow.alignment = .center
        titleRow.spacing = 8

        let ringColumns: [UIView] = zip(rings, ringCaptions).map { ring, caption in
            let column = UIStackView(arrangedSubviews: [ring, caption])
            column.axis = .vertical
            column.alignment = .center
            column.spacing = 3
            return column
        }
        let ringRow = UIStackView(arrangedSubviews: ringColumns)
        ringRow.spacing = 10
        let mainRow = UIStackView(arrangedSubviews: [countLabel, UIView(), ringRow])
        mainRow.alignment = .bottom
        mainRow.spacing = 8

        let footerRow = UIStackView(arrangedSubviews: [footerTag, footerTitle, UIView(), footerDetail, chevron])
        footerRow.alignment = .center
        footerRow.spacing = 6
        footerRow.setCustomSpacing(4, after: footerDetail)
        footerRow.isUserInteractionEnabled = false
        footerRow.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(footerRow)
        footer.addAction(UIAction { [weak self] _ in
            guard let self, let id = spotlightID else { return }
            onSpotlight?(id)
        }, for: .touchUpInside)
        footer.accessibilityIdentifier = "probe-hero-spotlight"

        let column = UIStackView(arrangedSubviews: [titleRow, metaLabel, mainRow])
        column.axis = .vertical
        column.spacing = 3
        column.setCustomSpacing(6, after: metaLabel)
        // 内容放进玻璃的 contentView，按压时玻璃才能收到触摸并给出反馈。
        [column, divider, footer].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            glassView.contentView.addSubview($0)
        }
        NSLayoutConstraint.activate([
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor),
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            column.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            divider.topAnchor.constraint(equalTo: column.bottomAnchor, constant: 8),
            divider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            divider.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            footer.topAnchor.constraint(equalTo: divider.bottomAnchor),
            footer.leadingAnchor.constraint(equalTo: leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 38),
            footerRow.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 16),
            footerRow.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -16),
            footerRow.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// `interactive` 为 false 时（两侧缩小的卡片）底部一行不响应点按，点卡片只负责切换。
    func configure(_ card: ProbeCard, interactive: Bool) {
        footer.isEnabled = interactive && card.spotlight != nil
        // 两侧卡片的点按交给集合视图，用来滑到这张卡。
        footer.isUserInteractionEnabled = interactive
        spotlightID = card.spotlight?.entryID
        apply(card)
    }

    private func apply(_ card: ProbeCard) {
        let palette = ProbeHeroPalette.self
        let summary = card.summary
        titleLabel.text = card.name
        titleLabel.textColor = palette.primary

        let status: (String, UIColor)
        if card.hasError {
            status = ("连接失败", .systemRed)
        } else if summary.total == 0 {
            status = ("暂无数据", palette.secondary)
        } else if summary.offline > 0 {
            status = ("● \(summary.offline) 台离线", .systemRed)
        } else {
            status = ("● 全部在线", .systemGreen)
        }
        statusTag.text = status.0
        statusTag.textColor = status.1
        statusTag.backgroundColor = status.1 == palette.secondary ? .clear : status.1.withAlphaComponent(0.15)

        metaLabel.text = [card.subtitle, card.updated].filter { !$0.isEmpty }.joined(separator: " · ")
        metaLabel.textColor = palette.secondary

        let count = NSMutableAttributedString(string: "\(summary.online)", attributes: [
            .font: ProbeStyle.digits(summary.total >= 100 ? 34 : 40), .foregroundColor: palette.primary, .kern: -1,
        ])
        count.append(NSAttributedString(string: "/\(summary.total)", attributes: [
            .font: ProbeStyle.digits(17, .semibold), .foregroundColor: palette.secondary,
        ]))
        count.append(NSAttributedString(string: "  在线", attributes: [
            .font: UIFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: palette.secondary,
        ]))
        countLabel.attributedText = count

        let values: [(Double?, ProbeStyle.Metric, String)] = [
            (card.averageCPU, .cpu, "CPU"), (card.averageMemory, .memory, "内存"), (card.averageDisk, .disk, "硬盘"),
        ]
        for (index, value) in values.enumerated() {
            rings[index].configure(percent: value.0, metric: value.1, textColor: palette.primary, trackColor: palette.track)
            ringCaptions[index].text = value.2
            ringCaptions[index].textColor = palette.secondary
        }

        divider.backgroundColor = palette.divider
        applyFooter(card, palette: palette)
        accessibilityLabel = "\(card.name)，在线 \(summary.online) 台，共 \(summary.total) 台，\(status.0.replacingOccurrences(of: "● ", with: ""))，\(card.updated)"
    }

    private func applyFooter(_ card: ProbeCard, palette: ProbeHeroPalette.Type) {
        guard let spotlight = card.spotlight else {
            footerTag.isHidden = true
            chevron.isHidden = true
            footerDetail.text = nil
            footerTitle.text = card.hasError ? "连接失败，下拉可重试" : "暂无在线服务器的数据"
            footerTitle.font = .systemFont(ofSize: 13, weight: .regular)
            footerTitle.textColor = palette.secondary
            footer.accessibilityLabel = footerTitle.text
            return
        }
        footerTag.isHidden = false
        chevron.isHidden = false
        footerTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        footerTitle.text = spotlight.title
        footerTitle.textColor = palette.primary
        footerDetail.text = spotlight.detail
        chevron.tintColor = palette.secondary
        switch spotlight.kind {
        case .offline:
            footerTag.text = "离线"
            footerTag.insets = Self.tagInsets
            footerTag.textColor = .systemRed
            footerTag.backgroundColor = UIColor.systemRed.withAlphaComponent(0.15)
            footerDetail.textColor = .systemRed
        case .busiest:
            // 玻璃上的浅灰底色会把同色系文字吃掉（真机上只剩空胶囊），这里只用文字。
            footerTag.text = "最忙"
            footerTag.insets = .zero
            footerTag.textColor = palette.secondary
            footerTag.backgroundColor = .clear
            switch ProbeUsageLevel(percent: spotlight.percent) {
            case .normal: footerDetail.textColor = palette.secondary
            case .warning: footerDetail.textColor = .systemOrange
            case .critical: footerDetail.textColor = .systemRed
            }
        }
        footer.accessibilityLabel = "\(footerTag.text ?? "")，\(spotlight.title)，\(spotlight.detail)"
    }
}

/// 横向轮播布局：卡片居中停靠，离中心越远越小、越淡；松手时一次只翻一张。
final class ProbeCarouselLayout: UICollectionViewLayout {
    var itemSize: CGSize = .zero
    /// 首尾卡片能停在正中的左右留白，等于 (容器宽 - 卡片宽) / 2。
    var sideInset: CGFloat = 0
    var spacing: CGFloat = 0
    var minScale: CGFloat = 1
    var minAlpha: CGFloat = 1
    private var count = 0

    var pageWidth: CGFloat { itemSize.width + spacing }

    override func prepare() {
        super.prepare()
        guard let collectionView, collectionView.numberOfSections > 0 else { count = 0; return }
        count = collectionView.numberOfItems(inSection: 0)
    }

    override var collectionViewContentSize: CGSize {
        guard count > 0 else { return .zero }
        return CGSize(width: sideInset * 2 + CGFloat(count) * itemSize.width + CGFloat(count - 1) * spacing, height: itemSize.height)
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        (0..<count).compactMap { item in
            frame(for: item).intersects(rect) ? layoutAttributesForItem(at: IndexPath(item: item, section: 0)) : nil
        }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard indexPath.item < count else { return nil }
        let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
        attributes.frame = frame(for: indexPath.item)
        let midX = collectionView?.bounds.midX ?? attributes.center.x
        let ratio = pageWidth > 0 ? min(abs(attributes.center.x - midX) / pageWidth, 1) : 0
        let scale = 1 - (1 - minScale) * ratio
        attributes.transform = CGAffineTransform(scaleX: scale, y: scale)
        attributes.alpha = 1 - (1 - minAlpha) * ratio
        return attributes
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool { true }

    override func targetContentOffset(forProposedContentOffset proposed: CGPoint, withScrollingVelocity velocity: CGPoint) -> CGPoint {
        guard let collectionView, pageWidth > 0, count > 0 else { return proposed }
        let current = collectionView.contentOffset.x / pageWidth
        var page: CGFloat
        if velocity.x > 0.2 {
            page = floor(current) + 1
        } else if velocity.x < -0.2 {
            page = ceil(current) - 1
        } else {
            page = (proposed.x / pageWidth).rounded()
        }
        page = min(max(page, 0), CGFloat(count - 1))
        return CGPoint(x: page * pageWidth, y: proposed.y)
    }

    func offset(forItem item: Int) -> CGFloat { CGFloat(item) * pageWidth }

    private func frame(for item: Int) -> CGRect {
        CGRect(x: sideInset + CGFloat(item) * pageWidth, y: 0, width: itemSize.width, height: itemSize.height)
    }
}

private final class ProbeHeroCell: UICollectionViewCell {
    static let reuseIdentifier = "ProbeHeroCell"
    let cardView = ProbeHeroCardView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardView)
        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// 顶部探针卡片：多个探针时是放大缩小的轮播；只有一个时占满整行、不能滑。
/// 只在翻页落定后通知切换，滑到一半不改下面的列表。
final class ProbeHeroCarouselView: UIView, UICollectionViewDataSource, UICollectionViewDelegate {
    var onSelect: ((UUID) -> Void)?
    var onOpenEntry: ((String) -> Void)?
    /// 长按当前卡片时的菜单。两侧露出的卡片不提供，避免滑的时候误删。
    var manageMenu: ((UUID) -> UIMenu?)?
    /// 与页面内容对齐的左右边距，由列表页传入。
    private var horizontalMargin: CGFloat = 16
    /// 列表页在算表头高度前先告诉轮播整行宽度，否则第一次算高时自身还没有宽度。
    private var containerWidth: CGFloat = 0
    private(set) var cardIDs: [UUID] = []
    var pagesAreEnabled: Bool { collectionView.isScrollEnabled }

    let layout = ProbeCarouselLayout()
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
    private var cards: [ProbeCard] = []
    private var selectedID: UUID?
    private var pendingScroll = false
    private var heightConstraint: NSLayoutConstraint!
    private let sizingCard = ProbeHeroCardView()

    /// 两侧卡片在页面边距之外再多露出的宽度，以及缩小后两张卡之间的可见间隔。
    private static let peek: CGFloat = 10
    private static let gap: CGFloat = 10
    private static let sideScale: CGFloat = 0.88
    private static let sideAlpha: CGFloat = 0.55

    override init(frame: CGRect) {
        super.init(frame: frame)
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.alwaysBounceVertical = false
        collectionView.decelerationRate = .fast
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(ProbeHeroCell.self, forCellWithReuseIdentifier: ProbeHeroCell.reuseIdentifier)
        collectionView.accessibilityIdentifier = "probe-hero-carousel"
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(collectionView)
        heightConstraint = collectionView.heightAnchor.constraint(equalToConstant: 164)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            heightConstraint,
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setContainerWidth(_ width: CGFloat, margin: CGFloat) {
        guard width != containerWidth || margin != horizontalMargin else { return }
        containerWidth = width
        horizontalMargin = margin
        updateMetrics()
        setNeedsLayout()
    }

    func configure(_ cards: [ProbeCard]) {
        let ids = cards.map(\.id)
        let idsChanged = ids != cardIDs
        self.cards = cards
        cardIDs = ids
        selectedID = cards.first(where: \.isSelected)?.id ?? cards.first?.id
        collectionView.isScrollEnabled = cards.count > 1
        updateMetrics()
        if idsChanged {
            collectionView.reloadData()
        } else {
            for case let cell as ProbeHeroCell in collectionView.visibleCells {
                guard let indexPath = collectionView.indexPath(for: cell) else { continue }
                configure(cell, at: indexPath.item)
            }
        }
        // 手指还在滑时不把偏移拉回去。
        if collectionView.isDragging || collectionView.isDecelerating { return }
        pendingScroll = true
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateMetrics()
        guard pendingScroll, bounds.width > 1, !collectionView.isDragging, !collectionView.isDecelerating else { return }
        pendingScroll = false
        collectionView.layoutIfNeeded()
        scrollToSelected(animated: false)
    }

    private func updateMetrics() {
        let width = bounds.width > 1 ? bounds.width : containerWidth
        guard width > 1 else { return }
        let paging = cards.count > 1
        let itemWidth = paging ? width - 2 * (horizontalMargin + Self.peek) : width - 2 * horizontalMargin
        let scale = paging ? Self.sideScale : 1
        if let card = cards.first {
            sizingCard.configure(card, interactive: false)
        }
        let height = ceil(sizingCard.systemLayoutSizeFitting(
            CGSize(width: itemWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel
        ).height)
        let size = CGSize(width: max(itemWidth, 1), height: max(height, 1))
        // 缩小后两侧各收进 (1 - scale) / 2，间距扣掉这部分，看起来才是 gap。
        let spacing = paging ? Self.gap - size.width * (1 - scale) / 2 : 0
        let inset = (width - size.width) / 2
        guard size != layout.itemSize || spacing != layout.spacing || inset != layout.sideInset || scale != layout.minScale else { return }
        layout.itemSize = size
        layout.spacing = spacing
        layout.sideInset = inset
        layout.minScale = scale
        layout.minAlpha = paging ? Self.sideAlpha : 1
        heightConstraint.constant = size.height
        layout.invalidateLayout()
        pendingScroll = true
    }

    private func scrollToSelected(animated: Bool) {
        guard let selectedID, let index = cardIDs.firstIndex(of: selectedID) else { return }
        let target = layout.offset(forItem: index)
        if abs(collectionView.contentOffset.x - target) < 0.5 { return }
        collectionView.setContentOffset(CGPoint(x: target, y: 0), animated: animated)
    }

    private func commitPage() {
        guard layout.pageWidth > 0, !cardIDs.isEmpty else { return }
        let index = min(max(Int((collectionView.contentOffset.x / layout.pageWidth).rounded()), 0), cardIDs.count - 1)
        let id = cardIDs[index]
        guard id != selectedID else { return }
        selectedID = id
        onSelect?(id)
    }

    private func configure(_ cell: ProbeHeroCell, at index: Int) {
        let card = cards[index]
        let paging = cards.count > 1
        cell.cardView.accessibilityIdentifier = "probe-hero-\(card.id.uuidString)"
        cell.cardView.configure(card, interactive: !paging || card.isSelected)
        cell.cardView.onSpotlight = { [weak self] id in self?.onOpenEntry?(id) }
    }

    // MARK: - UICollectionView

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        cards.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ProbeHeroCell.reuseIdentifier, for: indexPath) as! ProbeHeroCell
        configure(cell, at: indexPath.item)
        return cell
    }

    /// 只有当前这张卡能长按出菜单。
    func contextMenu(at index: Int) -> UIMenu? {
        guard cards.indices.contains(index), cards[index].isSelected else { return nil }
        return manageMenu?(cards[index].id)
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard let menu = contextMenu(at: indexPath.item) else { return nil }
        return UIContextMenuConfiguration(actionProvider: { _ in menu })
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        // 点两侧的卡片：滑到它，落定后再切换。
        let target = layout.offset(forItem: indexPath.item)
        guard abs(collectionView.contentOffset.x - target) > 0.5 else { return }
        collectionView.setContentOffset(CGPoint(x: target, y: 0), animated: true)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { commitPage() }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { commitPage() }
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { commitPage() }
}
