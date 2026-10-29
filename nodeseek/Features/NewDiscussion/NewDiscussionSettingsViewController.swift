//
//  NewDiscussionSettingsViewController.swift
//  nodeseek
//

import UIKit

/// “发布到”半屏面板：同一处选板块和阅读限制，高度贴合内容。
final class NewDiscussionSettingsViewController: UIViewController {
    var onSelectCategory: ((DiscussionCategory) -> Void)?
    var onSelectRank: ((DiscussionReadRank) -> Void)?
    var onRetryUserLevel: (() -> Void)?

    private var category: DiscussionCategory?
    private var rank: DiscussionReadRank
    private var userLevel: NewDiscussionUserLevelState
    private var rankOptions: [DiscussionReadRank]
    /// 编辑已发帖子时板块不能改，只展示当前板块。
    private let isCategoryLocked: Bool

    private let contentStack = UIStackView()
    private let categoryFlow = PillFlowView()
    private let feeLabel = UILabel()
    private let rankFlow = PillFlowView()
    private let rankHintLabel = UILabel()
    private let rankStatusRow = UIStackView()
    private let rankStatusLabel = UILabel()
    private let rankRetryButton = UIButton(type: .system)
    private var categoryPills: [DiscussionCategory: SettingsPill] = [:]
    private var rankPills: [DiscussionReadRank: SettingsPill] = [:]
    private var lastMeasuredHeight: CGFloat = 0

    init(
        category: DiscussionCategory?,
        rank: DiscussionReadRank,
        userLevel: NewDiscussionUserLevelState,
        rankOptions: [DiscussionReadRank],
        isCategoryLocked: Bool = false
    ) {
        self.category = category
        self.rank = rank
        self.userLevel = userLevel
        self.rankOptions = rankOptions
        self.isCategoryLocked = isCategoryLocked
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupUI()
        updateCategorySelection()
        rebuildRankSection()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
        // 选中文字用的是固定色，深浅切换后要重新取。
        (Array(categoryPills.values) + Array(rankPills.values)).forEach { $0.applyColors() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updatePreferredHeightIfNeeded()
    }

    /// 面板打开期间等级读取完成时刷新。
    func update(userLevel: NewDiscussionUserLevelState, rankOptions: [DiscussionReadRank]) {
        self.userLevel = userLevel
        self.rankOptions = rankOptions
        guard isViewLoaded else { return }
        rebuildRankSection()
    }

    /// 弹出前配置高度：iOS 16 起按内容自适应，更早系统用半屏。
    func configureSheet() {
        guard let sheet = sheetPresentationController else { return }
        sheet.prefersGrabberVisible = true
        sheet.preferredCornerRadius = 24
        if #available(iOS 16.0, *) {
            sheet.detents = [.custom(identifier: .init("content")) { [weak self] context in
                guard let self, lastMeasuredHeight > 0 else { return context.maximumDetentValue * 0.6 }
                return min(lastMeasuredHeight, context.maximumDetentValue)
            }]
        } else {
            sheet.detents = [.medium(), .large()]
        }
    }

    // MARK: - 布局

