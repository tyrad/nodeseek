//
//  AccountManagementViewController.swift
//  nodeseek
//

import UIKit

/// 账号管理页：查看全部已保存账号、切换、重登、左滑删除、添加账号与退出当前账号。
final class AccountManagementViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case accounts
        case add
        case logout
    }

    private let vaultStore: AccountVaultStore
    private var accounts: [SavedAccount] = []
    private var activeUID: Int?
    private var vaultObserver: NSObjectProtocol?

    init(vaultStore: AccountVaultStore = .shared) {
        self.vaultStore = vaultStore
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let vaultObserver {
            NotificationCenter.default.removeObserver(vaultObserver)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = AccountsL10n.text("账号管理")
        view.backgroundColor = .systemGroupedBackground
        tableView.backgroundColor = .systemGroupedBackground
        tableView.tintColor = .label
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 64
        tableView.accessibilityIdentifier = "account-management-table-view"
        tableView.register(AccountRowCell.self, forCellReuseIdentifier: AccountRowCell.reuseIdentifier)

        vaultObserver = NotificationCenter.default.addObserver(
            forName: AccountVaultStore.didChangeNotification,
            object: vaultStore,
            queue: .main
        ) { [weak self] _ in
            self?.reloadAccounts()
        }
        reloadAccounts()
    }

    private func reloadAccounts() {
        accounts = vaultStore.accounts
        activeUID = vaultStore.activeUID
        tableView.reloadData()
    }

    private var visibleSections: [Section] {
        var sections: [Section] = [.accounts, .add]
        if activeUID != nil {
            sections.append(.logout)
        }
        return sections
    }

    // MARK: - UITableViewDataSource

    override func numberOfSections(in tableView: UITableView) -> Int {
        visibleSections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch visibleSections[section] {
        case .accounts:
            return max(1, accounts.count)
        case .add, .logout:
            return 1
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch visibleSections[section] {
        case .accounts:
            return AccountsL10n.text("已保存账号")
        case .add, .logout:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch visibleSections[section] {
        case .accounts:
            return AccountsL10n.text("点击可切换账号，左滑可移除本机保存的登录凭证。凭证仅保存在本机钥匙串。")
        case .add, .logout:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch visibleSections[indexPath.section] {
        case .accounts:
            guard accounts.isEmpty == false else {
                let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
                cell.textLabel?.text = AccountsL10n.text("尚未保存任何账号")
                cell.textLabel?.textColor = .secondaryLabel
                cell.textLabel?.font = .preferredFont(forTextStyle: .subheadline)
                cell.textLabel?.adjustsFontForContentSizeCategory = true
                cell.selectionStyle = .none
                return cell
            }
            let account = accounts[indexPath.row]
            let cell = tableView.dequeueReusableCell(withIdentifier: AccountRowCell.reuseIdentifier, for: indexPath) as! AccountRowCell
            cell.configure(account: account, isActive: account.uid == activeUID)
            return cell

        case .add:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = AccountsL10n.text("添加账号")
            cell.textLabel?.textColor = ReadingColors.text
            cell.textLabel?.font = .preferredFont(forTextStyle: .body)
            cell.textLabel?.adjustsFontForContentSizeCategory = true
            cell.imageView?.image = UIImage(systemName: "plus.circle")
            cell.imageView?.tintColor = .label
            cell.accessibilityIdentifier = "account-management-add-cell"
            return cell

        case .logout:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = AccountsL10n.text("退出当前账号")
            cell.textLabel?.textColor = .systemRed
            cell.textLabel?.textAlignment = .center
            cell.textLabel?.font = .preferredFont(forTextStyle: .body)
            cell.textLabel?.adjustsFontForContentSizeCategory = true
            cell.accessibilityIdentifier = "account-management-logout-cell"
            return cell
        }
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        visibleSections[indexPath.section] == .accounts && accounts.isEmpty == false
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard visibleSections[indexPath.section] == .accounts,
              accounts.indices.contains(indexPath.row) else {
            return nil
        }
        let account = accounts[indexPath.row]
        let deleteAction = UIContextualAction(style: .destructive, title: AccountsL10n.text("移除")) { [weak self] _, _, completion in
            guard let self else {
                completion(false)
                return
            }
            self.confirmRemove(account: account)
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch visibleSections[indexPath.section] {
        case .accounts:
            guard accounts.indices.contains(indexPath.row) else { return }
            let account = accounts[indexPath.row]
            Task { @MainActor [weak self] in
                guard let self else { return }
                _ = await AccountsModule.switchToAccount(uid: account.uid, from: self)
            }

        case .add:
            AccountsModule.presentAddAccount(from: self)

        case .logout:
            confirmLogoutCurrentAccount()
        }
    }

    private func confirmRemove(account: SavedAccount) {
        let isActive = account.uid == activeUID
        let title = isActive ? AccountsL10n.text("退出当前账号") : AccountsL10n.text("移除账号")
        let message = isActive
            ? AccountsL10n.format("退出「%@」将删除本机保存的登录凭证并切换到游客模式。", account.displayName)
            : AccountsL10n.format("移除「%@」后将删除本机保存的登录凭证，下次切换需重新登录。", account.displayName)
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: AccountsL10n.text("取消"), style: .cancel))
        alert.addAction(UIAlertAction(title: isActive ? AccountsL10n.text("退出登录") : AccountsL10n.text("移除"), style: .destructive) { _ in
            Task { @MainActor in
                _ = await AccountsModule.coordinator.removeAccount(uid: account.uid)
            }
        })
        present(alert, animated: true)
    }

    private func confirmLogoutCurrentAccount() {
        let activeName = activeUID.flatMap { vaultStore.account(uid: $0)?.displayName } ?? ""
        let message = activeName.isEmpty
            ? AccountsL10n.text("退出登录将删除本机保存的登录凭证并切换到游客模式。")
            : AccountsL10n.format("退出「%@」将删除本机保存的登录凭证并切换到游客模式。", activeName)
        let alert = UIAlertController(
            title: AccountsL10n.text("退出当前账号"),
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: AccountsL10n.text("取消"), style: .cancel))
        alert.addAction(UIAlertAction(title: AccountsL10n.text("退出登录"), style: .destructive) { _ in
            Task { @MainActor in
                _ = await AccountsModule.logoutCurrentAccount()
            }
        })
        present(alert, animated: true)
    }
}
