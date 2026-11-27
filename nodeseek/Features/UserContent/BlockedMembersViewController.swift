import UIKit

extension UIViewController {
    func confirmBlockChange(_ blocked: Bool, member: BlockedMember, completion: @escaping () -> Void) {
        let verb = AccountsL10n.text(blocked ? "拉黑用户" : "解除拉黑")
        let message = blocked ? "拉黑 %@ 后，帖子列表会隐藏对方的主题，评论区会隐藏对方的回复。仍可通过链接打开主题。" : "将 %@ 从当前账号的屏蔽名单中移除。"
        let alert = UIAlertController(title: verb, message: AccountsL10n.format(message, member.name), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: AccountsL10n.text("取消"), style: .cancel))
        alert.addAction(UIAlertAction(title: verb, style: blocked ? .destructive : .default) { _ in completion() })
        present(alert, animated: true)
    }
}

final class BlockedMembersViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let accountID: Int
    private let client: NodeSeekUserContentClient
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private var members: [BlockedMember] = []
    private weak var loadingToast: UIView?
    private var task: Task<Void, Never>?

    init(accountID: Int, client: NodeSeekUserContentClient? = nil) {
        self.accountID = accountID
        self.client = client ?? NodeSeekUserContentClient()
        super.init(nibName: nil, bundle: nil)
        title = AccountsL10n.text("黑名单")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        table.dataSource = self
        table.delegate = self
        table.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(table)
        NSLayoutConstraint.activate([
            table.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            table.topAnchor.constraint(equalTo: view.topAnchor),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        NotificationCenter.default.addObserver(self, selector: #selector(blockListChanged(_:)), name: .nodeSeekBlockListChanged, object: nil)
        reload()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        NotificationCenter.default.removeObserver(self, name: .nodeSeekBlockListChanged, object: nil)
        task?.cancel()
        if let loadingToast { BottomToast.dismiss(loadingToast) }
    }

    @objc private func blockListChanged(_ notification: Notification) {
        guard notification.object as? Int == accountID else { return }
        // 本页只会解除拉黑，按缓存删掉对应行，避免整表清空再加载造成闪烁。
        let removed = members.indices.filter { client.cachedBlockStatus(members[$0].id, for: accountID) == false }
        guard !removed.isEmpty else { return }
        for index in removed.reversed() { members.remove(at: index) }
        table.deleteRows(at: removed.map { IndexPath(row: $0, section: 0) }, with: .automatic)
        updateEmptyState()
    }

    private func updateEmptyState() {
        guard members.isEmpty else { return table.backgroundView = nil }
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.text = AccountsL10n.text("黑名单为空")
        table.backgroundView = label
    }

    @objc private func reload() {
        load(showProgress: true)
    }

    private func load(showProgress: Bool) {
        task?.cancel()
        if let loadingToast { BottomToast.dismiss(loadingToast) }
        members = []
        table.reloadData()
        table.backgroundView = nil
        let progress = showProgress ? BottomToast.show(AccountsL10n.text("正在加载黑名单…"),
                                                       style: .progress, in: view, duration: 60) : nil
        loadingToast = progress
        task = Task {
            defer { if let progress { BottomToast.dismiss(progress) } }
            do {
                let rows = try await client.loadBlockedMembers(for: accountID)
                try Task.checkCancellation()
                members = rows
                table.reloadData()
                updateEmptyState()
            } catch {
                guard !Task.isCancelled else { return }
                let retry = UIButton(type: .system)
                retry.setTitle(AccountsL10n.format("%@，点按重试", error.localizedDescription), for: .normal)
                retry.titleLabel?.numberOfLines = 0
                retry.addTarget(self, action: #selector(reload), for: .touchUpInside)
                table.backgroundView = retry
            }
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { members.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.textLabel?.text = members[indexPath.row].name
        cell.detailTextLabel?.text = AccountsL10n.text("解除拉黑")
        cell.accessibilityTraits.insert(.button)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard members.indices.contains(indexPath.row) else { return }
        let member = members[indexPath.row]
        UserAvatarMenu.confirm(false, member: member, accountID: accountID, client: client, presenter: self)
    }
}