    private func setupUI() {
        let titleLabel = UILabel()
        titleLabel.text = isCategoryLocked ? "帖子设置" : "发布到"
        titleLabel.font = .preferredFont(forTextStyle: .title3).withSymbolicTraits(.traitBold)
        titleLabel.adjustsFontForContentSizeCategory = true

        var doneConfiguration = UIButton.Configuration.plain()
        doneConfiguration.title = "完成"
        doneConfiguration.baseForegroundColor = .label
        doneConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var updated = attributes
            updated.font = .preferredFont(forTextStyle: .body).withSymbolicTraits(.traitBold)
            return updated
        }
        let doneButton = UIButton(configuration: doneConfiguration)
        doneButton.setContentHuggingPriority(.required, for: .horizontal)
        doneButton.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)

        let header = UIStackView(arrangedSubviews: [titleLabel, doneButton])
        header.alignment = .center

        for category in DiscussionCategory.regularCases + [.inside] {
            let pill = makePill(title: category.title, symbolName: category.symbolName)
            pill.addAction(UIAction { [weak self] _ in self?.select(category) }, for: .touchUpInside)
            categoryPills[category] = pill
        }
        feeLabel.font = .preferredFont(forTextStyle: .footnote)
        feeLabel.adjustsFontForContentSizeCategory = true
        feeLabel.textColor = .systemOrange
        feeLabel.numberOfLines = 0
        if isCategoryLocked {
            // 只留当前板块，选中态展示，不响应点击。
            let current = category.flatMap { categoryPills[$0] }
            current?.isUserInteractionEnabled = false
            categoryFlow.setPills([current].compactMap { $0 })
            feeLabel.text = "发布后不能修改板块"
        } else {
            categoryFlow.setPills(DiscussionCategory.regularCases.compactMap { categoryPills[$0] } + [categoryPills[.inside]].compactMap { $0 })
            feeLabel.text = "内版用于敏感话题，发帖收取 \(DiscussionCategory.inside.chickenLegFee ?? 0) 鸡腿"
        }

        rankHintLabel.font = .preferredFont(forTextStyle: .footnote)
        rankHintLabel.adjustsFontForContentSizeCategory = true
        rankHintLabel.textColor = MarkdownEditorStyler.secondaryTextColor
        rankHintLabel.numberOfLines = 0

        setupRankStatusRow()

        contentStack.axis = .vertical
        contentStack.spacing = 10
        [
            header,
            sectionLabel("板块"),
            categoryFlow,
            feeLabel,
            sectionLabel("谁可以看"),
            rankFlow,
            rankStatusRow,
            rankHintLabel
        ].forEach(contentStack.addArrangedSubview)
        contentStack.setCustomSpacing(18, after: header)
        contentStack.setCustomSpacing(22, after: feeLabel)
        contentStack.setCustomSpacing(22, after: categoryFlow)

        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 22),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16)
        ])
    }

    private func setupRankStatusRow() {
        rankStatusLabel.font = .preferredFont(forTextStyle: .subheadline)
        rankStatusLabel.adjustsFontForContentSizeCategory = true
        rankStatusLabel.textColor = .secondaryLabel
        rankStatusLabel.numberOfLines = 0

        var retryConfiguration = UIButton.Configuration.plain()
        retryConfiguration.title = "重试"
        retryConfiguration.baseForegroundColor = .label
        rankRetryButton.configuration = retryConfiguration
        rankRetryButton.setContentHuggingPriority(.required, for: .horizontal)
        rankRetryButton.addAction(UIAction { [weak self] _ in self?.onRetryUserLevel?() }, for: .touchUpInside)

        rankStatusRow.addArrangedSubview(rankStatusLabel)
        rankStatusRow.addArrangedSubview(rankRetryButton)
        rankStatusRow.alignment = .center
    }

    private func sectionLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .subheadline).withSymbolicTraits(.traitBold)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        return label
    }

    private func makePill(title: String, symbolName: String?) -> SettingsPill {
        SettingsPill(title: title, symbolName: symbolName)
    }

    private static func applySelection(_ pills: [(SettingsPill, Bool)]) {
        for (pill, isSelected) in pills {
            pill.isSelected = isSelected
        }
    }

    // MARK: - 板块

    private func select(_ category: DiscussionCategory) {
        self.category = category
        updateCategorySelection()
        UISelectionFeedbackGenerator().selectionChanged()
        onSelectCategory?(category)
    }

    private func updateCategorySelection() {
        Self.applySelection(categoryPills.map { ($0.value, $0.key == category) })
        feeLabel.textColor = category == .inside && !isCategoryLocked ? .systemOrange : MarkdownEditorStyler.secondaryTextColor
    }

    // MARK: - 阅读限制

    private func rebuildRankSection() {
        rankPills.removeAll()
        switch userLevel {
        case .loaded where !rankOptions.isEmpty:
            let pills = rankOptions.map { option -> SettingsPill in
                let pill = makePill(title: option.title, symbolName: option == .onlyMe ? "lock" : nil)
                pill.addAction(UIAction { [weak self] _ in self?.select(option) }, for: .touchUpInside)
                rankPills[option] = pill
                return pill
            }
            rankFlow.setPills(pills)
            rankFlow.isHidden = false
            rankStatusRow.isHidden = true
        case .loading, .loaded:
            rankFlow.isHidden = true
            rankStatusRow.isHidden = false
            rankStatusLabel.text = "正在读取你的等级…"
            rankRetryButton.isHidden = true
        case .failed:
            rankFlow.isHidden = true
            rankStatusRow.isHidden = false
            rankStatusLabel.text = "等级读取失败，暂时保持「\(rank.title)」"
            rankRetryButton.isHidden = false
        }
        updateRankSelection()
    }

    private func select(_ option: DiscussionReadRank) {
        rank = option
        updateRankSelection()
        UISelectionFeedbackGenerator().selectionChanged()
        onSelectRank?(option)
    }

    private func updateRankSelection() {
        Self.applySelection(rankPills.map { ($0.value, $0.key == rank) })
        let hint: String
        switch rank {
        case .everyone: hint = "所有人都能看到这篇帖子"
        case .onlyMe: hint = "只有你自己能看到"
        default: hint = "\(rank.title) 及以上等级的用户才能看到"
        }
        // 站点只允许选到自己当前的等级，说明一下为什么没有更高的选项。
        guard case .loaded(let level) = userLevel, !rankPills.isEmpty else {
            rankHintLabel.text = hint
            return
        }
        let font = UIFont.preferredFont(forTextStyle: .footnote)
        let text = NSMutableAttributedString(string: hint, attributes: [.font: font, .foregroundColor: MarkdownEditorStyler.secondaryTextColor])
        text.append(NSAttributedString(
            string: "\n最高只能选到你当前的等级 Lv\(level)",
            attributes: [.font: font, .foregroundColor: MarkdownEditorStyler.secondaryTextColor]
        ))
        rankHintLabel.attributedText = text
    }

    // MARK: - 高度

    private func updatePreferredHeightIfNeeded() {
        // 自定义高度不含底部安全区，系统会自己补上。
        let height = ceil(contentStack.frame.maxY + 16)
        guard contentStack.frame.height > 0, abs(height - lastMeasuredHeight) > 1 else { return }
        lastMeasuredHeight = height
        if #available(iOS 16.0, *) {
            sheetPresentationController?.animateChanges {
                sheetPresentationController?.invalidateDetents()
            }
        }
    }
}

