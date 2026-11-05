//
//  SearchUserResultsView.swift
//  nodeseek
//
//  Created by Claude on 2026/11/2.
//

import UIKit

protocol UserSearchLoading {
    func findMembers(keyword: String) async throws -> [UserConnectionRecord]
}

extension NodeSeekUserContentClient: UserSearchLoading {}

/// 搜一搜「用户」Tab 的结果列表，卡片样式复用关注列表的单元格。
@MainActor
final class SearchUserResultsView: UIView, UITableViewDataSource, UITableViewDelegate {
    enum State: Equatable {
        case idle
        case loading
        case loaded([UserConnectionRecord])
        case failed(String)
    }

    var onSelectUser: ((UserConnectionRecord) -> Void)?

    private(set) var state: State = .idle {
        didSet { render() }
    }

    private var records: [UserConnectionRecord] {
        if case .loaded(let records) = state { return records }
        return []
    }

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let messageLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.systemBackground
        accessibilityIdentifier = "search-user-results"

        tableView.backgroundColor = UIColor.systemBackground
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 116
        tableView.keyboardDismissMode = .onDrag
        tableView.register(UserConnectionCell.self, forCellReuseIdentifier: "member")
        tableView.accessibilityIdentifier = "search-user-results-table"
        tableView.translatesAutoresizingMaskIntoConstraints = false

        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.accessibilityIdentifier = "search-user-results-message"
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        activityIndicator.hidesWhenStopped = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false

        addSubview(tableView)
        addSubview(messageLabel)
        addSubview(activityIndicator)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: topAnchor),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor),

            messageLabel.topAnchor.constraint(equalTo: topAnchor, constant: 48),
            messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),
            messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -32),

            activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            activityIndicator.topAnchor.constraint(equalTo: topAnchor, constant: 48)
        ])
        render()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setState(_ state: State) {
        self.state = state
    }

    private func render() {
        tableView.reloadData()
        switch state {
        case .idle:
            activityIndicator.stopAnimating()
            messageLabel.text = nil
        case .loading:
            activityIndicator.startAnimating()
            messageLabel.text = nil
        case .loaded(let records):
            activityIndicator.stopAnimating()
            messageLabel.text = records.isEmpty ? "未找到用户，换个关键词试试" : nil
            if !records.isEmpty {
                tableView.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top), animated: false)
            }
        case .failed(let message):
            activityIndicator.stopAnimating()
            messageLabel.text = message
        }
        messageLabel.isHidden = messageLabel.text == nil
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        records.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "member", for: indexPath) as! UserConnectionCell
        // 搜索结果只负责找人，关注操作留给个人页，避免这里再维护一套关注状态
        cell.configure(records[indexPath.row], showsFollowButton: false)
        cell.backgroundColor = UIColor.systemBackground
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard records.indices.contains(indexPath.row) else { return }
        onSelectUser?(records[indexPath.row])
    }
}
