//
//  PostTextureListView.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import UIKit
import Foundation

protocol PostTextureListViewDelegate: AnyObject {
    func postTextureListView(_ textureListView: PostTextureListView, didSelectPostAt index: Int)
    func postTextureListViewDidRequestRefresh(_ textureListView: PostTextureListView)
    func postTextureListViewDidRequestFirstPageRetry(_ textureListView: PostTextureListView)
    func postTextureListView(_ textureListView: PostTextureListView, didApproachBottomAt index: Int, totalCount: Int)
}

final class PostTextureListView: UIView {
    private enum DisplayMode {
        case content
        case skeleton
        case firstPageError
    }

    weak var delegate: PostTextureListViewDelegate?

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let refreshControl = UIRefreshControl()
    private var displayMode: DisplayMode = .content
    private var items: [PostListItem] = []
    private let minimumSkeletonRowCount = 8
    private let estimatedSkeletonRowHeight = PostListCellStyle.Avatar.skeletonSize
        + PostListCellStyle.Layout.verticalContentInset * 2
    private let leadingScreensForBatching: CGFloat = 2.0
    private var skeletonRowCount: Int = 8
    private var lastBatchFetchRequestedItemCount: Int?

    private let loadMoreIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    private let errorTitleLabel: UILabel = {
        let label = UILabel()
        label.text = "加载失败"
        label.font = .preferredFont(forTextStyle: .headline)
        label.textColor = .label
        label.textAlignment = .center
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private let errorMessageLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private lazy var retryButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.title = "重试"
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 18)
        let button = UIButton(type: .system)
        button.configuration = configuration
        button.accessibilityIdentifier = "post-list-first-page-retry-button"
        button.addTarget(self, action: #selector(retryFirstPageTapped), for: .touchUpInside)
        return button
    }()

    private lazy var errorStackView: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [errorTitleLabel, errorMessageLabel, retryButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        stack.isHidden = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.accessibilityIdentifier = "post-list-first-page-error"
        return stack
    }()

    private lazy var loadMoreContainer: UIView = {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 56))
        container.addSubview(loadMoreIndicator)
        NSLayoutConstraint.activate([
            loadMoreIndicator.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            loadMoreIndicator.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func setItems(_ items: [PostListItem]) {
        hideErrorView()
        if self.items.count != items.count {
            lastBatchFetchRequestedItemCount = nil
        }
        if displayMode == .content, self.items == items {
            return
        }
        if displayMode != .content {
            self.items = items
            displayMode = .content
            reloadTable()
            return
        }

        if let appendIndexPaths = makeAppendIndexPaths(from: self.items, to: items) {
            self.items = items
            // 分页追加发生在滚动底部，关闭 row 插入动画可以避免调整 contentOffset 时牵动上方内容。
            UIView.performWithoutAnimation {
                tableView.performBatchUpdates {
                    tableView.insertRows(at: appendIndexPaths, with: .none)
                }
            }
            return
        }

        self.items = items
        reloadTable()
    }

    func updateVisitedState(at index: Int, isVisited: Bool) {
        guard displayMode == .content else { return }
        guard items.indices.contains(index) else { return }
        let existing = items[index]
        guard existing.isVisited != isVisited else { return }
        items[index] = PostListItem(post: existing.post, isVisited: isVisited)
        let indexPath = IndexPath(row: index, section: 0)
        if let cell = tableView.cellForRow(at: indexPath) as? PostSummaryCell {
            cell.configure(with: items[index])
        }
    }

    func showLoadingSkeleton() {
        hideErrorView()
        guard displayMode != .skeleton else { return }
        displayMode = .skeleton
        lastBatchFetchRequestedItemCount = nil
        skeletonRowCount = currentSkeletonRowCount()
        hideLoadingMore()
        reloadTable()
    }

    func hideLoadingSkeleton() {
        guard displayMode == .skeleton else { return }
        displayMode = .content
        reloadTable()
    }

    func showFirstPageError(message: String) {
        displayMode = .firstPageError
        items = []
        lastBatchFetchRequestedItemCount = nil
        hideLoadingMore()
        hideRefreshing()
        errorMessageLabel.text = message
        errorStackView.isHidden = false
        reloadTable()
    }

    func hideFirstPageError() {
        guard displayMode == .firstPageError else {
            hideErrorView()
            return
        }
        displayMode = .content
        hideErrorView()
        reloadTable()
    }

    func showLoadingMore() {
        loadMoreIndicator.startAnimating()
    }

    func hideLoadingMore() {
        loadMoreIndicator.stopAnimating()
        lastBatchFetchRequestedItemCount = nil
    }

    func hideRefreshing() {
        refreshControl.endRefreshing()
    }

    func scrollToTop(animated: Bool) {
        tableView.setContentOffset(.zero, animated: animated)
    }

    func refreshVisibleAppearanceForCurrentTraits() {
        tableView.visibleCells.forEach { cell in
            (cell as? PostSummaryCell)?.applyCurrentTheme()
        }
    }

    private func setupUI() {
        PostSummaryText.prewarmSymbolImages()
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(PostSummaryCell.self, forCellReuseIdentifier: PostSummaryCell.reuseIdentifier)
        tableView.register(PostSummarySkeletonCell.self, forCellReuseIdentifier: PostSummarySkeletonCell.reuseIdentifier)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = estimatedSkeletonRowHeight
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .singleLine
        tableView.showsVerticalScrollIndicator = true
        tableView.tableFooterView = loadMoreContainer
        refreshControl.addTarget(self, action: #selector(handlePullToRefresh), for: .valueChanged)
        tableView.refreshControl = refreshControl
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appTextSizeDidChange(_:)),
            name: AppTextSizeSettings.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(specialFollowKeywordsDidChange(_:)),
            name: SpecialFollowKeywordStore.didChangeNotification,
            object: SpecialFollowKeywordStore.shared
        )

        addSubview(tableView)
        addSubview(errorStackView)
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.topAnchor.constraint(equalTo: topAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor),

            errorStackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            errorStackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            errorStackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 32),
            errorStackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -32)
        ])
    }

    private func hideErrorView() {
        errorStackView.isHidden = true
    }

    private func makeAppendIndexPaths(from oldItems: [PostListItem], to newItems: [PostListItem]) -> [IndexPath]? {
        guard newItems.count > oldItems.count else { return nil }
        guard !oldItems.isEmpty else { return nil }

        for index in oldItems.indices where oldItems[index].post.id != newItems[index].post.id {
            return nil
        }

        return (oldItems.count..<newItems.count).map { IndexPath(row: $0, section: 0) }
    }

    @objc private func handlePullToRefresh() {
        delegate?.postTextureListViewDidRequestRefresh(self)
    }

    @objc private func appTextSizeDidChange(_ notification: Notification) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.appTextSizeDidChange(notification)
            }
            return
        }
        guard displayMode == .content else { return }
        // 字号变了缓存键会变，先预热再刷新。
        PostSummaryText.prewarmSymbolImages()
        reloadTable()
    }

    @objc private func specialFollowKeywordsDidChange(_ notification: Notification) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.specialFollowKeywordsDidChange(notification)
            }
            return
        }
        guard displayMode == .content else { return }
        reloadTable()
    }

    @objc private func retryFirstPageTapped() {
        delegate?.postTextureListViewDidRequestFirstPageRetry(self)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard displayMode == .skeleton else { return }
        let targetRowCount = currentSkeletonRowCount()
        guard targetRowCount != skeletonRowCount else { return }
        skeletonRowCount = targetRowCount
        reloadTable()
    }

    private func reloadTable() {
        tableView.reloadData()
        scheduleBatchFetchCheck()
    }

    private func currentSkeletonRowCount() -> Int {
        let visibleHeight = max(bounds.height, tableView.bounds.height)
        guard visibleHeight > 0 else { return minimumSkeletonRowCount }
        let visibleRows = Int(ceil(visibleHeight / estimatedSkeletonRowHeight)) + 1
        return max(minimumSkeletonRowCount, visibleRows)
    }
}

