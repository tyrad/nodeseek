//
//  LayoutChooserViewController.swift
//  nodeseek
//

import UIKit

/// 选择阅读模式或多 Tab 模式。升级后弹出一次，也从设置进入。
final class LayoutChooserViewController: UIViewController {
    enum Mode {
        /// 升级后弹出：选好后点“开始使用”生效。
        case upgradePrompt
        /// 设置里进入：点选即生效。
        case settings
    }

    private let mode: Mode
    private let settings: AppNavigationLayoutSettings
    private var selectedLayout: AppNavigationLayout
    private var cards: [AppNavigationLayout: LayoutOptionCard] = [:]
    private let footnoteLabel = UILabel()
    private let tabItemsRow = TabItemsSummaryRow()

    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()

    private let startButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.baseBackgroundColor = .label
        configuration.baseForegroundColor = .systemBackground
        configuration.cornerStyle = .capsule
        configuration.title = "开始使用"
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 17, weight: .semibold)
            return outgoing
        }
        let button = UIButton(configuration: configuration)
        button.accessibilityIdentifier = "layout-chooser-start-button"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    init(mode: Mode, settings: AppNavigationLayoutSettings? = nil) {
        self.mode = mode
        self.settings = settings ?? .shared
        self.selectedLayout = self.settings.layout
        super.init(nibName: nil, bundle: nil)
        title = "界面布局"
        if mode == .upgradePrompt {
            modalPresentationStyle = .fullScreen
            // 必须做出选择，不允许下滑关掉
            isModalInPresentation = true
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        view.accessibilityIdentifier = "layout-chooser"
        setupUI()
        applySelection()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if mode == .upgradePrompt {
            navigationController?.setNavigationBarHidden(true, animated: animated)
        }
        tabItemsRow.setSummary(settings.tabItems.map(\.title).joined(separator: "、"))
    }

    private func setupUI() {
        let titleLabel = UILabel()
        titleLabel.text = "选择浏览方式"
        titleLabel.font = .systemFont(ofSize: 30, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center

        let subtitleLabel = UILabel()
        subtitleLabel.text = "两种布局功能完全一样，\n以后可在设置里随时切换"
        subtitleLabel.font = .systemFont(ofSize: 15)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0

        let cardStack = UIStackView()
        cardStack.axis = .horizontal
        cardStack.spacing = 12
        cardStack.distribution = .fillEqually
        cardStack.alignment = .top
        for layout in AppNavigationLayout.allCases {
            let card = LayoutOptionCard(layout: layout)
            card.addTarget(self, action: #selector(cardTapped(_:)), for: .touchUpInside)
            cards[layout] = card
            cardStack.addArrangedSubview(card)
        }

        let contentStack = UIStackView()
        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        switch mode {
        case .upgradePrompt:
            contentStack.addArrangedSubview(titleLabel)
            contentStack.setCustomSpacing(8, after: titleLabel)
            contentStack.addArrangedSubview(subtitleLabel)
            contentStack.setCustomSpacing(24, after: subtitleLabel)
        case .settings:
            subtitleLabel.text = "点选后立即切换，登录状态不受影响"
            subtitleLabel.font = .preferredFont(forTextStyle: .footnote)
            contentStack.addArrangedSubview(subtitleLabel)
            contentStack.setCustomSpacing(16, after: subtitleLabel)
        }
        contentStack.addArrangedSubview(cardStack)
        if mode == .settings {
            tabItemsRow.addTarget(self, action: #selector(tabItemsRowTapped), for: .touchUpInside)
            let rowFootnote = UILabel()
            rowFootnote.text = "底部栏只在多 Tab 模式下生效；切回阅读模式会保留你的设置。"
            rowFootnote.font = .preferredFont(forTextStyle: .footnote)
            rowFootnote.textColor = .secondaryLabel
            rowFootnote.numberOfLines = 0
            contentStack.setCustomSpacing(24, after: cardStack)
            contentStack.addArrangedSubview(tabItemsRow)
            contentStack.setCustomSpacing(8, after: tabItemsRow)
            contentStack.addArrangedSubview(rowFootnote)
        }

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        let topInset: CGFloat = mode == .upgradePrompt ? 28 : 12
        var constraints = [
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),

            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: topInset),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -20)
        ]

        switch mode {
        case .upgradePrompt:
            startButton.addTarget(self, action: #selector(startTapped), for: .touchUpInside)
            footnoteLabel.text = "设置 › 阅读 › 界面布局 可再修改"
            footnoteLabel.font = .preferredFont(forTextStyle: .footnote)
            footnoteLabel.textColor = .secondaryLabel
            footnoteLabel.textAlignment = .center
            footnoteLabel.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(startButton)
            view.addSubview(footnoteLabel)
            constraints += [
                scrollView.bottomAnchor.constraint(equalTo: startButton.topAnchor, constant: -12),
                startButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
                startButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
                startButton.heightAnchor.constraint(equalToConstant: 52),
                footnoteLabel.topAnchor.constraint(equalTo: startButton.bottomAnchor, constant: 12),
                footnoteLabel.leadingAnchor.constraint(equalTo: startButton.leadingAnchor),
                footnoteLabel.trailingAnchor.constraint(equalTo: startButton.trailingAnchor),
                footnoteLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8)
            ]
        case .settings:
            constraints.append(scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor))
        }
        NSLayoutConstraint.activate(constraints)
    }

    private func applySelection() {
        for (layout, card) in cards {
            card.isSelected = layout == selectedLayout
        }
        guard mode == .upgradePrompt else { return }
        // 多 Tab 模式多一步自定义底部栏
        let isTabs = selectedLayout == .tabs
        startButton.configuration?.title = isTabs ? "下一步" : "开始使用"
        footnoteLabel.text = isTabs ? "下一步可自定义底部栏，也可直接跳过" : "设置 › 阅读 › 界面布局 可再修改"
    }

    @objc private func cardTapped(_ sender: LayoutOptionCard) {
        guard sender.layout != selectedLayout else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        selectedLayout = sender.layout
        applySelection()
        if mode == .settings {
            settings.markChoiceConfirmed()
            // 根界面会被替换，当前页面随之关闭
            settings.setLayout(selectedLayout)
        }
    }

    @objc private func startTapped() {
        guard selectedLayout == .tabs, let navigationController else {
            finishChoice(tabItems: nil)
            return
        }
        let customizeViewController = TabBarCustomizeViewController(mode: .onboarding, settings: settings)
        customizeViewController.onFinish = { [weak self] items in
            self?.finishChoice(tabItems: items)
        }
        navigationController.pushViewController(customizeViewController, animated: true)
    }

    @objc private func tabItemsRowTapped() {
        navigationController?.pushViewController(TabBarCustomizeViewController(mode: .settings, settings: settings), animated: true)
    }

    private func finishChoice(tabItems: [MainTabItem]?) {
        if let tabItems {
            settings.setTabItems(tabItems)
        }
        settings.markChoiceConfirmed()
        AppLog.info(.postList, "升级布局选择: \(selectedLayout.rawValue), 底部栏: \(settings.tabItems.map(\.rawValue))")
        if selectedLayout == settings.layout {
            dismiss(animated: true)
        } else {
            // AppRouter 收到变化后会先关闭本页再替换根界面
            settings.setLayout(selectedLayout)
        }
    }
}

