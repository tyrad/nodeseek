//
//  AccountSwitcherViewController.swift
//  nodeseek
//

import UIKit

/// 快捷切换账号半屏面板：展示已保存账号列表、添加账号与管理账号入口。
final class AccountSwitcherViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case accounts
        case actions
    }

    private enum ActionRow: Int, CaseIterable {
        case addAccount
        case manageAccounts
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
        title = AccountsL10n.text("切换账号")
        view.backgroundColor = .systemGroupedBackground
        tableView.backgroundColor = .systemGroupedBackground
        tableView.tintColor = .label
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 64
        tableView.accessibilityIdentifier = "account-switcher-table-view"
        tableView.register(AccountRowCell.self, forCellReuseIdentifier: AccountRowCell.reuseIdentifier)

        let closeItem = UIBarButtonItem(
            image: UIImage(systemName: "xmark"),
            style: .plain,
            target: self,
            action: #selector(closeTapped)
        )
        closeItem.tintColor = .label
        closeItem.accessibilityLabel = AccountsL10n.text("关闭")
        navigationItem.rightBarButtonItem = closeItem

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

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    // MARK: - UITableViewDataSource

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .accounts:
            return max(1, accounts.count)
        case .actions:
            return ActionRow.allCases.count
        case .none:
            return 0
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {
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

        case .actions:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.textColor = ReadingColors.text
            cell.textLabel?.font = .preferredFont(forTextStyle: .body)
            cell.textLabel?.adjustsFontForContentSizeCategory = true
            switch ActionRow(rawValue: indexPath.row) {
            case .addAccount:
                cell.textLabel?.text = AccountsL10n.text("添加账号")
                cell.imageView?.image = UIImage(systemName: "plus.circle")
                cell.imageView?.tintColor = .label
                cell.accessibilityIdentifier = "account-switcher-add-button"
            case .manageAccounts:
                cell.textLabel?.text = AccountsL10n.text("管理账号")
                cell.imageView?.image = UIImage(systemName: "slider.horizontal.3")
                cell.imageView?.tintColor = .label
                cell.accessoryType = .disclosureIndicator
                cell.accessibilityIdentifier = "account-switcher-manage-button"
            case .none:
                break
            }
            return cell

        case .none:
            return UITableViewCell()
        }
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section) {
        case .accounts:
            guard accounts.indices.contains(indexPath.row) else { return }
            let account = accounts[indexPath.row]
            if account.uid == activeUID && account.credentialState == .valid {
                dismiss(animated: true)
                return
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                _ = await AccountsModule.switchToAccount(uid: account.uid, from: self)
            }

        case .actions:
            switch ActionRow(rawValue: indexPath.row) {
            case .addAccount:
                AccountsModule.presentAddAccount(from: self)
            case .manageAccounts:
                navigationController?.pushViewController(AccountManagementViewController(vaultStore: vaultStore), animated: true)
            case .none:
                break
            }

        case .none:
            break
        }
    }
}
