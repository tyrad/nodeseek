//
//  UserCommentsViewController.swift
//  nodeseek
//
//  Created by Codex on 2026/5/11.
//

import UIKit

@MainActor
final class UserCommentsViewController: UIViewController {
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let refreshControl = UIRefreshControl()
    private let footerView = UserContentFooterView()
    private let errorView = UserContentErrorView(accessibilityIdentifier: "user-comments-error-view")
    private let client: NodeSeekUserContentClient
    private let currentAccountStore: CurrentAccountStore
    private var records: [UserCommentRecord] = [] {
        didSet { groups = UserCommentGroup.grouped(records) }
    }
    private var groups: [UserCommentGroup] = []
    private var displayMode: UserContentDisplayMode = .content
    private let targetUID: Int?
    private var uid: Int?
    private var nextPage = 2
    private var hasMorePages = true
    private var requestGeneration = 0
    private var isLoadingFirstPage = false
    private var isLoadingMore = false
    private var hasUserStartedScrolling = false
    private var lastBatchFetchRequestedCount: Int?
    private let skeletonRowCount = 9
    var onSelectPost: ((PostSummary, Int, String?) -> Void)?

    /// 不传 uid 时取当前账号，供侧边栏「我的」入口使用
    init(
        uid: Int? = nil,
        title: String = "评论",
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

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection),
           isViewLoaded, displayMode == .content {
            tableView.reloadData()
        }
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
        tableView.register(UserCommentGroupCell.self, forCellReuseIdentifier: "content")
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
        hasMorePages = true
        nextPage = 2
        lastBatchFetchRequestedCount = nil
        hasUserStartedScrolling = false
        showSkeleton()

        Task { [weak self] in
            guard let self else { return }
            do {
                let uid = try await resolveUID()
                let loaded = try await client.loadComments(uid: uid, page: 1)
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
                let loaded = try await client.loadComments(uid: uid, page: page)
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

    private func finishFirstPage(records: [UserCommentRecord]) {
        self.records = records
        displayMode = .content
        isLoadingFirstPage = false
        isLoadingMore = false
        hasMorePages = !records.isEmpty
        errorView.isHidden = true
        refreshControl.endRefreshing()
        footerView.stopAnimating()
        tableView.reloadData()
    }

    private func finishLoadMore(records loaded: [UserCommentRecord], page: Int) {
        isLoadingMore = false
        footerView.stopAnimating()
        guard !loaded.isEmpty else {
            hasMorePages = false
            return
        }
        nextPage = page + 1
        let oldGroups = groups
        let oldCount = records.count
        var known = Dictionary(grouping: records, by: \.postID).mapValues { Set($0.map(\.floorID)) }
        records.append(contentsOf: loaded.filter { known[$0.postID, default: []].insert($0.floorID).inserted })
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
        // 保留未变化的节点，避免分页时重建整张列表导致可见内容跳动。
        let changed = oldGroups.indices.compactMap { index -> IndexPath? in
            oldGroups[index] != groups[index] ? IndexPath(row: index, section: 0) : nil
        }
        let inserted = (oldGroups.count..<groups.count).map { IndexPath(row: $0, section: 0) }
        tableView.performBatchUpdates {
            tableView.reloadRows(at: changed, with: .none)
            tableView.insertRows(at: inserted, with: .none)
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

    private func openPost(_ record: UserCommentRecord) {
        let post = UserContentPostSummaryFactory.postSummary(id: record.postID, title: record.title)
        onSelectPost?(post, 1, nil)
    }

    private func openComment(_ record: UserCommentRecord) {
        let post = UserContentPostSummaryFactory.postSummary(id: record.postID, title: record.title)
        onSelectPost?(post, record.commentPage, record.anchorID)
    }
}

extension UserCommentsViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch displayMode {
        case .content:
            return groups.count
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
        let cell = tableView.dequeueReusableCell(withIdentifier: "content", for: indexPath) as! UserCommentGroupCell
        let group = groups[indexPath.row]
        cell.configure(group, onOpenPost: { [weak self] in
            if let first = group.comments.first { self?.openPost(first) }
        }) { [weak self] in self?.openComment($0) }
        return cell
    }
}

extension UserCommentsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard displayMode == .content, groups.indices.contains(indexPath.row) else { return }
        tableView.deselectRow(at: indexPath, animated: true)
        if let record = groups[indexPath.row].comments.first {
            openPost(record)
        }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        hasUserStartedScrolling = true
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard hasUserStartedScrolling, displayMode == .content, !isLoadingMore, !isLoadingFirstPage, hasMorePages,
              scrollView.contentOffset.y + scrollView.bounds.height * 2 >= scrollView.contentSize.height,
              lastBatchFetchRequestedCount != records.count else { return }
        lastBatchFetchRequestedCount = records.count
        loadMoreIfNeeded()
    }
}
