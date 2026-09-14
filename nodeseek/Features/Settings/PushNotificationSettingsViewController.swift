import UIKit
import UserNotifications

enum PushNotificationSettingsCopy {
    static let nsApnsRepositoryURL = URL(string: "https://github.com/tyrad/ns-apns")!
    static let setupSteps = """
    1. 使用 Telegram，并已绑定官方 Bot 接收通知
    2. 在本 App 开启推送通知
    3. 自行私有部署 ns-apns，步骤见下方仓库文档
    """

    static func listSummary(for status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "未开启"
        case .denied:
            return "系统已关闭"
        case .authorized, .provisional, .ephemeral:
            return "已开启"
        @unknown default:
            return "未开启"
        }
    }

    static func statusText(for status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "尚未开启"
        case .denied:
            return "已关闭"
        case .authorized:
            return "已开启"
        case .provisional, .ephemeral:
            return "临时开启"
        @unknown default:
            return "未知"
        }
    }
}

/// 设置里的推送入口：点开才申请权限，并提供复制 device token。
final class PushNotificationSettingsViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case steps
        case permission
        case token
        case nsApns
    }

    private enum PermissionRow: Int, CaseIterable {
        case status
        case enable
        case systemSettings
    }

    private enum TokenRow: Int, CaseIterable {
        case value
        case fetch
        case copy
    }

    private enum NsApnsRow: Int, CaseIterable {
        case github
    }

    private let tokenStore: PushNotificationTokenStore
    private let notificationCenter: UNUserNotificationCenter
    private let application: UIApplication
    private let authorizationStatusProvider: @MainActor () async -> UNAuthorizationStatus
    private var authorizationStatus: UNAuthorizationStatus = .notDetermined

    init(
        tokenStore: PushNotificationTokenStore = .shared,
        notificationCenter: UNUserNotificationCenter = .current(),
        application: UIApplication = .shared,
        authorizationStatusProvider: @escaping @MainActor () async -> UNAuthorizationStatus = {
            await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        }
    ) {
        self.tokenStore = tokenStore
        self.notificationCenter = notificationCenter
        self.application = application
        self.authorizationStatusProvider = authorizationStatusProvider
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "推送通知"
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 88
        tableView.accessibilityIdentifier = "push-notification-settings-table-view"
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(tokenDidChange),
            name: PushNotificationTokenStore.didChangeNotification,
            object: tokenStore
        )
        refreshAuthorizationStatus()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshAuthorizationStatus()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .steps:
            return 1
        case .permission:
            return visiblePermissionRows().count
        case .token:
            return TokenRow.allCases.count
        case .nsApns:
            return NsApnsRow.allCases.count
        case .none:
            return 0
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .steps:
            return "使用步骤"
        case .permission:
            return "系统权限"
        case .token:
            return "Device Token"
        case .nsApns:
            return "ns-apns"
        case .none:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .steps:
            return nil
        case .permission:
            return "不会在打开本页时弹窗，只有点「开启通知」才会向系统申请。"
        case .token:
            return "复制后粘贴到 ns-apns 设置页的 Device Token。换机或重装后需要重新获取。"
        case .nsApns:
            return "本 App 不托管推送。部署完成后，把上方 Token 填进 ns-apns 设置页。"
        case .none:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {
        case .steps:
            return stepsCell()
        case .permission:
            return permissionCell(for: visiblePermissionRows()[indexPath.row])
        case .token:
            return tokenCell(for: TokenRow(rawValue: indexPath.row))
        case .nsApns:
            return nsApnsCell(for: NsApnsRow(rawValue: indexPath.row))
        case .none:
            return UITableViewCell()
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section) {
        case .steps:
            break
        case .permission:
            switch visiblePermissionRows()[indexPath.row] {
            case .enable:
                requestAuthorizationThenRegister()
            case .systemSettings:
                openSystemSettings()
            case .status:
                break
            }
        case .token:
            switch TokenRow(rawValue: indexPath.row) {
            case .fetch:
                fetchToken()
            case .copy:
                copyToken()
            case .value, .none:
                break
            }
        case .nsApns:
            switch NsApnsRow(rawValue: indexPath.row) {
            case .github:
                openNsApnsRepository()
            case .none:
                break
            }
        case .none:
            break
        }
    }

    private func visiblePermissionRows() -> [PermissionRow] {
        var rows: [PermissionRow] = [.status]
        switch authorizationStatus {
        case .denied:
            rows.append(.systemSettings)
        case .authorized, .provisional, .ephemeral:
            break
        default:
            rows.append(.enable)
        }
        return rows
    }

    private func stepsCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = PushNotificationSettingsCopy.setupSteps
        cell.textLabel?.textColor = .label
        cell.textLabel?.numberOfLines = 0
        cell.selectionStyle = .none
        cell.accessibilityIdentifier = "push-notification-setup-steps-cell"
        return cell
    }

    private func permissionCell(for row: PermissionRow) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.textColor = .label
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.numberOfLines = 0
        switch row {
        case .status:
            cell.textLabel?.text = "当前状态"
            cell.detailTextLabel?.text = statusText
            cell.selectionStyle = .none
            cell.accessibilityIdentifier = "push-notification-status-cell"
        case .enable:
            cell.textLabel?.text = "开启通知"
            cell.detailTextLabel?.text = "允许显示横幅、声音和标记"
            cell.imageView?.image = UIImage(systemName: "bell.badge")
            cell.accessibilityIdentifier = "push-notification-enable-cell"
        case .systemSettings:
            cell.textLabel?.text = "前往系统设置"
            cell.detailTextLabel?.text = "通知已被关闭，需要在系统设置中重新打开"
            cell.imageView?.image = UIImage(systemName: "gear")
            cell.accessibilityIdentifier = "push-notification-system-settings-cell"
        }
        return cell
    }

    private func tokenCell(for row: TokenRow?) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.textColor = .label
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.numberOfLines = 0
        switch row {
        case .value:
            cell.textLabel?.text = "当前 Token"
            if let hex = tokenStore.deviceTokenHex {
                cell.detailTextLabel?.text = hex
            } else if let error = tokenStore.lastError {
                cell.detailTextLabel?.text = "获取失败：\(error)"
            } else {
                cell.detailTextLabel?.text = "还没有，请先开启通知"
            }
            cell.detailTextLabel?.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            cell.selectionStyle = .none
            cell.accessibilityIdentifier = "push-notification-token-value-cell"
        case .fetch:
            cell.textLabel?.text = "获取 Token"
            cell.detailTextLabel?.text = "注册本机，成功后显示在上方"
            cell.imageView?.image = UIImage(systemName: "arrow.down.circle")
            cell.accessibilityIdentifier = "push-notification-fetch-token-cell"
        case .copy:
            let hasToken = tokenStore.deviceTokenHex != nil
            cell.textLabel?.text = "复制 Token"
            cell.detailTextLabel?.text = hasToken ? "复制到剪贴板" : "还没有可复制的内容"
            cell.imageView?.image = UIImage(systemName: "doc.on.doc")
            cell.selectionStyle = hasToken ? .default : .none
            cell.isUserInteractionEnabled = hasToken
            cell.accessibilityIdentifier = "push-notification-copy-token-cell"
        case .none:
            break
        }
        return cell
    }

    private func nsApnsCell(for row: NsApnsRow?) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.textColor = .label
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.numberOfLines = 2
        switch row {
        case .github:
            cell.textLabel?.text = "GitHub"
            cell.detailTextLabel?.text = PushNotificationSettingsCopy.nsApnsRepositoryURL.absoluteString
            cell.imageView?.image = UIImage(systemName: "link")
            cell.accessoryType = .disclosureIndicator
            cell.accessibilityIdentifier = "push-notification-ns-apns-github-cell"
        case .none:
            break
        }
        return cell
    }

    private var statusText: String {
        PushNotificationSettingsCopy.statusText(for: authorizationStatus)
    }

    private func refreshAuthorizationStatus() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            authorizationStatus = await authorizationStatusProvider()
            tableView.reloadData()
        }
    }

    private func requestAuthorizationThenRegister() {
        notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.refreshAuthorizationStatus()
                if granted {
                    self?.application.registerForRemoteNotifications()
                }
            }
        }
    }

    private func fetchToken() {
        switch authorizationStatus {
        case .notDetermined:
            requestAuthorizationThenRegister()
        case .denied:
            openSystemSettings()
        default:
            application.registerForRemoteNotifications()
        }
    }

    private func copyToken() {
        guard let token = tokenStore.deviceTokenHex else { return }
        UIPasteboard.general.string = token
        let alert = UIAlertController(title: "已复制", message: "去 ns-apns 设置页粘贴即可。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }

    private func openNsApnsRepository() {
        application.open(PushNotificationSettingsCopy.nsApnsRepositoryURL)
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        application.open(url)
    }

    @objc private func tokenDidChange() {
        tableView.reloadSections(IndexSet(integer: Section.token.rawValue), with: .none)
    }

    func applyAuthorizationStatusForTesting(_ status: UNAuthorizationStatus) {
        authorizationStatus = status
        tableView.reloadData()
    }
}