/// 自动换行的胶囊排布，高度随宽度变化。
private final class PillFlowView: UIView {
    private let spacing: CGFloat = 8
    private var pills: [UIView] = []
    private var measuredHeight: CGFloat = 0

    func setPills(_ newPills: [UIView]) {
        pills.forEach { $0.removeFromSuperview() }
        pills = newPills
        pills.forEach(addSubview)
        setNeedsLayout()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: measuredHeight)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let height = arrange(width: bounds.width)
        if abs(height - measuredHeight) > 0.5 {
            measuredHeight = height
            invalidateIntrinsicContentSize()
        }
    }

    private func arrange(width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for pill in pills {
            let size = pill.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            let pillWidth = min(size.width, width)
            if x > 0 && x + pillWidth > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            pill.frame = CGRect(x: x, y: y, width: pillWidth, height: size.height)
            x += pillWidth + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return y + rowHeight
    }
}

extension DiscussionCategory {
    var symbolName: String {
        switch self {
        case .daily: return "cup.and.saucer"
        case .tech: return "terminal"
        case .info: return "dot.radiowaves.left.and.right"
        case .review: return "gauge"
        case .trade: return "arrow.left.arrow.right"
        case .carpool: return "person.2"
        case .promotion: return "megaphone"
        case .life: return "leaf"
        case .dev: return "curlybraces"
        case .photoShare: return "photo"
        case .expose: return "exclamationmark.triangle"
        case .inside: return "lock"
        case .sandbox: return "shippingbox"
        }
    }
}

private extension UIFont {
    func withSymbolicTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }
}

/// 发布设置里的选项胶囊。没用 UIButton：它切换选中时会对文字做交叉淡入，
/// 新文字从左上角滑入、黑底上文字渐变出现。这里直接改颜色，点下即切换、没有任何动画。
private final class SettingsPill: UIControl {
    /// 白天的玻璃半屏上 secondarySystemFill 偏重，换成更浅一档；夜间保持原来的层次。
    private static let fill = UIColor { traits in
        traits.userInterfaceStyle == .dark ? .secondarySystemFill : .tertiarySystemFill
    }

    private let titleLabel = UILabel()
    private let iconView = UIImageView()

    override var isSelected: Bool {
        didSet {
            guard isSelected != oldValue else { return }
            applyColors()
        }
    }

    init(title: String, symbolName: String?) {
        super.init(frame: .zero)
        titleLabel.text = title
        // 选中前后字重保持一致，胶囊宽度不变。
        titleLabel.font = .preferredFont(forTextStyle: .subheadline).withSymbolicTraits(.traitBold)
        titleLabel.adjustsFontForContentSizeCategory = true
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .footnote, scale: .medium)
        iconView.image = symbolName.flatMap { UIImage(systemName: $0) }
        iconView.isHidden = symbolName == nil
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [iconView, titleLabel])
        stack.spacing = 5
        stack.alignment = .center
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14)
        ])

        layer.cornerCurve = .continuous
        isAccessibilityElement = true
        accessibilityLabel = title
        applyColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var accessibilityTraits: UIAccessibilityTraits {
        get { isSelected ? [.button, .selected] : .button }
        set {}
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }

    /// 选中用 .label 反色：深浅模式下自动是黑底白字 / 白底黑字。
    func applyColors() {
        // iOS 26 的玻璃半屏会对系统动态色做混合，选中文字用 Assets 里的纯黑白反色才清晰。
        let foreground: UIColor = isSelected ? (UIColor(named: "InvertedLabel") ?? .systemBackground) : .label
        UIView.performWithoutAnimation {
            backgroundColor = isSelected ? .label : Self.fill
            titleLabel.textColor = foreground
            iconView.tintColor = isSelected ? foreground : .secondaryLabel
        }
    }
}
