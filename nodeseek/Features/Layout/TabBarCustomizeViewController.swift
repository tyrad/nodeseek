//
//  TabBarCustomizeViewController.swift
//  nodeseek
//

import UIKit

/// 自定义多 Tab 模式的底部栏：首页、我的固定，中间入口可增减、拖动排序，最多 5 项。
final class TabBarCustomizeViewController: UIViewController {
    enum Mode {
        /// 布局选择页的第 2 步：点“开始使用”或“跳过”后生效。
        case onboarding
        /// 设置里进入：每次改动立即生效。
        case settings
    }

    private enum Section: Int, CaseIterable {
        case shown
        case available
    }

    /// 引导模式下完成时回调最终的底部栏。
    var onFinish: (([MainTabItem]) -> Void)?

    private let mode: Mode
    private let settings: AppNavigationLayoutSettings
    private(set) var shownItems: [MainTabItem]

    private var availableItems: [MainTabItem] {
        MainTabItem.allCases.filter { shownItems.contains($0) == false }
    }

    private var isFull: Bool {
        shownItems.count >= MainTabItem.maximumCount
    }

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let previewStack = UIStackView()
    private let toastLabel = PaddingLabel()

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
        button.accessibilityIdentifier = "tab-customize-start-button"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    init(mode: Mode, settings: AppNavigationLayoutSettings? = nil) {
        self.mode = mode
        self.settings = settings ?? .shared
        self.shownItems = self.settings.tabItems
        super.init(nibName: nil, bundle: nil)
        title = "自定义底部栏"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.systemGroupedBackground
        view.accessibilityIdentifier = "tab-customize"
        navigationItem.largeTitleDisplayMode = .never
        setupTableView()
        setupChrome()
        setupToast()
        updatePreview()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 引导流程里上一页隐藏了导航栏，这里需要返回和“跳过”
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 表头高度依赖宽度，布局后再按内容重算
        guard let header = tableView.tableHeaderView else { return }
        let size = header.systemLayoutSizeFitting(
            CGSize(width: tableView.bounds.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        if abs(header.frame.height - size.height) > 0.5 {
            header.frame.size.height = size.height
            tableView.tableHeaderView = header
        }
    }

    // MARK: - Setup

    private func setupTableView() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.isEditing = true
        tableView.allowsSelectionDuringEditing = false
        tableView.register(TabItemCell.self, forCellReuseIdentifier: TabItemCell.reuseIdentifier)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.tableHeaderView = makeHeaderView()
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor)
        ])
    }

    private func setupChrome() {
        switch mode {
        case .onboarding:
            let skipItem = UIBarButtonItem(title: "跳过", style: .plain, target: self, action: #selector(skipTapped))
            skipItem.accessibilityIdentifier = "tab-customize-skip-button"
            navigationItem.rightBarButtonItem = skipItem
            startButton.addTarget(self, action: #selector(startTapped), for: .touchUpInside)
            view.addSubview(startButton)
            NSLayoutConstraint.activate([
                tableView.bottomAnchor.constraint(equalTo: startButton.topAnchor, constant: -12),
                startButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
                startButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
                startButton.heightAnchor.constraint(equalToConstant: 52),
                startButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
            ])
        case .settings:
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        }
    }

    private func makeHeaderView() -> UIView {
        let leadLabel = UILabel()
        leadLabel.numberOfLines = 0
        leadLabel.font = .preferredFont(forTextStyle: .subheadline)
        leadLabel.textColor = .secondaryLabel
        leadLabel.adjustsFontForContentSizeCategory = true
        let lead = "选出最常用的入口，放到底部一点即达。"
        leadLabel.text = mode == .onboarding ? "第 2 步，共 2 步\n\(lead)" : lead

        // 实时预览：用普通视图画一条底栏，独立摆放的系统底栏会带上安全区留白
        previewStack.axis = .horizontal
        previewStack.distribution = .fillEqually
        previewStack.spacing = 2
        previewStack.isUserInteractionEnabled = false
        previewStack.accessibilityIdentifier = "tab-customize-preview"
        previewStack.translatesAutoresizingMaskIntoConstraints = false

        let capsule = UIView()
        capsule.backgroundColor = .tertiarySystemFill
        capsule.layer.cornerRadius = 30
        capsule.layer.cornerCurve = .continuous
        capsule.translatesAutoresizingMaskIntoConstraints = false
        capsule.addSubview(previewStack)

        let previewContainer = UIView()
        previewContainer.backgroundColor = .secondarySystemGroupedBackground
        previewContainer.layer.cornerRadius = 18
        previewContainer.layer.cornerCurve = .continuous
        previewContainer.addSubview(capsule)
        NSLayoutConstraint.activate([
            capsule.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor, constant: 14),
            capsule.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor, constant: -14),
            capsule.topAnchor.constraint(equalTo: previewContainer.topAnchor, constant: 16),
            capsule.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor, constant: -16),
            capsule.heightAnchor.constraint(equalToConstant: 60),
            previewStack.leadingAnchor.constraint(equalTo: capsule.leadingAnchor, constant: 4),
            previewStack.trailingAnchor.constraint(equalTo: capsule.trailingAnchor, constant: -4),
            previewStack.topAnchor.constraint(equalTo: capsule.topAnchor, constant: 4),
            previewStack.bottomAnchor.constraint(equalTo: capsule.bottomAnchor, constant: -4)
        ])

        let stack = UIStackView(arrangedSubviews: [leadLabel, previewContainer])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        let header = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 140))
        header.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: header.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: header.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: header.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -4)
        ])
        header.preservesSuperviewLayoutMargins = true
        return header
    }

    private func setupToast() {
        toastLabel.text = "底部最多 \(MainTabItem.maximumCount) 项"
        toastLabel.font = .systemFont(ofSize: 14, weight: .medium)
        toastLabel.textColor = .systemBackground
        toastLabel.backgroundColor = .label
        toastLabel.layer.cornerRadius = 17
        toastLabel.layer.cornerCurve = .continuous
        toastLabel.clipsToBounds = true
        toastLabel.alpha = 0
        toastLabel.accessibilityIdentifier = "tab-customize-limit-toast"
        toastLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toastLabel)
        let anchor = mode == .onboarding ? startButton.topAnchor : view.safeAreaLayoutGuide.bottomAnchor
        NSLayoutConstraint.activate([
            toastLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toastLabel.bottomAnchor.constraint(equalTo: anchor, constant: -16),
            toastLabel.heightAnchor.constraint(equalToConstant: 34)
        ])
    }

    // MARK: - Editing

    private func addItem(_ item: MainTabItem) {
        guard isFull == false else {
            showLimitToast()
            return
        }
        // 新加的放在“我的”前面
        shownItems.insert(item, at: shownItems.count - 1)
        itemsDidChange()
    }

    private func removeItem(_ item: MainTabItem) {
        guard item.isFixed == false else { return }
        shownItems.removeAll { $0 == item }
        itemsDidChange()
    }

    private func itemsDidChange() {
        shownItems = MainTabItem.normalized(shownItems)
        UISelectionFeedbackGenerator().selectionChanged()
        tableView.reloadData()
        updatePreview()
        if mode == .settings {
            settings.setTabItems(shownItems)
        }
    }

    private func updatePreview() {
        previewStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, item) in shownItems.enumerated() {
            previewStack.addArrangedSubview(Self.makePreviewItem(item, isSelected: index == 0))
        }
        previewStack.accessibilityLabel = shownItems.map(\.title).joined(separator: "、")
    }

    /// 预览里的一项：图标 + 文字，第一项按选中样式显示。
    private static func makePreviewItem(_ item: MainTabItem, isSelected: Bool) -> UIView {
        let symbolName = isSelected ? "\(item.symbolName).fill" : item.symbolName
        let imageView = UIImageView(image: UIImage(systemName: symbolName) ?? UIImage(systemName: item.symbolName))
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        imageView.contentMode = .center
        imageView.tintColor = isSelected ? .label : .secondaryLabel

        let label = UILabel()
        label.text = item.title
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = isSelected ? .label : .secondaryLabel
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8

        let stack = UIStackView(arrangedSubviews: [imageView, label])
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .fill
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 4, leading: 2, bottom: 4, trailing: 2)
        if isSelected {
            stack.backgroundColor = .tertiarySystemFill
            stack.layer.cornerRadius = 26
            stack.layer.cornerCurve = .continuous
        }
        return stack
    }

    private func showLimitToast() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        toastLabel.layer.removeAllAnimations()
        UIView.animate(withDuration: 0.2, animations: {
            self.toastLabel.alpha = 1
        }, completion: { _ in
            UIView.animate(withDuration: 0.25, delay: 1.4, options: [.allowUserInteraction], animations: {
                self.toastLabel.alpha = 0
            })
        })
    }

    @objc private func startTapped() {
        onFinish?(shownItems)
    }

    @objc private func skipTapped() {
        onFinish?(MainTabItem.defaultItems)
    }
}

