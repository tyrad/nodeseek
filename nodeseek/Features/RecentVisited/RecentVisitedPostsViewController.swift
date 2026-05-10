//
//  RecentVisitedPostsViewController.swift
//  nodeseek
//
//  Created by Codex on 2026/5/2.
//

import UIKit

final class RecentVisitedPostsViewController: UITableViewController {
    var onSelectRecord: ((VisitedPostRecord) -> Void)?

    private let visitedStore: VisitedPostStoreProtocol
    private var records: [VisitedPostRecord] = []
    private var hasMoreRecords = true
    private let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter
    }()

    init(visitedStore: VisitedPostStoreProtocol) {
        self.visitedStore = visitedStore
        super.init(style: .plain)
        title = "最近浏览"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        tableView.backgroundColor = .systemBackground
        tableView.register(RecentVisitedPostCell.self, forCellReuseIdentifier: Self.cellIdentifier)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "trash"),
            style: .plain,
            target: self,
            action: #selector(clearButtonTapped)
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = "清扫浏览记录"
        loadNextPageIfNeeded()
        renderEmptyStateIfNeeded()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        records.count
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellIdentifier, for: indexPath) as? RecentVisitedPostCell
            ?? RecentVisitedPostCell(style: .default, reuseIdentifier: Self.cellIdentifier)
        let record = records[indexPath.row]
        cell.configure(
            record: record,
            visitedText: relativeDateFormatter.localizedString(for: record.visitedAt, relativeTo: Date())
        )
        return cell
    }

    override func tableView(
        _ tableView: UITableView,
        willDisplay cell: UITableViewCell,
        forRowAt indexPath: IndexPath
    ) {
        guard indexPath.row >= records.count - 4 else { return }
        loadNextPageIfNeeded()
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard records.indices.contains(indexPath.row) else { return }
        onSelectRecord?(records[indexPath.row])
    }

    @objc private func clearButtonTapped() {
        let alert = UIAlertController(
            title: "清除浏览记录？",
            message: "这会删除所有最近浏览记录，此操作无法撤销。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "清除", style: .destructive) { [weak self] _ in
            self?.clearAllRecords()
        })
        present(alert, animated: true)
    }

    private func clearAllRecords() {
        visitedStore.clearAll()
        records.removeAll()
        hasMoreRecords = false
        tableView.reloadData()
        renderEmptyStateIfNeeded()
    }

    private func loadNextPageIfNeeded() {
        guard hasMoreRecords else { return }
        let nextRecords = visitedStore.recentRecords(offset: records.count, limit: Self.pageSize)
        guard !nextRecords.isEmpty else {
            hasMoreRecords = false
            return
        }

        let startIndex = records.count
        records.append(contentsOf: nextRecords)
        hasMoreRecords = nextRecords.count == Self.pageSize

        guard startIndex > 0 else {
            tableView.reloadData()
            return
        }

        let indexPaths = (startIndex..<records.count).map { IndexPath(row: $0, section: 0) }
        tableView.insertRows(at: indexPaths, with: .automatic)
    }

    private func renderEmptyStateIfNeeded() {
        guard records.isEmpty else {
            tableView.backgroundView = nil
            navigationItem.rightBarButtonItem?.isEnabled = true
            return
        }

        let label = UILabel()
        label.text = "暂无最近浏览"
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.accessibilityIdentifier = "recent-visited-posts-empty-label"
        tableView.backgroundView = label
        navigationItem.rightBarButtonItem?.isEnabled = false
    }

    private static let pageSize = 30
    private static let cellIdentifier = "RecentVisitedPostCell"
}
