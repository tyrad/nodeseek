//
//  UserCollectionsViewController.swift
//  nodeseek
//
//  Created by Codex on 2026/5/11.
//

import AsyncDisplayKit
import UIKit

@MainActor
final class UserCollectionsViewController: UIViewController {
    private let tableNode = ASTableNode(style: .plain)
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
    private var lastBatchFetchRequestedCount: Int?
    private let skeletonRowCount = 9
    /// 只有自己的收藏能取消；看别人的收藏时不提供滑动操作。
    private var canRemove = false
    private var removingPostIDs: Set<Int> = []
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
            tableNode.reloadData()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupUI() {
        view.backgroundColor = .systemGroupedBackground
        tableNode.dataSource = self
        tableNode.delegate = self
        tableNode.leadingScreensForBatching = 2
        // 行是独立卡片，不用分隔线；顶部留白让第一张卡片不贴着导航栏
        tableNode.view.separatorStyle = .none
        tableNode.view.tableHeaderView = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 6))
        tableNode.view.tableFooterView = footerView
        tableNode.view.backgroundColor = .systemGroupedBackground
        refreshControl.addTarget(self, action: #selector(refreshTriggered), for: .valueChanged)
        tableNode.view.refreshControl = refreshControl
        tableNode.view.translatesAutoresizingMaskIntoConstraints = false
        errorView.onRetry = { [weak self] in
            self?.loadFirstPage()
        }

        view.addSubview(tableNode.view)
        view.addSubview(errorView)
        view.addSubview(emptyView)
        NSLayoutConstraint.activate([
            tableNode.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableNode.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableNode.view.topAnchor.constraint(equalTo: view.topAnchor),
            tableNode.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            errorView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            errorView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            errorView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            errorView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),

            emptyView.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            emptyView.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor, constant: -24),
            emptyView.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 40),
            emptyView.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -40)
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
        showSkeleton()

        Task { [weak self] in
            guard let self else { return }
            do {
                let uid = try await resolveUID()
                let loaded = try await client.loadCollections(page: 1, uid: uid)
                let currentUID = await currentAccountStore.snapshot()?.account.nodeSeekUID
                guard generation == requestGeneration else { return }
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

    private func finishFirstPage(records: [UserCollectionRecord]) {
        self.records = records
        displayMode = .content
        isLoadingFirstPage = false
        isLoadingMore = false
        hasMorePages = !records.isEmpty
        errorView.isHidden = true
        emptyView.isHidden = !records.isEmpty
        refreshControl.endRefreshing()
        footerView.stopAnimating()
        tableNode.reloadData()
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
        records.append(contentsOf: loaded.filter { item in
            records.contains { $0.postID == item.postID } == false
        })
        let newCount = records.count
        guard newCount > oldCount else { return }
        let indexPaths = (oldCount..<newCount).map { IndexPath(row: $0, section: 0) }
        tableNode.performBatch(animated: false) { [weak self] in
            self?.tableNode.insertRows(at: indexPaths, with: .none)
        }
    }

    private func showSkeleton() {
        displayMode = .skeleton
        records = []
        errorView.isHidden = true
        emptyView.isHidden = true
        footerView.stopAnimating()
        tableNode.reloadData()
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
        tableNode.reloadData()
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
        tableNode.reloadData()
    }

    /// 接口较慢，提交期间显示加载提示；确认成功后再移除这一行，失败时卡片留在原处。
    private func removeRecord(postID: Int) {
        guard !removingPostIDs.contains(postID) else { return }
        removingPostIDs.insert(postID)
        let generation = requestGeneration
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
                // 期间刷新过列表时按帖子 ID 重新定位，找不到说明新列表里已经没有它
                guard generation == requestGeneration,
                      displayMode == .content,
                      let row = records.firstIndex(where: { $0.postID == postID }) else { return }
                records.remove(at: row)
                tableNode.performBatch(animated: true, updates: { [weak self] in
                    self?.tableNode.deleteRows(at: [IndexPath(row: row, section: 0)], with: .automatic)
                }, completion: nil)
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

extension UserCollectionsViewController: ASTableDataSource {
    func tableNode(_ tableNode: ASTableNode, numberOfRowsInSection section: Int) -> Int {
        switch displayMode {
        case .content:
            return records.count
        case .skeleton:
            return skeletonRowCount
        case .firstPageError:
            return 0
        }
    }

    func tableNode(_ tableNode: ASTableNode, nodeBlockForRowAt indexPath: IndexPath) -> ASCellNodeBlock {
        switch displayMode {
        case .content:
            let record = records[indexPath.row]
            let traits = traitCollection
            return {
                UserCollectionCellNode(record: record, traits: traits)
            }
        case .skeleton:
            return {
                UserContentSkeletonCellNode(cardStyle: true)
            }
        case .firstPageError:
            return {
                ASCellNode()
            }
        }
    }
}

extension UserCollectionsViewController: ASTableDelegate {
    func tableNode(_ tableNode: ASTableNode, didSelectRowAt indexPath: IndexPath) {
        guard displayMode == .content, records.indices.contains(indexPath.row) else { return }
        tableNode.deselectRow(at: indexPath, animated: true)
        openRecord(records[indexPath.row])
    }

    func shouldBatchFetch(for tableNode: ASTableNode) -> Bool {
        displayMode == .content
            && !records.isEmpty
            && lastBatchFetchRequestedCount != records.count
    }

    func tableNode(_ tableNode: ASTableNode, willBeginBatchFetchWith context: ASBatchContext) {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                context.completeBatchFetching(true)
                return
            }
            self.lastBatchFetchRequestedCount = self.records.count
            self.loadMoreIfNeeded()
            context.completeBatchFetching(true)
        }
    }
}

// ASTableNode 会把 UITableViewDelegate 的方法转给这里
extension UserCollectionsViewController {
    /// 左滑取消收藏，接口确认后再移除这一行。
    @objc(tableView:trailingSwipeActionsConfigurationForRowAtIndexPath:)
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard canRemove, displayMode == .content, records.indices.contains(indexPath.row) else { return nil }
        let postID = records[indexPath.row].postID
        let action = UIContextualAction(style: .destructive, title: UserContentL10n.text("取消收藏")) { [weak self] _, _, done in
            // 先收起滑动按钮，结果由加载提示反馈，不让按钮停在原处等接口
            done(false)
            self?.removeRecord(postID: postID)
        }
        action.image = UIImage(systemName: "star.slash")
        let configuration = UISwipeActionsConfiguration(actions: [action])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }
}
