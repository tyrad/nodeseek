//
//  PostCategoryPreferencesViewController.swift
//  nodeseek
//

import UIKit

final class PostCategoryPreferencesViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case visible
        case hidden
        case reset
    }

    private let store: PostCategoryPreferenceStore
    private var visibleCategories: [PostListCategoryItem] = []
    private var hiddenCategories: [PostListCategoryItem] = []

    init(store: PostCategoryPreferenceStore = .shared) {
        self.store = store
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "首页分类"
        tableView.accessibilityIdentifier = "post-category-preferences-table-view"
        tableView.allowsSelectionDuringEditing = true
        navigationItem.rightBarButtonItems = [editButtonItem]
        reloadPreferences()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesDidChange(_:)),
            name: PostCategoryPreferenceStore.didChangeNotification,
            object: store
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .visible:
            return visibleCategories.count
        case .hidden:
            return hiddenCategories.count
        case .reset:
            return 1
        case .none:
            return 0
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .visible:
            return "显示"
        case .hidden:
            return "隐藏"
        case .reset:
            return nil
        case .none:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard Section(rawValue: section) == .visible else { return nil }
        return "拖动可排序，左滑可隐藏；隐藏分类点按后恢复。“全部”始终显示并固定在第一位。"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.textColor = .label
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.numberOfLines = 1

        switch Section(rawValue: indexPath.section) {
        case .visible:
            let category = visibleCategories[indexPath.row]
            cell.textLabel?.text = category.title
            cell.detailTextLabel?.text = detailText(for: category)
            cell.accessibilityIdentifier = "post-category-preferences-visible-cell-\(indexPath.row)"
        case .hidden:
            let category = hiddenCategories[indexPath.row]
            cell.textLabel?.text = category.title
            cell.detailTextLabel?.text = detailText(for: category)
            cell.accessibilityIdentifier = "post-category-preferences-hidden-cell-\(indexPath.row)"
        case .reset:
            cell.textLabel?.text = "恢复默认顺序"
            cell.detailTextLabel?.text = "显示全部分类并恢复默认排序"
            cell.imageView?.image = UIImage(systemName: "arrow.counterclockwise")
            cell.accessibilityIdentifier = "post-category-preferences-reset-cell"
        case .none:
            break
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        Section(rawValue: indexPath.section) == .visible && indexPath.row > 0
    }

    override func tableView(
        _ tableView: UITableView,
        targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
        toProposedIndexPath proposedDestinationIndexPath: IndexPath
    ) -> IndexPath {
        guard Section(rawValue: proposedDestinationIndexPath.section) == .visible else {
            return sourceIndexPath
        }
        guard proposedDestinationIndexPath.row > 0 else {
            return IndexPath(row: 1, section: Section.visible.rawValue)
        }
        return proposedDestinationIndexPath
    }

    override func tableView(
        _ tableView: UITableView,
        moveRowAt sourceIndexPath: IndexPath,
        to destinationIndexPath: IndexPath
    ) {
        guard Section(rawValue: sourceIndexPath.section) == .visible else { return }
        guard Section(rawValue: destinationIndexPath.section) == .visible else { return }
        guard visibleCategories.indices.contains(sourceIndexPath.row) else { return }
        guard sourceIndexPath.row > 0 else { return }
        store.moveVisibleCategory(from: sourceIndexPath.row, to: destinationIndexPath.row)
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        switch Section(rawValue: indexPath.section) {
        case .visible:
            return indexPath.row > 0
        case .hidden:
            return false
        case .reset:
            return false
        case .none:
            return false
        }
    }

    override func tableView(
        _ tableView: UITableView,
        editingStyleForRowAt indexPath: IndexPath
    ) -> UITableViewCell.EditingStyle {
        guard Section(rawValue: indexPath.section) == .visible else { return .none }
        guard indexPath.row > 0 else { return .none }
        return .delete
    }

    override func tableView(
        _ tableView: UITableView,
        titleForDeleteConfirmationButtonForRowAt indexPath: IndexPath
    ) -> String? {
        guard Section(rawValue: indexPath.section) == .visible else { return nil }
        guard indexPath.row > 0 else { return nil }
        return "隐藏"
    }

    override func tableView(
        _ tableView: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        switch (Section(rawValue: indexPath.section), editingStyle) {
        case (.visible, .delete) where visibleCategories.indices.contains(indexPath.row):
            let category = visibleCategories[indexPath.row]
            store.hideCategory(category)
        case (.hidden, .insert) where hiddenCategories.indices.contains(indexPath.row):
            let category = hiddenCategories[indexPath.row]
            store.showCategory(category)
        default:
            break
        }
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard Section(rawValue: indexPath.section) == .visible else { return nil }
        guard visibleCategories.indices.contains(indexPath.row) else { return nil }
        guard indexPath.row > 0 else { return nil }

        let action = UIContextualAction(style: .destructive, title: "隐藏") { [weak self] _, _, completion in
            guard let self else {
                completion(false)
                return
            }
            guard visibleCategories.indices.contains(indexPath.row) else {
                completion(false)
                return
            }
            store.hideCategory(visibleCategories[indexPath.row])
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [action])
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section) {
        case .hidden:
            guard hiddenCategories.indices.contains(indexPath.row) else { return }
            store.showCategory(hiddenCategories[indexPath.row])
        case .reset:
            store.resetToDefault()
        case .visible, .none:
            break
        }
    }

    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        tableView.setEditing(editing, animated: animated)
    }

    private func reloadPreferences() {
        visibleCategories = store.visibleCategoryItems
        hiddenCategories = store.hiddenCategoryItems
        tableView.reloadData()
    }

    @objc private func preferencesDidChange(_ notification: Notification) {
        reloadPreferences()
    }

    private func detailText(for category: PostListCategoryItem) -> String? {
        if category.isAll {
            return "固定第一位"
        }
        return nil
    }
}