// MARK: - UITableViewDataSource & UITableViewDelegate

extension TabBarCustomizeViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        Section(rawValue: section) == .shown ? shownItems.count : availableItems.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .shown:
            return "已显示 \(shownItems.count)/\(MainTabItem.maximumCount)"
        case .available:
            return "可添加"
        case .none:
            return nil
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .shown:
            return "首页和我的固定显示；拖动右侧把手调整顺序。"
        case .available:
            return isFull ? "底部最多放 \(MainTabItem.maximumCount) 项，先移除一项再添加。" : "加到底部的入口在“我的”页里仍保留。"
        case .none:
            return nil
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: TabItemCell.reuseIdentifier, for: indexPath) as! TabItemCell
        switch Section(rawValue: indexPath.section) {
        case .shown:
            let item = shownItems[indexPath.row]
            if item.isFixed {
                cell.configure(item: item, action: .fixed)
            } else {
                cell.configure(item: item, action: .remove) { [weak self] in self?.removeItem(item) }
            }
        case .available, .none:
            let item = availableItems[indexPath.row]
            cell.configure(item: item, action: isFull ? .addDisabled : .add) { [weak self] in self?.addItem(item) }
        }

        return cell
    }

    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        .none
    }

    func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
        false
    }

    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        Section(rawValue: indexPath.section) == .shown && shownItems[indexPath.row].isFixed == false
    }

    func tableView(
        _ tableView: UITableView,
        targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
        toProposedIndexPath proposedDestinationIndexPath: IndexPath
    ) -> IndexPath {
        // 只能在首页和我的之间移动
        let lastMovableRow = shownItems.count - 2
        guard proposedDestinationIndexPath.section == Section.shown.rawValue else {
            return IndexPath(row: lastMovableRow, section: Section.shown.rawValue)
        }
        let row = min(max(proposedDestinationIndexPath.row, 1), lastMovableRow)
        return IndexPath(row: row, section: Section.shown.rawValue)
    }

    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        let item = shownItems.remove(at: sourceIndexPath.row)
        shownItems.insert(item, at: destinationIndexPath.row)
        updatePreview()
        tableView.reloadSections(IndexSet(integer: Section.shown.rawValue), with: .none)
        if mode == .settings {
            settings.setTabItems(shownItems)
        }
    }
}

