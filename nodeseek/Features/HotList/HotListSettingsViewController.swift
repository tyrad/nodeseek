//
//  HotListSettingsViewController.swift
//  nodeseek
//

import UIKit

/// 热榜设置：展示数据来源，允许改三个接口地址。保存前逐个请求校验，任一失败都不保存。
final class HotListSettingsViewController: UITableViewController, UITextFieldDelegate {
    private enum Section: Int, CaseIterable {
        case order
        case source
        case urls
        case reset
    }

    private enum SourceRow: Int, CaseIterable {
        case provider
        case lastUpdated
        case scriptPage
    }

    static let scriptPageURL = URL(string: "https://greasyfork.org/zh-CN/scripts/560065")!

    private let repository: HotListRepository
    private let settings: HotListSourceSettings
    private var drafts: [HotListKind: String] = [:]
    private var kindOrder: [HotListKind]
    private var lastUpdatedText = HotListL10n.text("尚未更新")
    private var isSaving = false {
        didSet { navigationItem.rightBarButtonItem?.isEnabled = !isSaving }
    }

    private let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    init(repository: HotListRepository, settings: HotListSourceSettings = .shared) {
        self.repository = repository
        self.settings = settings
        kindOrder = settings.kindOrder
        super.init(style: .insetGrouped)
        title = HotListL10n.text("热榜设置")
        loadDrafts()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: HotListL10n.text("保存"),
            style: .done,
            target: self,
            action: #selector(saveTapped)
        )
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "hot-list-settings-save"
        tableView.keyboardDismissMode = .interactive
        // 常驻编辑状态只为显示顺序区的拖动手柄，其他行照常点按和输入
        tableView.isEditing = true
        tableView.allowsSelectionDuringEditing = true
        tableView.register(HotListURLFieldCell.self, forCellReuseIdentifier: HotListURLFieldCell.reuseIdentifier)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task { [weak self] in
            guard let self else { return }
            let lastSuccess = await self.repository.lastSuccessAt
            let failed = await self.repository.lastAttemptFailed
            if let lastSuccess {
                let time = self.relativeFormatter.localizedString(for: min(lastSuccess, Date()), relativeTo: Date())
                self.lastUpdatedText = HotListL10n.format(failed ? "%@ · 最近一次失败" : "%@ · 正常", time)
            } else {
                self.lastUpdatedText = HotListL10n.text("尚未更新")
            }
            self.tableView.reloadRows(
                at: [IndexPath(row: SourceRow.lastUpdated.rawValue, section: Section.source.rawValue)],
                with: .none
            )
        }
    }

    private func loadDrafts() {
        for kind in HotListKind.allCases {
            drafts[kind] = settings.url(for: kind).absoluteString
        }
    }

    // MARK: - Table

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .order: return kindOrder.count
        case .source: return SourceRow.allCases.count
        case .urls: return HotListKind.allCases.count
        case .reset: return 1
        case nil: return 0
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .order: return HotListL10n.text("榜单顺序")
        case .source: return HotListL10n.text("数据来源")
        case .urls: return HotListL10n.text("接口地址")
        default: return nil
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .order: return HotListL10n.text("拖动调整顺序，排在第一的榜单默认打开。")
        case .source: return HotListL10n.text("榜单和热度由第三方统计，不是 NodeSeek 官方数据。")
        case .urls: return HotListL10n.text("接口需返回与默认地址相同格式的 JSON。保存时会先请求一次校验，失败则不保存。")
        default: return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {
        case .order:
            let kind = kindOrder[indexPath.row]
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            var content = cell.defaultContentConfiguration()
            content.text = kind.sourceTitle
            content.secondaryText = kind.rangeDescription
            content.secondaryTextProperties.color = .secondaryLabel
            cell.contentConfiguration = content
            cell.selectionStyle = .none
            cell.accessibilityIdentifier = "hot-list-order-\(kind.rawValue)"
            return cell
        case .source:
            return sourceCell(row: SourceRow(rawValue: indexPath.row) ?? .provider)
        case .urls:
            let kind = HotListKind.allCases[indexPath.row]
            let cell = tableView.dequeueReusableCell(withIdentifier: HotListURLFieldCell.reuseIdentifier, for: indexPath)
            if let cell = cell as? HotListURLFieldCell {
                cell.configure(
                    title: kind.sourceTitle,
                    text: drafts[kind] ?? "",
                    placeholder: kind.defaultURL.absoluteString,
                    isLast: indexPath.row == HotListKind.allCases.count - 1
                )
                cell.textField.delegate = self
                cell.textField.tag = indexPath.row
                cell.textField.accessibilityIdentifier = "hot-list-url-\(kind.rawValue)"
                cell.onTextChange = { [weak self] text in self?.drafts[kind] = text }
            }
            return cell
        case .reset, nil:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            var content = cell.defaultContentConfiguration()
            content.text = HotListL10n.text("恢复默认地址")
            content.textProperties.alignment = .center
            content.textProperties.color = .label
            cell.contentConfiguration = content
            cell.accessibilityTraits = .button
            cell.accessibilityIdentifier = "hot-list-settings-reset"
            return cell
        }
    }

    private func sourceCell(row: SourceRow) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        var content = UIListContentConfiguration.valueCell()
        content.prefersSideBySideTextAndSecondaryText = true
        content.secondaryTextProperties.numberOfLines = 0
        switch row {
        case .provider:
            content.text = HotListL10n.text("提供方")
            content.secondaryText = settings.isUsingDefaults
                ? HotListL10n.text("NodeSeek 热榜插件（第三方）")
                : HotListL10n.text("自定义地址")
            cell.selectionStyle = .none
        case .lastUpdated:
            content.text = HotListL10n.text("上次更新")
            content.secondaryText = lastUpdatedText
            cell.selectionStyle = .none
        case .scriptPage:
            content.text = HotListL10n.text("查看插件主页")
            cell.accessoryType = .disclosureIndicator
        }
        cell.contentConfiguration = content
        return cell
    }

    // MARK: - Reorder

    override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        .none
    }

    override func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
        false
    }

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        indexPath.section == Section.order.rawValue
    }

    override func tableView(
        _ tableView: UITableView,
        targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
        toProposedIndexPath proposedDestinationIndexPath: IndexPath
    ) -> IndexPath {
        // 只能在顺序区内拖动
        let section = Section.order.rawValue
        if proposedDestinationIndexPath.section < section { return IndexPath(row: 0, section: section) }
        if proposedDestinationIndexPath.section > section { return IndexPath(row: kindOrder.count - 1, section: section) }
        return proposedDestinationIndexPath
    }

    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        let kind = kindOrder.remove(at: sourceIndexPath.row)
        kindOrder.insert(kind, at: destinationIndexPath.row)
        settings.setKindOrder(kindOrder)
    }

    override func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        switch Section(rawValue: indexPath.section) {
        case .source: return indexPath.row == SourceRow.scriptPage.rawValue
        case .reset: return true
        default: return false
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section) {
        case .source where indexPath.row == SourceRow.scriptPage.rawValue:
            UIApplication.shared.open(Self.scriptPageURL)
        case .reset:
            resetToDefaults()
        default:
            break
        }
    }

    // MARK: - Text field

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let next = IndexPath(row: textField.tag + 1, section: Section.urls.rawValue)
        if next.row < HotListKind.allCases.count,
           let cell = tableView.cellForRow(at: next) as? HotListURLFieldCell {
            cell.textField.becomeFirstResponder()
        } else {
            textField.resignFirstResponder()
        }
        return true
    }

    func textFieldShouldClear(_ textField: UITextField) -> Bool {
        if HotListKind.allCases.indices.contains(textField.tag) {
            drafts[HotListKind.allCases[textField.tag]] = ""
        }
        return true
    }

    // MARK: - Actions

    private func resetToDefaults() {
        view.endEditing(true)
        settings.resetToDefaults()
        loadDrafts()
        tableView.reloadData()
        BottomToast.show(HotListL10n.text("已恢复默认地址"), in: view)
    }

    @objc private func saveTapped() {
        guard !isSaving else { return }
        view.endEditing(true)

        var urls: [HotListKind: URL] = [:]
        for kind in HotListKind.allCases {
            let text = (drafts[kind] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                urls[kind] = kind.defaultURL
                continue
            }
            guard let url = HotListSourceSettings.validatedURL(from: text) else {
                showAlert(
                    title: HotListL10n.format("%@地址格式不正确", kind.sourceTitle),
                    message: HotListL10n.text("请填写以 https:// 开头的完整地址，留空则使用默认地址。")
                )
                return
            }
            urls[kind] = url
        }

        // 和当前一致的地址不用再请求
        let changed = urls.filter { settings.url(for: $0.key) != $0.value }
        guard !changed.isEmpty else {
            navigationController?.popViewController(animated: true)
            return
        }

        isSaving = true
        BottomToast.show(HotListL10n.text("正在校验…"), style: .progress, in: view)
        Task { [weak self] in
            guard let self else { return }
            for kind in HotListKind.allCases {
                guard let url = changed[kind] else { continue }
                do {
                    _ = try await self.repository.validate(url)
                } catch {
                    self.isSaving = false
                    let message = error is HotListDecodingError
                        ? HotListL10n.text("热榜数据格式不正确")
                        : HotListL10n.text("网络不可用或热榜服务暂时无法访问")
                    self.showAlert(title: HotListL10n.format("%@地址无法使用", kind.sourceTitle), message: message)
                    return
                }
            }
            self.settings.setURLs(urls)
            self.isSaving = false
            BottomToast.show(HotListL10n.text("已保存"), in: self.view)
            self.navigationController?.popViewController(animated: true)
        }
    }

    private func showAlert(title: String, message: String) {
        view.window?.subviews
            .filter { $0.accessibilityIdentifier == BottomToast.accessibilityIdentifier }
            .forEach { $0.removeFromSuperview() }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: HotListL10n.text("好"), style: .default))
        present(alert, animated: true)
    }
}