extension PostTextureListView: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch displayMode {
        case .content:
            return items.count
        case .skeleton:
            return skeletonRowCount
        case .firstPageError:
            return 0
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch displayMode {
        case .content:
            let cell = tableView.dequeueReusableCell(
                withIdentifier: PostSummaryCell.reuseIdentifier,
                for: indexPath
            )
            (cell as? PostSummaryCell)?.configure(with: items[indexPath.row])
            return cell
        case .skeleton, .firstPageError:
            return tableView.dequeueReusableCell(
                withIdentifier: PostSummarySkeletonCell.reuseIdentifier,
                for: indexPath
            )
        }
    }
}

extension PostTextureListView: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard displayMode == .content else { return }
        tableView.deselectRow(at: indexPath, animated: true)
        delegate?.postTextureListView(self, didSelectPostAt: indexPath.row)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        requestBatchFetchIfNeeded()
    }

    /// 距离底部不足 leadingScreensForBatching 屏时提前请求下一页。
    private func requestBatchFetchIfNeeded() {
        guard canRequestBatchFetch() else { return }
        let viewportHeight = tableView.bounds.height
        guard viewportHeight > 0 else { return }
        let remainingDistance = tableView.contentSize.height - (tableView.contentOffset.y + viewportHeight)
        guard remainingDistance <= viewportHeight * leadingScreensForBatching else { return }

        let totalCount = items.count
        lastBatchFetchRequestedItemCount = totalCount
        AppLog.info(.postList, "提前触发帖子列表分页: itemCount=\(totalCount), leadingScreens=\(leadingScreensForBatching)")
        delegate?.postTextureListView(
            self,
            didApproachBottomAt: max(totalCount - 1, 0),
            totalCount: totalCount
        )
    }

    /// 内容变化后补一次检查：首屏内容不足一屏时，没有滚动也要能继续加载。
    fileprivate func scheduleBatchFetchCheck() {
        DispatchQueue.main.async { [weak self] in
            self?.requestBatchFetchIfNeeded()
        }
    }

    private func canRequestBatchFetch() -> Bool {
        guard displayMode == .content else { return false }
        guard !items.isEmpty else { return false }
        guard lastBatchFetchRequestedItemCount != items.count else { return false }
        return true
    }
}
