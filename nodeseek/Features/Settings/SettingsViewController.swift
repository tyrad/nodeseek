//
//  SettingsViewController.swift
//  nodeseek
//
//  Created by Codex on 2026/5/2.
//

import Kingfisher
import UIKit
import WebKit

@MainActor
protocol SettingsCacheManaging: AnyObject {
    func cacheByteSize() async -> UInt64
    func clearPreservingCookies() async throws
}

@MainActor
protocol SettingsSessionManaging: AnyObject {
    func logout() async
}

final class DefaultSettingsCacheManager: SettingsCacheManaging {
    func cacheByteSize() async -> UInt64 {
        let detailSize = UInt64(max(DetailImageLoader.shared.detailImageCacheByteSize(), 0))
        let kingfisherSize = (try? await ImageCache.default.diskStorageSize) ?? 0
        return detailSize + UInt64(kingfisherSize)
    }

    func clearPreservingCookies() async throws {
        try DetailImageLoader.shared.clearDetailImageCache()
        AvatarImageLoader.shared.clearMemoryCaches()
        ImageCache.default.clearMemoryCache()
        await ImageCache.default.clearDiskCache()
        URLCache.shared.removeAllCachedResponses()
        await clearWebViewCachesPreservingCookies()
    }

    private func clearWebViewCachesPreservingCookies() async {
        let dataTypes: Set<String> = [
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache
        ]
        await WKWebsiteDataStore.default().removeData(
            ofTypes: dataTypes,
            modifiedSince: Date(timeIntervalSince1970: 0)
        )
    }
}

final class DefaultSettingsSessionManager: SettingsSessionManaging {
    private let cookieBridge: CookieBridge
    private let currentAccountStore: CurrentAccountStore

    init(
        cookieBridge: CookieBridge? = nil,
        currentAccountStore: CurrentAccountStore = .shared
    ) {
        self.cookieBridge = cookieBridge ?? CookieBridge()
        self.currentAccountStore = currentAccountStore
    }

    func logout() async {
        await cookieBridge.clearSession()
        await currentAccountStore.clear()
        NotificationCenter.default.post(name: .nodeSeekLoginSessionDidClose, object: nil)
    }
}

