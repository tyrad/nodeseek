import UIKit

final class PostListSortSettingsViewController: UITableViewController {
    private let store: PostListSortPreferenceStoring

    init(store: PostListSortPreferenceStoring = PostListSortPreferenceStore.shared) {
        self.store = store
        super.init(style: .insetGrouped)
        title = NSLocalizedString("sort.title", tableName: "PostList", comment: "")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.backgroundColor = .systemGroupedBackground
        // 黑白主题：勾选标记等跟随 tableView 着色，不用系统蓝
        tableView.tintColor = .label
        tableView.accessibilityIdentifier = "settings-post-list-sort-table-view"
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 1 : PostListSortMode.allCases.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell()
        var content = cell.defaultContentConfiguration()
        content.textProperties.color = ReadingColors.text
        if indexPath.section == 0 {
            content.text = NSLocalizedString("sort.show", tableName: "PostList", comment: "")
            let toggle = UISwitch()
            toggle.accessibilityLabel = content.text
            toggle.accessibilityIdentifier = "settings-post-list-sort-show-switch"
            toggle.isOn = store.showsHomeControl
            toggle.addTarget(self, action: #selector(visibilityChanged(_:)), for: .valueChanged)
            cell.accessoryView = toggle
            cell.selectionStyle = .none
            cell.accessibilityIdentifier = "settings-post-list-sort-show-cell"
        } else {
            let mode = PostListSortMode.allCases[indexPath.row]
            content.text = mode.accessibilityTitle
            cell.accessoryType = mode == store.sortMode ? .checkmark : .none
            if mode == store.sortMode { cell.accessibilityTraits.insert(.selected) }
            cell.accessibilityIdentifier = "settings-post-list-sort-mode-\(mode.rawValue)"
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 1 else { return }
        store.sortMode = PostListSortMode.allCases[indexPath.row]
        tableView.reloadSections(IndexSet(integer: 1), with: .none)
    }

    @objc private func visibilityChanged(_ sender: UISwitch) {
        store.showsHomeControl = sender.isOn
    }
}
