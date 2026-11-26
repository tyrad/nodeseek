//
//  UserCollectionsViewController.swift
//  nodeseek
//
//  Created by Codex on 2026/5/11.
//

import UIKit

@MainActor
final class UserCollectionsViewController: UIViewController {
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let refreshControl = UIRefreshControl()
    private let footerView = UserContentFooterView()
    private let errorView = UserContentErrorView(accessibilityIdentifier: "user-collections-error-view")
    private let emptyView = UserContentEmptyView(
        symbolName: "star",
        title: UserContentL10n.text("还没有收藏"),
        message: UserContentL10n.text("在帖子页点「收藏」，之后可以在这里找到。"),
        accessibilityIdentifier: "user-collections-empty-view"
    )
    private let client: NodeSeekUserContentClient
    private let collectionSubmitter: PostCollectionSubmitting
    private let currentAccountStore: CurrentAccountStore
    private var records: [UserCollectionRecord] = []
    private var displayMode: UserContentDisplayMode = .content
    private let targetUID: Int?
    private var uid: Int?
    private var nextPage = 2
    private var hasMorePages = true
    private var requestGeneration = 0
    private var isLoadingFirstPage = false
    private var isLoadingMore = false
    private let paginationButton = UIButton(type: .system)
    private let skeletonRowCount = 9
    /// 只有自己的收藏能取消；看别人的收藏时不提供滑动操作。
    private var canRemove = false
    private var removingPostIDs: Set<Int> = []
    // 本轮刷新或分页返回的快照可能早于取消收藏成功的时间。
    private var removedSinceRefresh: Set<Int> = []
    var onSelectPost: ((PostSummary, Int, String?) -> Void)?

