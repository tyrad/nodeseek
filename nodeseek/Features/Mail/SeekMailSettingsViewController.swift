//
//  SeekMailSettingsViewController.swift
//  nodeseek
//

import SafariServices
import UIKit

/// 底部栏邮箱 Tab 是否显示未读数；只影响 Tab 角标，邮箱内的未读标记照常显示。
/// 默认关闭；属于 App 偏好，不随移除 Key 清掉。
enum SeekMailTabBadgeSetting {
    static let didChangeNotification = Notification.Name("SeekMailTabBadgeSetting.didChange")
    private static let key = "seekMail.tabBadgeEnabled"

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        (defaults.object(forKey: key) as? Bool) ?? false
    }

    static func setEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: key)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}

/// 邮箱设置：原来导航栏「更多」菜单里的偏好、邮箱管理和账号操作集中到这一页。
final class SeekMailSettingsViewController: UIViewController {
    struct Actions {
        /// 新建邮箱的弹窗；创建成功后回调，用于在本页提示。
        var makeCreateMailbox: (_ onCreated: @escaping (SeekMailbox) -> Void) -> UIViewController
        var replaceKey: () -> Void
        /// 用户确认后执行，由入口页清理数据并返回。
        var removeKey: () -> Void
    }

    private enum Section: Int, CaseIterable { case display, mailboxes, key, remove }
    private enum Row {
        case tabBadge, autoRefresh
        case createMailbox, storage, manage
        case replaceKey
        case removeKey
    }

    private enum StorageState {
        case loading
        case loaded(String)
        case failed
    }

    private let selectionStore: SeekMailSelectionStore
    private let provider: SeekMailProvider<SeekMailAPI>
    private let actions: Actions
    private let defaults: UserDefaults
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let toast = SeekMailUndoToast()
    private var storageState: StorageState = .loading
    private var storageTask: Task<Void, Never>?

    init(selectionStore: SeekMailSelectionStore,
         provider: SeekMailProvider<SeekMailAPI>,
         defaults: UserDefaults = .standard,
         actions: Actions) {
        self.selectionStore = selectionStore
        self.provider = provider
        self.defaults = defaults
        self.actions = actions
        super.init(nibName: nil, bundle: nil)
        title = SeekMailL10n.text("邮箱设置")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        storageTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        tableView.dataSource = self
        tableView.delegate = self
        tableView.accessibilityIdentifier = "seek-mail-settings-list"
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        NotificationCenter.default.addObserver(
            self, selector: #selector(textSizeDidChange),
            name: AppTextSizeSettings.didChangeNotification, object: nil
        )
        loadStorage()
    }

    @objc private func textSizeDidChange() {
        toast.refreshFonts()
        tableView.reloadData()
    }

    private func rows(in section: Section) -> [Row] {
        switch section {
        case .display: return [.tabBadge, .autoRefresh]
        case .mailboxes: return [.createMailbox, .storage, .manage]
        case .key: return [.replaceKey]
        case .remove: return [.removeKey]
        }
    }

    // MARK: - 存储用量

    private func loadStorage() {
        storageTask?.cancel()
        storageState = .loading
        reloadRow(.storage)
        storageTask = Task { [weak self, provider] in
            let quota = try? await provider.quota()
            guard let self, Task.isCancelled == false else { return }
            if let storage = quota?.storage {
                let percent = storage.usagePercent ?? Int(Double(storage.used) / Double(max(storage.quota, 1)) * 100)
                storageState = .loaded("\(SeekMailFormat.bytes(storage.used)) / \(SeekMailFormat.bytes(storage.quota)) · \(percent)%")
            } else {
                storageState = .failed
            }
            reloadRow(.storage)
        }
    }

    private func reloadRow(_ row: Row) {
        guard isViewLoaded else { return }
        for section in Section.allCases {
            if let index = rows(in: section).firstIndex(of: row) {
                tableView.reloadRows(at: [IndexPath(row: index, section: section.rawValue)], with: .none)
            }
        }
    }

    // MARK: - 自动刷新

    static func autoRefreshTitle(_ seconds: Int) -> String {
        seconds == 0 ? SeekMailL10n.text("关闭") : SeekMailL10n.format("每 %@ 秒", String(seconds))
    }

