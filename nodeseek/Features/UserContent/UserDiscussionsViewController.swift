//
//  UserDiscussionsViewController.swift
//  nodeseek
//
//  Created by Codex on 2026/5/11.
//

import UIKit

@MainActor
final class UserDiscussionsViewController: UIViewController {
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let refreshControl = UIRefreshControl()
    private let footerView = UserContentFooterView()
    private let errorView = UserContentErrorView(accessibilityIdentifier: "user-discussions-error-view")
    private let client: NodeSeekUserContentClient
    private let currentAccountStore: CurrentAccountStore
    private var records: [UserDiscussionRecord] = []
    private var displayMode: UserContentDisplayMode = .content
    private let targetUID: Int?
    private var uid: Int?
    private var nextPage = 2
    private var hasMorePages = true
    private var requestGeneration = 0
    private var isLoadingFirstPage = false
    private var isRefreshing = false
    private var isLoadingMore = false
    private var lastBatchFetchRequestedCount: Int?
    private let skeletonRowCount = 9
    var onSelectPost: ((PostSummary, Int, String?) -> Void)?

    /// 不传 uid 时取当前账号，供侧边栏「我的」入口使用
    init(
        uid: Int? = nil,
        title: String = "帖子",
        client: NodeSeekUserContentClient? = nil,
        currentAccountStore: CurrentAccountStore = .shared
    ) {
        self.targetUID = uid
        self.client = client ?? NodeSeekUserContentClient()
        self.currentAccountStore = currentAccountStore
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        observeTextSizeChanges()
        loadFirstPage()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupUI() {
        view.backgroundColor = UIColor.systemBackground
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "content")
        tableView.register(UserContentSkeletonCell.self, forCellReuseIdentifier: "skeleton")
        tableView.separatorStyle = .singleLine
        tableView.tableFooterView = footerView
        tableView.backgroundColor = UIColor.systemBackground
        refreshControl.addTarget(self, action: #selector(refreshTriggered), for: .valueChanged)
        tableView.refreshControl = refreshControl
        tableView.translatesAutoresizingMaskIntoConstraints = false
        errorView.onRetry = { [weak self] in
            self?.loadFirstPage()
        }

        view.addSubview(tableView)
        view.addSubview(errorView)
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            errorView.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            errorView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            errorView.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 32),
            errorView.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -32)
        ])
    }

    private func loadFirstPage() {
        guard !isLoadingFirstPage else { return }
        requestGeneration += 1
        let generation = requestGeneration
        isLoadingMore = false
        isLoadingFirstPage = true
        isRefreshing = false
        hasMorePages = true
        nextPage = 2
        lastBatchFetchRequestedCount = nil
        showSkeleton()

        Task { [weak self] in
            guard let self else { return }
            do {
                let uid = try await resolveUID()
                let loaded = try await client.loadDiscussions(uid: uid, page: 1)
                guard generation == requestGeneration else { return }
                self.uid = uid
                finishFirstPage(records: loaded)
            } catch {
                guard generation == requestGeneration else { return }
                showFirstPageError(error.localizedDescription)
            }
        }
    }

    private func loadMoreIfNeeded() {
        guard let uid else { return }
        guard !records.isEmpty, hasMorePages, !isLoadingMore, !isLoadingFirstPage else { return }
        isLoadingMore = true
        footerView.startAnimating()
        let generation = requestGeneration
        let page = nextPage
        Task { [weak self] in
            guard let self else { return }
            do {
                let loaded = try await client.loadDiscussions(uid: uid, page: page)
                guard generation == requestGeneration else { return }
                finishLoadMore(records: loaded, page: page)
            } catch {
                guard generation == requestGeneration else { return }
                isLoadingMore = false
                lastBatchFetchRequestedCount = nil
                footerView.stopAnimating()
            }
        }
    }

    private func resolveUID() async throws -> Int {
        if let targetUID { return targetUID }
        guard let snapshot = await currentAccountStore.snapshot(),
              let uid = snapshot.account.nodeSeekUID else {
            throw UserContentViewError.missingUID
        }
        return uid
    }

    private func finishFirstPage(records: [UserDiscussionRecord]) {
        self.records = records
        displayMode = .content
        isLoadingFirstPage = false
        isRefreshing = false
        isLoadingMore = false
        hasMorePages = !records.isEmpty
        errorView.isHidden = true
        refreshControl.endRefreshing()
        footerView.stopAnimating()
        tableView.reloadData()
    }

    private func finishLoadMore(records loaded: [UserDiscussionRecord], page: Int) {
        isLoadingMore = false
        footerView.stopAnimating()
        guard !loaded.isEmpty else {
            hasMorePages = false
            return
        }
        nextPage = page + 1
        let oldCount = records.count
        var known = Set(records.map(\.postID))
        records.append(contentsOf: loaded.filter { known.insert($0.postID).inserted })
        let newCount = records.count
        guard newCount > oldCount else {
            lastBatchFetchRequestedCount = nil
            return
        }
        // 离屏时 UITableView 可能尚未读取上一次 reload 的行数，直接同步当前数据。
        guard tableView.window != nil else {
            tableView.reloadData()
            return
        }
        let indexPaths = (oldCount..<newCount).map { IndexPath(row: $0, section: 0) }
        tableView.performBatchUpdates {
            tableView.insertRows(at: indexPaths, with: .none)
        }
    }

    private func showSkeleton() {
        displayMode = .skeleton
        records = []
        errorView.isHidden = true
        footerView.stopAnimating()
        tableView.reloadData()
    }

    private func showFirstPageError(_ message: String) {
        displayMode = .firstPageError
        records = []
        isLoadingFirstPage = false
        isRefreshing = false
        isLoadingMore = false
        refreshControl.endRefreshing()
        footerView.stopAnimating()
        errorView.messageLabel.text = message
        errorView.isHidden = false
        tableView.reloadData()
    }

    @objc private func refreshTriggered() {
        guard !isLoadingFirstPage else { return }
        loadFirstPage()
    }

    private func observeTextSizeChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appTextSizeDidChange(_:)),
            name: AppTextSizeSettings.didChangeNotification,
            object: nil
        )
    }

    @objc private func appTextSizeDidChange(_ notification: Notification) {
        guard displayMode == .content else { return }
        tableView.reloadData()
    }

    private func openRecord(_ record: UserDiscussionRecord) {
        let post = UserContentPostSummaryFactory.postSummary(id: record.postID, title: record.title)
        onSelectPost?(post, 1, nil)
    }
}