extension LayoutChooserViewController {
    /// 开屏结束后按需弹出；推送冷启动不走这里。返回是否已弹出。
    @discardableResult
    static func presentIfNeeded(
        from presenter: UIViewController,
        settings: AppNavigationLayoutSettings? = nil,
        currentVersion: String? = nil
    ) -> Bool {
        let settings = settings ?? .shared
        let version = currentVersion
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? ""
        guard presenter.presentedViewController == nil,
              settings.needsChoicePrompt(currentVersion: version) else { return false }
        // 放进导航栈，多 Tab 模式的第 2 步需要 push
        let navigationController = UINavigationController(
            rootViewController: LayoutChooserViewController(mode: .upgradePrompt, settings: settings)
        )
        navigationController.modalPresentationStyle = .fullScreen
        navigationController.isModalInPresentation = true
        presenter.present(navigationController, animated: true)
        return true
    }
}

/// 一张布局卡片：缩略图 + 名称 + 说明 + 单选圈，选中时文字色描边。
final class LayoutOptionCard: UIControl {
    let layout: AppNavigationLayout

    private let previewImageView = UIImageView()
    private let radioView = UIImageView()

    init(layout: AppNavigationLayout) {
        self.layout = layout
        super.init(frame: .zero)
        accessibilityIdentifier = "layout-option-\(layout.rawValue)"
        isAccessibilityElement = true
        accessibilityLabel = "\(layout.title)，\(layout.subtitle.replacingOccurrences(of: "\n", with: ""))"
        accessibilityTraits = .button

        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        layer.borderWidth = 2

        previewImageView.image = UIImage(named: layout == .reading ? "LayoutPreviewReading" : "LayoutPreviewTabs")
        previewImageView.contentMode = .scaleAspectFill
        previewImageView.clipsToBounds = true
        previewImageView.layer.cornerRadius = 14
        previewImageView.layer.cornerCurve = .continuous
        previewImageView.layer.borderWidth = 1 / UIScreen.main.scale
        previewImageView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = layout.title
        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center

        let subtitleLabel = UILabel()
        subtitleLabel.text = layout.subtitle
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0

        radioView.contentMode = .center
        radioView.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [previewImageView, titleLabel, subtitleLabel, radioView])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 6
        stack.setCustomSpacing(14, after: previewImageView)
        stack.setCustomSpacing(12, after: subtitleLabel)
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let imageAspect = previewImageView.image.map { $0.size.height / max($0.size.width, 1) } ?? 2.16
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            previewImageView.heightAnchor.constraint(equalTo: previewImageView.widthAnchor, multiplier: imageAspect),
            radioView.heightAnchor.constraint(equalToConstant: 26)
        ])
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isSelected: Bool {
        didSet { updateAppearance() }
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.8 : 1 }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateAppearance()
    }

    private func updateAppearance() {
        // layer 颜色不会自动跟随深浅色，需要按当前外观解析
        layer.borderColor = (isSelected ? UIColor.label : UIColor.clear).resolvedColor(with: traitCollection).cgColor
        previewImageView.layer.borderColor = UIColor.separator.resolvedColor(with: traitCollection).cgColor
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 24, weight: .regular)
        radioView.image = UIImage(
            systemName: isSelected ? "checkmark.circle.fill" : "circle",
            withConfiguration: symbolConfiguration
        )
        radioView.tintColor = isSelected ? .label : .tertiaryLabel
        accessibilityTraits = isSelected ? [.button, .selected] : .button
    }
}

/// 设置里的“底部栏”行：标题 + 当前组合 + 箭头。
final class TabItemsSummaryRow: UIControl {
    private let valueLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "layout-tab-items-row"
        isAccessibilityElement = true
        accessibilityTraits = .button
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous

        let titleLabel = UILabel()
        titleLabel.text = "底部栏"
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.textColor = .label
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        valueLabel.font = .preferredFont(forTextStyle: .subheadline)
        valueLabel.textColor = .secondaryLabel
        valueLabel.textAlignment = .right
        valueLabel.lineBreakMode = .byTruncatingTail

        let chevron = UIImageView(image: UIImage(
            systemName: "chevron.right",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        ))
        chevron.tintColor = .tertiaryLabel
        chevron.setContentHuggingPriority(.required, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [titleLabel, valueLabel, chevron])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 48)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet { backgroundColor = isHighlighted ? .systemFill : .secondarySystemGroupedBackground }
    }

    func setSummary(_ summary: String) {
        valueLabel.text = summary
        accessibilityLabel = "底部栏，\(summary)"
    }
}
