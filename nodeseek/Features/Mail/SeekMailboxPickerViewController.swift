//
//  SeekMailboxPickerViewController.swift
//  nodeseek
//

import UIKit

/// 邮箱超过 5 个时的选择面板：搜索、最近、全部邮箱，再按置顶 → 有未读 → 其他分组。
final class SeekMailboxPickerViewController: UITableViewController {
    private let model: SeekMailInboxModel
    private let onSelect: (Int64?) -> Void
    private let searchBar = UISearchBar()
    private var counts: [Int64: Int] = [:]
    private var sections = SeekMailboxPickerSections()
    private var countsTask: Task<Void, Never>?

    private enum Kind {
        case recents, all, pinned, unread, others
    }

    private var visibleKinds: [Kind] {
        var kinds: [Kind] = []
        if sections.recents.isEmpty == false { kinds.append(.recents) }
        if sections.isSearching == false { kinds.append(.all) }
        if sections.pinned.isEmpty == false { kinds.append(.pinned) }
        if sections.unread.isEmpty == false { kinds.append(.unread) }
        if sections.others.isEmpty == false { kinds.append(.others) }
        return kinds
    }

    init(model: SeekMailInboxModel, onSelect: @escaping (Int64?) -> Void) {
        self.model = model
        self.onSelect = onSelect
        super.init(style: .insetGrouped)
        title = "切换邮箱"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { countsTask?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
        searchBar.placeholder = "按地址或别名搜索"
        searchBar.searchBarStyle = .minimal
        searchBar.autocapitalizationType = .none
        searchBar.autocorrectionType = .no
        searchBar.delegate = self
        searchBar.accessibilityIdentifier = "seek-mail-picker-search"
        searchBar.sizeToFit()
        tableView.tableHeaderView = searchBar
        tableView.keyboardDismissMode = .onDrag
        tableView.accessibilityIdentifier = "seek-mail-picker"
        rebuild()
        // 打开时请求一次未读数，一个请求就能拿到全部邮箱的数量
        countsTask = Task { [weak self] in
            guard let self, let result = try? await model.provider.unreadCounts() else { return }
            counts = result.byMailbox
            rebuild()
        }
    }

    private func rebuild() {
        sections = SeekMailboxPickerSections.make(
            mailboxes: model.mailboxes, names: model.names, counts: counts,
            recentIDs: model.selectionStore.recentMailboxIDs, query: searchBar.text ?? ""
        )
        tableView.reloadData()
    }

    private func rows(for kind: Kind) -> [SeekMailboxPickerSections.Row] {
        switch kind {
        case .recents: return sections.recents
        case .all: return []
        case .pinned: return sections.pinned
        case .unread: return sections.unread
        case .others: return sections.others
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int { visibleKinds.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let kind = visibleKinds[section]
        return kind == .all ? 1 : rows(for: kind).count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch visibleKinds[section] {
        case .recents: return "最近"
        case .all: return nil
        case .pinned: return "置顶"
        case .unread: return "有未读"
        case .others: return sections.isSearching ? "搜索结果" : "其他"
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        var content = UIListContentConfiguration.subtitleCell()
        let kind = visibleKinds[indexPath.section]
        let selectedID = model.selectedMailboxID

        if kind == .all {
            content.text = "全部邮箱"
            content.secondaryText = "\(model.mailboxes.count) 个邮箱"
            content.image = UIImage(systemName: "tray.2")
            cell.accessoryType = selectedID == nil ? .checkmark : .none
            cell.accessibilityIdentifier = "seek-mail-picker-all"
        } else {
            let row = rows(for: kind)[indexPath.row]
            let mailbox = model.mailboxes.first { $0.id == row.mailboxID }
            let display = model.names[row.mailboxID]
            var title = AttributedString(display?.title ?? mailbox?.address ?? "")
            title.foregroundColor = .label
            if let suffix = display?.domainSuffix {
                var domain = AttributedString(suffix)
                domain.foregroundColor = .secondaryLabel
                title += domain
            }
            content.attributedText = NSAttributedString(title)
            content.textProperties.lineBreakMode = .byTruncatingMiddle
            content.textProperties.numberOfLines = 1
            var details: [String] = []
            if display?.hasAlias == true, let address = mailbox?.address { details.append(address) }
            if mailbox?.canSendMail == true { details.append("可发信") }
            content.secondaryText = details.isEmpty ? nil : details.joined(separator: " · ")
            content.secondaryTextProperties.color = .secondaryLabel
            content.secondaryTextProperties.lineBreakMode = .byTruncatingMiddle
            cell.accessibilityIdentifier = "seek-mail-picker-\(row.mailboxID)"
            if row.unreadCount > 0 {
                let badge = UILabel()
                badge.text = "\(row.unreadCount)"
                badge.font = .monospacedDigitSystemFont(ofSize: 15, weight: .regular)
                badge.textColor = .secondaryLabel
                badge.sizeToFit()
                cell.accessoryView = selectedID == row.mailboxID ? nil : badge
            }
            cell.accessoryType = selectedID == row.mailboxID ? .checkmark : .none
        }
        cell.tintColor = .label
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let kind = visibleKinds[indexPath.section]
        let id = kind == .all ? nil : rows(for: kind)[indexPath.row].mailboxID
        onSelect(id)
        dismiss(animated: true)
    }
}

extension SeekMailboxPickerViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        rebuild()
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}