/// 接口地址输入行：上方是榜单名，下方是可编辑的地址。
final class HotListURLFieldCell: UITableViewCell {
    static let reuseIdentifier = "HotListURLFieldCell"

    var onTextChange: ((String) -> Void)?

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        return label
    }()

    let textField: UITextField = {
        let field = UITextField()
        field.font = UIFontMetrics(forTextStyle: .subheadline)
            .scaledFont(for: .monospacedSystemFont(ofSize: 14, weight: .regular))
        field.adjustsFontForContentSizeCategory = true
        field.textColor = .label
        field.keyboardType = .URL
        field.textContentType = .URL
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.clearButtonMode = .whileEditing
        // 地址按从左到右显示，不随界面语言翻转
        field.semanticContentAttribute = .forceLeftToRight
        return field
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        let stack = UIStackView(arrangedSubviews: [titleLabel, textField])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            textField.heightAnchor.constraint(greaterThanOrEqualToConstant: 28)
        ])
        textField.addAction(UIAction { [weak self] _ in
            self?.onTextChange?(self?.textField.text ?? "")
        }, for: .editingChanged)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, text: String, placeholder: String, isLast: Bool) {
        titleLabel.text = title
        textField.text = text
        textField.placeholder = placeholder
        textField.returnKeyType = isLast ? .done : .next
    }
}