extension UserDiscussionsViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch displayMode {
        case .content:
            return records.count
        case .skeleton:
            return skeletonRowCount
        case .firstPageError:
            return 0
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard displayMode == .content else {
            return tableView.dequeueReusableCell(withIdentifier: "skeleton", for: indexPath)
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: "content", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = records[indexPath.row].title
        content.textProperties.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: PostListCellStyle.Typography.titleFont, compatibleWith: traitCollection)
        content.textProperties.color = ReadingColors.text
        content.textProperties.numberOfLines = 2
        content.directionalLayoutMargins = .init(top: 13, leading: 18, bottom: 13, trailing: 18)
        cell.contentConfiguration = content
        return cell
    }
}

extension UserDiscussionsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard displayMode == .content, records.indices.contains(indexPath.row) else { return }
        tableView.deselectRow(at: indexPath, animated: true)
        openRecord(records[indexPath.row])
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard displayMode == .content, !isLoadingMore, !isLoadingFirstPage, hasMorePages,
              scrollView.contentOffset.y + scrollView.bounds.height * 2 >= scrollView.contentSize.height,
              lastBatchFetchRequestedCount != records.count else { return }
        lastBatchFetchRequestedCount = records.count
        loadMoreIfNeeded()
    }
}

enum UserContentViewError: LocalizedError {
    case missingUID

    var errorDescription: String? {
        "未获取到账号 UID，请重新登录后再试"
    }
}