    /// 不传 uid 时取当前账号，供侧边栏「我的」入口使用
    init(
        uid: Int? = nil,
        title: String = "收藏",
        client: NodeSeekUserContentClient? = nil,
        currentAccountStore: CurrentAccountStore = .shared,
        collectionSubmitter: PostCollectionSubmitting? = nil
    ) {
        self.targetUID = uid
        self.client = client ?? NodeSeekUserContentClient()
        self.collectionSubmitter = collectionSubmitter ?? NodeSeekPostCollectionSubmitter()
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
        view.backgroundColor = .systemGroupedBackground
        tableView.dataSource = self
        tableView.delegate = self
        tableView.estimatedRowHeight = 68
        tableView.rowHeight = UITableView.automaticDimension
        tableView.register(UserCollectionCell.self, forCellReuseIdentifier: "collection")
        tableView.register(UserCollectionSkeletonCell.self, forCellReuseIdentifier: "skeleton")
        paginationButton.configuration = .plain()
        paginationButton.frame.size.height = 56
        paginationButton.addAction(UIAction { [weak self] _ in self?.loadMoreIfNeeded() }, for: .touchUpInside)
        // 行是独立卡片，不用分隔线；顶部留白让第一张卡片不贴着导航栏
        tableView.separatorStyle = .none
        tableView.tableHeaderView = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 6))
        tableView.tableFooterView = footerView
        tableView.backgroundColor = .systemGroupedBackground
        refreshControl.addTarget(self, action: #selector(refreshTriggered), for: .valueChanged)
        tableView.refreshControl = refreshControl
        tableView.translatesAutoresizingMaskIntoConstraints = false
        errorView.onRetry = { [weak self] in
            self?.loadFirstPage()
        }

        view.addSubview(tableView)
        view.addSubview(errorView)
        view.addSubview(emptyView)
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            errorView.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            errorView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            errorView.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 32),
            errorView.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -32),

            emptyView.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            emptyView.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor, constant: -24),
            emptyView.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 40),
            emptyView.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -40)
        ])
    }

    private func loadFirstPage() {
        guard !isLoadingFirstPage else { return }
        removedSinceRefresh.removeAll()
        requestGeneration += 1
        let generation = requestGeneration
        isLoadingMore = false
        isLoadingFirstPage = true
        hasMorePages = true
        nextPage = 2
        tableView.tableFooterView = footerView
        showSkeleton()

        Task { [weak self] in
            guard let self else { return }
            do {
                let uid = try await resolveUID()
                let loaded = try await client.loadCollections(page: 1, uid: uid)
                let currentUID = await currentAccountStore.snapshot()?.account.nodeSeekUID
                guard generation == requestGeneration else { return }
                if self.uid != uid { removedSinceRefresh.removeAll() }
                self.uid = uid
                canRemove = currentUID == uid
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
        tableView.tableFooterView = footerView
        footerView.startAnimating()
        let generation = requestGeneration
        let page = nextPage
        Task { [weak self] in
            guard let self else { return }
            do {
                let loaded = try await client.loadCollections(page: page, uid: uid)
                guard generation == requestGeneration else { return }
                finishLoadMore(records: loaded, page: page)
            } catch {
                guard generation == requestGeneration else { return }
                isLoadingMore = false
                footerView.stopAnimating()
                paginationButton.configuration?.title = UserContentL10n.text("重试")
                tableView.tableFooterView = paginationButton
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

    private func finishFirstPage(records loaded: [UserCollectionRecord]) {
        var knownIDs = removedSinceRefresh
        records = loaded.filter { knownIDs.insert($0.postID).inserted }
        displayMode = .content
        isLoadingFirstPage = false
        isLoadingMore = false
        hasMorePages = !records.isEmpty
        errorView.isHidden = true
        emptyView.isHidden = !records.isEmpty
        refreshControl.endRefreshing()
        footerView.stopAnimating()
        tableView.reloadData()
        if records.isEmpty, !loaded.isEmpty { loadFirstPage() }
    }

    private func finishLoadMore(records loaded: [UserCollectionRecord], page: Int) {
        isLoadingMore = false
        footerView.stopAnimating()
        guard !loaded.isEmpty else {
            hasMorePages = false
            return
        }
        nextPage = page + 1
        let oldCount = records.count
        var knownIDs = removedSinceRefresh.union(records.map(\.postID))
        records.append(contentsOf: loaded.filter { knownIDs.insert($0.postID).inserted })
        let newCount = records.count
        guard newCount > oldCount else {
            paginationButton.configuration?.title = UserContentL10n.text("加载更多")
            tableView.tableFooterView = paginationButton
            return
        }
        // 离屏时 UITableView 可能尚未读取上一次 reload 的行数，直接同步当前数据。
        guard tableView.window != nil else {
            tableView.reloadData()
            return
        }
        let indexPaths = (oldCount..<newCount).map { IndexPath(row: $0, section: 0) }
        tableView.insertRows(at: indexPaths, with: .none)
    }

    private func showSkeleton() {
        displayMode = .skeleton
        records = []
        errorView.isHidden = true
        emptyView.isHidden = true
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
        emptyView.isHidden = true
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

    /// 接口较慢，提交期间显示加载提示；确认成功后再移除这一行，失败时卡片留在原处。
    private func removeRecord(postID: Int, ownerUID: Int) {
        guard uid == ownerUID, canRemove, !removingPostIDs.contains(postID) else { return }
        removingPostIDs.insert(postID)
        let progressToast = BottomToast.show(
            UserContentL10n.text("正在取消收藏…"),
            style: .progress,
            in: view,
            duration: 60
        )
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await collectionSubmitter.removeFavorite(
                    postID: "\(postID)",
                    referer: NodeSeekSite.postURL(id: "\(postID)", page: 1)
                )
                removingPostIDs.remove(postID)
                BottomToast.dismiss(progressToast)
                BottomToast.show(UserContentL10n.text("已取消收藏"), in: view)
                guard uid == ownerUID else { return }
                removedSinceRefresh.insert(postID)
                guard displayMode == .content,
                      let row = records.firstIndex(where: { $0.postID == postID }) else { return }
                records.remove(at: row)
                if tableView.window == nil {
                    tableView.reloadData()
                } else {
                    tableView.deleteRows(at: [IndexPath(row: row, section: 0)], with: .automatic)
                }
                emptyView.isHidden = !records.isEmpty || hasMorePages
                if records.isEmpty, hasMorePages { loadFirstPage() }
            } catch {
                removingPostIDs.remove(postID)
                BottomToast.dismiss(progressToast)
                guard !UserFacingError.isCancellation(error) else { return }
                let message = UserFacingError.message(for: error, fallback: UserContentL10n.text("操作未完成，请刷新后再试。"))
                BottomToast.show(message, style: .failure, in: view, duration: 3)
            }
        }
    }

    private func openRecord(_ record: UserCollectionRecord) {
        let post = UserContentPostSummaryFactory.postSummary(id: record.postID, title: record.title)
        onSelectPost?(post, 1, nil)
    }
}

extension UserCollectionsViewController: UITableViewDataSource {
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
        let cell = tableView.dequeueReusableCell(withIdentifier: "collection", for: indexPath) as! UserCollectionCell
        cell.configure(records[indexPath.row])
        return cell
    }
}

extension UserCollectionsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard displayMode == .content, records.indices.contains(indexPath.row) else { return }
        tableView.deselectRow(at: indexPath, animated: true)
        openRecord(records[indexPath.row])
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard displayMode == .content, indexPath.row >= records.count - 4,
              tableView.tableFooterView !== paginationButton else { return }
        loadMoreIfNeeded()
    }

    /// 左滑取消收藏，接口确认后再移除这一行。
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let uid, canRemove, displayMode == .content, records.indices.contains(indexPath.row) else { return nil }
        let postID = records[indexPath.row].postID
        let action = UIContextualAction(style: .destructive, title: UserContentL10n.text("取消收藏")) { [weak self] _, _, done in
            // 先收起滑动按钮，结果由加载提示反馈，不让按钮停在原处等接口
            done(false)
            self?.removeRecord(postID: postID, ownerUID: uid)
        }
        action.image = UIImage(systemName: "star.slash")
        let configuration = UISwipeActionsConfiguration(actions: [action])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }
}
