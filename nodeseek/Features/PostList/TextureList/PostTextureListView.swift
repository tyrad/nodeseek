//
//  PostTextureListView.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import AsyncDisplayKit
import UIKit

protocol PostTextureListViewDelegate: AnyObject {
    func postTextureListView(_ textureListView: PostTextureListView, didSelectPostAt index: Int)
    func postTextureListViewDidRequestRefresh(_ textureListView: PostTextureListView)
    func postTextureListView(_ textureListView: PostTextureListView, didApproachBottomAt index: Int, totalCount: Int)
}

final class PostTextureListView: UIView {
    private enum DisplayMode {
        case content
        case skeleton
    }

    weak var delegate: PostTextureListViewDelegate?

    private let tableNode = ASTableNode(style: .plain)
    private let refreshControl = UIRefreshControl()
    private var displayMode: DisplayMode = .content
    private var items: [PostListItem] = []
    private let minimumSkeletonRowCount = 8
    private let estimatedSkeletonRowHeight: CGFloat = 84
    private var skeletonRowCount: Int = 8

    private let loadMoreIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
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

    func setItems(_ items: [PostListItem]) {
        if displayMode == .content, self.items == items {
            return
        }
        if displayMode != .content {
            self.items = items
            displayMode = .content
            tableNode.reloadData()
            return
        }

        if let appendIndexPaths = makeAppendIndexPaths(from: self.items, to: items) {
            self.items = items
            // 分页追加发生在滚动底部，关闭 row 插入动画可以避免 Texture 调整 contentOffset 时牵动上方内容。
            tableNode.performBatch(animated: false, updates: { [weak self] in
                self?.tableNode.insertRows(at: appendIndexPaths, with: .none)
            })
            return
        }

        self.items = items
        tableNode.reloadData()
    }

    func updateVisitedState(at index: Int, isVisited: Bool) {
        guard displayMode == .content else { return }
        guard items.indices.contains(index) else { return }
        let existing = items[index]
        guard existing.isVisited != isVisited else { return }
        items[index] = PostListItem(post: existing.post, isVisited: isVisited)
        tableNode.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
    }

    func showLoadingSkeleton() {
        guard displayMode != .skeleton else { return }
        displayMode = .skeleton
        skeletonRowCount = currentSkeletonRowCount()
        hideLoadingMore()
        tableNode.reloadData()
    }

    func hideLoadingSkeleton() {
        guard displayMode == .skeleton else { return }
        displayMode = .content
        tableNode.reloadData()
    }

    func showLoadingMore() {
        tableNode.view.tableFooterView = loadMoreContainer
        loadMoreIndicator.startAnimating()
    }

    func hideLoadingMore() {
        loadMoreIndicator.stopAnimating()
        tableNode.view.tableFooterView = UIView(frame: .zero)
    }

    func showRefreshing() {
        guard !refreshControl.isRefreshing else { return }
        refreshControl.beginRefreshing()
    }

    func hideRefreshing() {
        refreshControl.endRefreshing()
    }

    func scrollToTop(animated: Bool) {
        tableNode.setContentOffset(.zero, animated: animated)
    }

    private func setupUI() {
        tableNode.dataSource = self
        tableNode.delegate = self
        tableNode.view.separatorStyle = .singleLine
        tableNode.view.showsVerticalScrollIndicator = true
        refreshControl.addTarget(self, action: #selector(handlePullToRefresh), for: .valueChanged)
        tableNode.view.refreshControl = refreshControl
        tableNode.view.translatesAutoresizingMaskIntoConstraints = false

        addSubview(tableNode.view)
        NSLayoutConstraint.activate([
            tableNode.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableNode.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableNode.view.topAnchor.constraint(equalTo: topAnchor),
            tableNode.view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
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

    override func layoutSubviews() {
        super.layoutSubviews()
        guard displayMode == .skeleton else { return }
        let targetRowCount = currentSkeletonRowCount()
        guard targetRowCount != skeletonRowCount else { return }
        skeletonRowCount = targetRowCount
        tableNode.reloadData()
    }

    private func currentSkeletonRowCount() -> Int {
        let visibleHeight = max(bounds.height, tableNode.view.bounds.height)
        guard visibleHeight > 0 else { return minimumSkeletonRowCount }
        let visibleRows = Int(ceil(visibleHeight / estimatedSkeletonRowHeight)) + 1
        return max(minimumSkeletonRowCount, visibleRows)
    }
}

extension PostTextureListView: ASTableDataSource {
    func tableNode(_ tableNode: ASTableNode, numberOfRowsInSection section: Int) -> Int {
        switch displayMode {
        case .content:
            return items.count
        case .skeleton:
            return skeletonRowCount
        }
    }

    func tableNode(_ tableNode: ASTableNode, nodeBlockForRowAt indexPath: IndexPath) -> ASCellNodeBlock {
        switch displayMode {
        case .content:
            let item = items[indexPath.row]
            return {
                PostSummaryCellNode(item: item)
            }
        case .skeleton:
            return {
                PostSummarySkeletonCellNode()
            }
        }
    }
}

extension PostTextureListView: ASTableDelegate {
    func tableNode(_ tableNode: ASTableNode, didSelectRowAt indexPath: IndexPath) {
        guard displayMode == .content else { return }
        tableNode.deselectRow(at: indexPath, animated: true)
        delegate?.postTextureListView(self, didSelectPostAt: indexPath.row)
    }

    func tableNode(_ tableNode: ASTableNode, willDisplayRowWith node: ASCellNode) {
        guard displayMode == .content else { return }
        guard let indexPath = tableNode.indexPath(for: node) else { return }
        delegate?.postTextureListView(self, didApproachBottomAt: indexPath.row, totalCount: items.count)
    }
}