final class SettingsViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case cache
        case debug
        case account
    }

    private enum DebugRow: Int, CaseIterable {
        case fileLogging
        case logFile
        case detailTest

        static var visibleRows: [DebugRow] {
            var rows: [DebugRow] = [.fileLogging, .logFile]
            #if DEBUG
            if NodeSeekDebugConfig.enablePostDetailTestEntry {
                rows.append(.detailTest)
            }
            #endif
            return rows
        }
    }

    private let cacheManager: SettingsCacheManaging
    private let sessionManager: SettingsSessionManaging
    private let confirmsActionsImmediately: Bool
    private let onLogout: @MainActor () -> Void
    private let onLogFile: @MainActor () -> Void
    private let onDetailTest: (@MainActor () -> Void)?
    private var cacheByteSize: UInt64?
    private var isClearingCache = false
    private var isLoggingOut = false

    init(
        cacheManager: SettingsCacheManaging? = nil,
        sessionManager: SettingsSessionManaging? = nil,
        confirmsActionsImmediately: Bool = false,
        onLogout: @escaping @MainActor () -> Void = {},
        onLogFile: @escaping @MainActor () -> Void = {},
        onDetailTest: (@MainActor () -> Void)? = nil
    ) {
        self.cacheManager = cacheManager ?? DefaultSettingsCacheManager()
        self.sessionManager = sessionManager ?? DefaultSettingsSessionManager()
        self.confirmsActionsImmediately = confirmsActionsImmediately
        self.onLogout = onLogout
        self.onLogFile = onLogFile
        self.onDetailTest = onDetailTest
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "设置"
        tableView.accessibilityIdentifier = "settings-table-view"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SettingsCell")
        refreshCacheSize()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if Section(rawValue: section) == .debug {
            return DebugRow.visibleRows.count
        }
        return 1
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .cache:
            return "缓存"
        case .debug:
            return "调试"
        case .account:
            return "账号"
        case .none:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {
        case .cache:
            return cacheCell(for: indexPath)
        case .debug:
            return debugCell(for: indexPath)
        case .account:
            return logoutCell(for: indexPath)
        case .none:
            return UITableViewCell()
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section) {
        case .cache:
            confirmClearCache()
        case .debug:
            handleDebugSelection(at: indexPath)
        case .account:
            confirmLogout()
        case .none:
            break
        }
    }

    private func cacheCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.textLabel?.text = isClearingCache ? "正在清除缓存..." : "清除缓存"
        cell.detailTextLabel?.text = cacheDetailText
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = isClearingCache ? .none : .default
        cell.isUserInteractionEnabled = !isClearingCache
        cell.accessibilityIdentifier = "settings-clear-cache-cell"
        return cell
    }

    private func logoutCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = isLoggingOut ? "正在退出登录..." : "退出登录"
        cell.textLabel?.textColor = .systemRed
        cell.textLabel?.textAlignment = .center
        cell.selectionStyle = isLoggingOut ? .none : .default
        cell.isUserInteractionEnabled = !isLoggingOut
        cell.accessibilityIdentifier = "settings-logout-cell"
        return cell
    }

    private func debugCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        switch DebugRow.visibleRows[indexPath.row] {
        case .fileLogging:
            cell.textLabel?.text = "记录日志"
            let loggingSwitch = UISwitch()
            loggingSwitch.isOn = NodeSeekDebugConfig.enableFileLogging
            loggingSwitch.accessibilityIdentifier = "settings-file-logging-switch"
            loggingSwitch.addTarget(self, action: #selector(fileLoggingSwitchChanged(_:)), for: .valueChanged)
            cell.accessoryView = loggingSwitch
            cell.selectionStyle = .none
            cell.accessibilityIdentifier = "settings-file-logging-cell"
            return cell
        case .logFile:
            cell.textLabel?.text = "日志文件"
            cell.imageView?.image = UIImage(systemName: "doc.text")
            cell.accessibilityIdentifier = "settings-log-file-cell"
        case .detailTest:
            cell.textLabel?.text = "详情测试"
            cell.imageView?.image = UIImage(systemName: "doc.text.magnifyingglass")
            cell.accessibilityIdentifier = "settings-detail-test-cell"
        }
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    private var cacheDetailText: String {
        guard let cacheByteSize else {
            return "计算中"
        }
        return ByteCountFormatter.string(fromByteCount: Int64(cacheByteSize), countStyle: .file)
    }

    private func refreshCacheSize() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            cacheByteSize = await cacheManager.cacheByteSize()
            tableView.reloadSections(IndexSet(integer: Section.cache.rawValue), with: .none)
        }
    }

    private func confirmClearCache() {
        guard !isClearingCache else { return }
        guard !confirmsActionsImmediately else {
            performClearCache()
            return
        }

        let alert = UIAlertController(
            title: "清除缓存",
            message: "将清除图片、网页和网络缓存，但会保留登录状态。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "清除", style: .destructive) { [weak self] _ in
            self?.performClearCache()
        })
        present(alert, animated: true)
    }

    private func confirmLogout() {
        guard !isLoggingOut else { return }
        guard !confirmsActionsImmediately else {
            performLogout()
            return
        }

        let alert = UIAlertController(
            title: "退出登录",
            message: "将清除 NodeSeek 登录 Cookie 和本地账号状态。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "退出登录", style: .destructive) { [weak self] _ in
            self?.performLogout()
        })
        present(alert, animated: true)
    }

    private func handleDebugSelection(at indexPath: IndexPath) {
        switch DebugRow.visibleRows[indexPath.row] {
        case .fileLogging:
            break
        case .logFile:
            onLogFile()
        case .detailTest:
            guard let onDetailTest else { return }
            if let navigationController {
                navigationController.popViewController(animated: true)
                DispatchQueue.main.async { [onDetailTest] in
                    onDetailTest()
                }
                return
            }
            onDetailTest()
        }
    }

    @objc private func fileLoggingSwitchChanged(_ sender: UISwitch) {
        NodeSeekDebugConfig.enableFileLogging = sender.isOn
    }

    private func performClearCache() {
        isClearingCache = true
        tableView.reloadRows(at: [IndexPath(row: 0, section: Section.cache.rawValue)], with: .none)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await cacheManager.clearPreservingCookies()
                cacheByteSize = await cacheManager.cacheByteSize()
                isClearingCache = false
                tableView.reloadSections(IndexSet(integer: Section.cache.rawValue), with: .none)
                showAlert(title: "已清除缓存", message: "登录状态已保留。")
            } catch {
                isClearingCache = false
                tableView.reloadSections(IndexSet(integer: Section.cache.rawValue), with: .none)
                showAlert(title: "清除失败", message: error.localizedDescription)
            }
        }
    }

    private func performLogout() {
        isLoggingOut = true
        tableView.reloadRows(at: [IndexPath(row: 0, section: Section.account.rawValue)], with: .none)
        Task { @MainActor [weak self] in
            guard let self else { return }
            await sessionManager.logout()
            isLoggingOut = false
            tableView.reloadRows(at: [IndexPath(row: 0, section: Section.account.rawValue)], with: .none)
            onLogout()
            navigationController?.popViewController(animated: true)
        }
    }

    private func showAlert(title: String, message: String) {
        guard !confirmsActionsImmediately else { return }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}

private extension WKWebsiteDataStore {
    func removeData(ofTypes dataTypes: Set<String>, modifiedSince date: Date) async {
        await withCheckedContinuation { continuation in
            removeData(ofTypes: dataTypes, modifiedSince: date) {
                continuation.resume()
            }
        }
    }
}