// MARK: - Cell

private final class TabItemCell: UITableViewCell {
    static let reuseIdentifier = "TabItemCell"

    enum Action {
        case fixed
        case remove
        case add
        case addDisabled
    }

    private let actionButton = UIButton(type: .system)
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let fixedLabel = PaddingLabel()
    private var handler: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none

        actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)
        iconView.contentMode = .center
        iconView.tintColor = .label
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.adjustsFontForContentSizeCategory = true

        fixedLabel.text = "固定"
        fixedLabel.font = .preferredFont(forTextStyle: .caption1)
        fixedLabel.textColor = .secondaryLabel
        fixedLabel.backgroundColor = .tertiarySystemFill
        fixedLabel.layer.cornerRadius = 6
        fixedLabel.clipsToBounds = true
        fixedLabel.insets = UIEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)

        let stack = UIStackView(arrangedSubviews: [actionButton, iconView, titleLabel, fixedLabel])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        stack.setCustomSpacing(10, after: iconView)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            actionButton.widthAnchor.constraint(equalToConstant: 28),
            actionButton.heightAnchor.constraint(equalToConstant: 28),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(item: MainTabItem, action: Action, handler: (() -> Void)? = nil) {
        self.handler = handler
        iconView.image = UIImage(systemName: item.symbolName)
        titleLabel.text = item.title
        fixedLabel.isHidden = action != .fixed
        accessibilityIdentifier = "tab-customize-row-\(item.rawValue)"

        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        let disabled = action == .addDisabled || action == .fixed
        iconView.tintColor = action == .addDisabled ? .tertiaryLabel : .label
        titleLabel.textColor = action == .addDisabled ? .tertiaryLabel : .label
        switch action {
        case .fixed:
            actionButton.setImage(UIImage(systemName: "lock.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15)), for: .normal)
            actionButton.tintColor = .tertiaryLabel
            actionButton.accessibilityIdentifier = nil
            actionButton.accessibilityLabel = "\(item.title)，固定"
        case .remove:
            // 系统编辑列表的移除样式，属于状态色
            actionButton.setImage(UIImage(systemName: "minus.circle.fill", withConfiguration: symbolConfiguration), for: .normal)
            actionButton.tintColor = .systemRed
            actionButton.accessibilityIdentifier = "tab-customize-remove-\(item.rawValue)"
            actionButton.accessibilityLabel = "移除\(item.title)"
        case .add, .addDisabled:
            actionButton.setImage(UIImage(systemName: "plus.circle.fill", withConfiguration: symbolConfiguration), for: .normal)
            actionButton.tintColor = disabled ? .tertiaryLabel : .systemGreen
            actionButton.accessibilityIdentifier = "tab-customize-add-\(item.rawValue)"
            actionButton.accessibilityLabel = "添加\(item.title)"
        }
        // 满 5 项时仍可点按，用于提示上限
        actionButton.isUserInteractionEnabled = action != .fixed
    }

    @objc private func actionTapped() {
        handler?()
    }
}

/// 带内边距的标签，用于“固定”标记和上限提示。
private final class PaddingLabel: UILabel {
    var insets = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }
}
