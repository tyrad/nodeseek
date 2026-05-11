//
//  UserCommentsViewController.swift
//  nodeseek
//
//  Created by Codex on 2026/5/11.
//

import AsyncDisplayKit
import UIKit

@MainActor
final class UserCommentsViewController: UIViewController {
    private let tableNode = ASTableNode(style: .plain)
    private let refreshControl = UIRefreshControl()
    private let footerView = UserContentFooterView()
    private let errorView = UserContentErrorView(accessibilityIdentifier: "user-comments-error-view")
    private let client: NodeSeekUserContentClient
    private let currentAccountStore: CurrentAccountStore
    private var records: [UserCommentRecord] = []
    private var displayMode: UserContentDisplayMode = .content
    private var uid: Int?
    private var nextPage = 2
    private var hasMorePages = true
    private var isLoadingFirstPage = false
    private var isLoadingMore = false
    private var lastBatchFetchRequestedCount: Int?
    private let skeletonRowCount = 9
    var onSelectPost: ((PostSummary, Int, String?) -> Void)?

    init(
        client: NodeSeekUserContentClient? = nil,
        currentAccountStore: CurrentAccountStore = .shared
    ) {
        self.client = client ?? NodeSeekUserContentClient()
        self.currentAccountStore = currentAccountStore
        super.init(nibName: nil, bundle: nil)
        title = "评论"
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
        view.backgroundColor = .systemBackground
        tableNode.dataSource = self
        tableNode.delegate = self
        tableNode.leadingScreensForBatching = 2
        tableNode.view.separatorStyle = .singleLine
        tableNode.view.tableFooterView = footerView
        tableNode.view.backgroundColor = .systemBackground
        refreshControl.addTarget(self, action: #selector(refreshTriggered), for: .valueChanged)
        tableNode.view.refreshControl = refreshControl
        tableNode.view.translatesAutoresizingMaskIntoConstraints = false
        errorView.onRetry = { [weak self] in
            self?.loadFirstPage()
        }

        view.addSubview(tableNode.view)
        view.addSubview(errorView)
        NSLayoutConstraint.activate([
            tableNode.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableNode.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableNode.view.topAnchor.constraint(equalTo: view.topAnchor),
            tableNode.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            errorView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            errorView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            errorView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            errorView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32)
        ])
    }

    private func loadFirstPage() {
        guard !isLoadingFirstPage else { return }
        isLoadingFirstPage = true
        hasMorePages = true
        nextPage = 2
        lastBatchFetchRequestedCount = nil
        showSkeleton()

        Task { [weak self] in
            guard let self else { return }
            do {
                let uid = try await resolveUID()
                let loaded = try await client.loadComments(uid: uid, page: 1)
                self.uid = uid
                finishFirstPage(records: loaded)
            } catch {
                showFirstPageError(error.localizedDescription)
            }
        }
    }

    private func loadMoreIfNeeded() {
        guard let uid else { return }
        guard !records.isEmpty, hasMorePages, !isLoadingMore, !isLoadingFirstPage else { return }
        isLoadingMore = true
        footerView.startAnimating()
        let page = nextPage
        Task { [weak self] in
            guard let self else { return }
            do {
                let loaded = try await client.loadComments(uid: uid, page: page)
                finishLoadMore(records: loaded, page: page)
            } catch {
                isLoadingMore = false
                footerView.stopAnimating()
            }
        }
    }

    private func resolveUID() async throws -> Int {
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
        tableNode.reloadData()
    }

    private func finishLoadMore(records loaded: [UserCommentRecord], page: Int) {
        isLoadingMore = false
        footerView.stopAnimating()
        guard !loaded.isEmpty else {
            hasMorePages = false
            return
        }
        nextPage = page + 1
        let oldCount = records.count
        records.append(contentsOf: loaded.filter { item in
            records.contains { $0.postID == item.postID && $0.floorID == item.floorID } == false
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

    private func openPost(_ record: UserCommentRecord) {
        let post = UserContentPostSummaryFactory.postSummary(id: record.postID, title: record.title)
        onSelectPost?(post, 1, nil)
    }

    private func openComment(_ record: UserCommentRecord) {
        let post = UserContentPostSummaryFactory.postSummary(id: record.postID, title: record.title)
        onSelectPost?(post, record.commentPage, record.anchorID)
    }
}

extension UserCommentsViewController: ASTableDataSource {
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
            return { [weak self] in
                UserCommentCellNode(
                    record: record,
                    onOpenComment: { [weak self] in self?.openComment(record) }
                )
            }
        case .skeleton:
            return {
                UserContentSkeletonCellNode()
            }
        case .firstPageError:
            return {
                ASCellNode()
            }
        }
    }
}

extension UserCommentsViewController: ASTableDelegate {
    func tableNode(_ tableNode: ASTableNode, didSelectRowAt indexPath: IndexPath) {
        guard displayMode == .content, records.indices.contains(indexPath.row) else { return }
        tableNode.deselectRow(at: indexPath, animated: true)
        openPost(records[indexPath.row])
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