    /// 用弹出菜单直接选，不再进一层页面；列表回到前台时按新间隔重新计时。
    private func makeAutoRefreshButton() -> UIButton {
        let current = selectionStore.autoRefreshSeconds
        var configuration = UIButton.Configuration.plain()
        configuration.baseForegroundColor = .secondaryLabel
        configuration.image = UIImage(systemName: "chevron.up.chevron.down")
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 4
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 0)
        var title = AttributedString(Self.autoRefreshTitle(current))
        title.font = SeekMailFont.of(.body)
        configuration.attributedTitle = title
        let button = UIButton(configuration: configuration)
        button.menu = UIMenu(children: SeekMailSelectionStore.autoRefreshOptions.map { seconds in
            UIAction(title: Self.autoRefreshTitle(seconds), state: seconds == current ? .on : .off) { [weak self] _ in
                self?.selectionStore.autoRefreshSeconds = seconds
                self?.reloadRow(.autoRefresh)
            }
        })
        button.showsMenuAsPrimaryAction = true
        button.accessibilityLabel = SeekMailL10n.text("自动刷新")
        button.accessibilityValue = Self.autoRefreshTitle(current)
        button.accessibilityIdentifier = "seek-mail-settings-auto-refresh"
        button.sizeToFit()
        return button
    }

    // MARK: - 操作

    @objc private func tabBadgeChanged(_ sender: UISwitch) {
        SeekMailTabBadgeSetting.setEnabled(sender.isOn, defaults: defaults)
    }

    private func presentCreateMailbox() {
        let controller = actions.makeCreateMailbox { [weak self] mailbox in
            guard let self else { return }
            toast.showMessage(SeekMailL10n.format("已创建并复制 %@", mailbox.address), in: view)
            loadStorage()
        }
        present(controller, animated: true)
    }

    private func confirmRemoveKey() {
        let alert = UIAlertController(
            title: SeekMailL10n.text("移除 API Key？"),
            message: SeekMailL10n.text("本机保存的 Key 会被删除，邮箱数据不受影响。之后需要重新粘贴 Key 才能查看邮件。"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: SeekMailL10n.text("取消"), style: .cancel))
        alert.addAction(UIAlertAction(title: SeekMailL10n.text("移除"), style: .destructive) { [weak self] _ in
            self?.actions.removeKey()
        })
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource / Delegate

extension SeekMailSettingsViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        Section(rawValue: section).map { rows(in: $0).count } ?? 0
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .display: return SeekMailL10n.text("显示与刷新")
        case .mailboxes: return SeekMailL10n.text("邮箱与存储")
        case .key: return "API Key"
        case .remove, .none: return nil
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        Section(rawValue: section) == .display
            ? SeekMailL10n.text("关闭后只隐藏底部栏邮箱 Tab 的数字，邮箱内的未读标记不受影响。")
            : nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else { return UITableViewCell() }
        let row = rows(in: section)[indexPath.row]
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        var content = UIListContentConfiguration.valueCell()
        content.textProperties.font = SeekMailFont.of(.body)
        content.textProperties.numberOfLines = 0
        content.secondaryTextProperties.font = SeekMailFont.of(.body)
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.numberOfLines = 0

        switch row {
        case .tabBadge:
            content.text = SeekMailL10n.text("多 Tab 模式未读角标")
            let toggle = UISwitch()
            toggle.isOn = SeekMailTabBadgeSetting.isEnabled(defaults: defaults)
            toggle.accessibilityIdentifier = "seek-mail-settings-tab-badge"
            toggle.addTarget(self, action: #selector(tabBadgeChanged(_:)), for: .valueChanged)
            cell.accessoryView = toggle
            cell.selectionStyle = .none
        case .autoRefresh:
            content.text = SeekMailL10n.text("自动刷新")
            cell.accessoryView = makeAutoRefreshButton()
            cell.selectionStyle = .none
        case .createMailbox:
            content.text = SeekMailL10n.text("新建邮箱")
            cell.accessoryType = .disclosureIndicator
        case .storage:
            content.text = SeekMailL10n.text("存储用量")
            switch storageState {
            case .loading:
                let spinner = UIActivityIndicatorView(style: .medium)
                spinner.startAnimating()
                cell.accessoryView = spinner
                cell.selectionStyle = .none
            case .loaded(let text):
                content.secondaryText = text
                cell.selectionStyle = .none
            case .failed:
                content.secondaryText = SeekMailL10n.text("暂时无法获取，点按重试")
            }
        case .manage:
            content.text = SeekMailL10n.text("在网页中管理")
            let icon = UIImageView(image: UIImage(systemName: "arrow.up.right.square"))
            icon.tintColor = .tertiaryLabel
            cell.accessoryView = icon
            cell.accessibilityTraits = .link
        case .replaceKey:
            content.text = SeekMailL10n.text("更换 API Key")
            cell.accessoryType = .disclosureIndicator
        case .removeKey:
            content = UIListContentConfiguration.cell()
            content.text = SeekMailL10n.text("移除 Key 并退出")
            content.textProperties.font = SeekMailFont.of(.body)
            content.textProperties.color = .systemRed
            content.textProperties.alignment = .center
            content.textProperties.numberOfLines = 0
        }
        cell.contentConfiguration = content
        cell.accessibilityIdentifier = "seek-mail-settings-\(row)"
        return cell
    }

    func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        guard let section = Section(rawValue: indexPath.section) else { return false }
        switch rows(in: section)[indexPath.row] {
        case .tabBadge, .autoRefresh: return false
        case .storage:
            if case .failed = storageState { return true }
            return false
        default: return true
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let section = Section(rawValue: indexPath.section) else { return }
        switch rows(in: section)[indexPath.row] {
        case .createMailbox: presentCreateMailbox()
        case .storage: loadStorage()
        case .manage: present(SFSafariViewController(url: SeekMailLinks.manage), animated: true)
        case .replaceKey: actions.replaceKey()
        case .removeKey: confirmRemoveKey()
        case .tabBadge, .autoRefresh: break
        }
    }
}
