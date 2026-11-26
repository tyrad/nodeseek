//
//  PostListViewTests.swift
//  nodeseekTests
//

import Testing
import UIKit
@testable import nodeseek

@MainActor
struct PostListViewTests {
    @Test func footerHeightStaysFixedAfterHidingLoadingMore() throws {
        let view = PostListView()
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        view.layoutIfNeeded()

        view.showLoadingMore()
        view.hideLoadingMore()

        let tableView = try #require(view.firstSubview(of: UITableView.self))
        let footer = try #require(tableView.tableFooterView)
        #expect(footer.frame.height == 56)
    }

    @Test func canRefreshVisibleCellAppearanceWithoutReloadingItems() throws {
        let view = PostListView()
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        view.setItems([
            PostListItem(post: PostSummary(
                id: "1",
                title: "标题",
                url: URL(string: "https://www.nodeseek.com/post-1-1")!,
                authorName: "ipv4",
                nodeName: "技术",
                replyCount: 1,
                lastActivityText: "刚刚",
                isPinned: false
            ), isVisited: false)
        ])
        view.layoutIfNeeded()

        view.refreshVisibleAppearanceForCurrentTraits()

        let tableView = try #require(view.firstSubview(of: UITableView.self))
        #expect(tableView.numberOfRows(inSection: 0) == 1)
    }

    /// 首页用的列表默认不带关键词；搜索页设置后可见行重新排版出高亮，清空后恢复。
    @Test func searchHighlightTermsRelayoutVisibleTitles() throws {
        let view = PostListView()
        #expect(view.searchHighlightTerms.isEmpty)
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        view.setItems([
            PostListItem(post: PostSummary(
                id: "1",
                title: "出一台美西 VPS",
                url: URL(string: "https://www.nodeseek.com/post-1-1")!,
                authorName: "ipv4",
                nodeName: "交易",
                replyCount: 1,
                lastActivityText: "刚刚",
                isPinned: false
            ), isVisited: false)
        ])
        view.layoutIfNeeded()
        let tableView = try #require(view.firstSubview(of: UITableView.self))

        func keywordBackground() throws -> Any? {
            tableView.layoutIfNeeded()
            let cell = try #require(tableView.visibleCells.first as? PostSummaryCell)
            let label = try #require(Mirror(reflecting: cell).children.first { $0.label == "titleLabel" }?.value as? UILabel)
            let text = try #require(label.attributedText)
            let location = (text.string as NSString).range(of: "美西").location
            return text.attribute(.backgroundColor, at: location, effectiveRange: nil)
        }

        #expect(try keywordBackground() == nil)
        view.searchHighlightTerms = ["美西"]
        #expect(try keywordBackground() as? UIColor == SearchKeywordHighlighter.backgroundColor)

        // 切换深浅色、宽度变化时行会自己补算排版，高亮不能丢
        let cell = try #require(tableView.visibleCells.first as? PostSummaryCell)
        cell.overrideUserInterfaceStyle = .dark
        cell.applyCurrentTheme()
        #expect(try keywordBackground() as? UIColor == SearchKeywordHighlighter.backgroundColor)
        cell.contentView.frame.size.width -= 40
        cell.layoutIfNeeded()
        #expect(try keywordBackground() as? UIColor == SearchKeywordHighlighter.backgroundColor)

        view.searchHighlightTerms = []
        #expect(try keywordBackground() == nil)
    }

    @Test func loadingSkeletonRowsFillVisibleListHeight() throws {
        let view = PostListView()
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 806)

        view.showLoadingSkeleton()
        view.layoutIfNeeded()

        let tableView = try #require(view.firstSubview(of: UITableView.self))
        let minimumSkeletonHeight = PostListCellStyle.Avatar.skeletonSize
            + PostListCellStyle.Layout.verticalContentInset * 2
        #expect(CGFloat(tableView.numberOfRows(inSection: 0)) * minimumSkeletonHeight >= tableView.bounds.height)
    }

    @Test func shortFirstPageRequestsNextPageOnlyOnce() async throws {
        let view = PostListView()
        let delegate = SpyPostListViewDelegate()
        view.delegate = delegate
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        view.setItems([
            PostListItem(post: PostSummary(
                id: "1",
                title: "标题",
                url: URL(string: "https://www.nodeseek.com/post-1-1")!,
                authorName: "ipv4",
                nodeName: "技术",
                replyCount: 1,
                lastActivityText: "刚刚",
                isPinned: false
            ), isVisited: false)
        ])
        view.layoutIfNeeded()

        try await Task.sleep(nanoseconds: 100_000_000)
        let tableView = try #require(view.firstSubview(of: UITableView.self))
        tableView.delegate?.scrollViewDidScroll?(tableView)

        #expect(delegate.approachBottomCount == 1)
    }

    @Test func retryButtonNotifiesDelegateAfterFirstPageError() throws {
        let view = PostListView()
        let delegate = SpyPostListViewDelegate()
        view.delegate = delegate

        view.showFirstPageError(message: "网络超时")

        let retryButton = try #require(view.firstButton(accessibilityIdentifier: "post-list-first-page-retry-button"))
        retryButton.sendActions(for: .touchUpInside)

        #expect(delegate.retryRequestCount == 1)
    }
}

private final class SpyPostListViewDelegate: PostListViewDelegate {
    private(set) var retryRequestCount = 0
    private(set) var approachBottomCount = 0

    func postListView(_ listView: PostListView, didSelectPostAt index: Int) {}

    func postListViewDidRequestRefresh(_ listView: PostListView) {}

    func postListViewDidRequestFirstPageRetry(_ listView: PostListView) {
        retryRequestCount += 1
    }

    func postListView(_ listView: PostListView, didApproachBottomAt index: Int, totalCount: Int) {
        approachBottomCount += 1
    }
}

private extension UIView {
    func firstSubview<T: UIView>(of type: T.Type) -> T? {
        if let matched = self as? T {
            return matched
        }
        for subview in subviews {
            if let matched = subview.firstSubview(of: type) {
                return matched
            }
        }
        return nil
    }

    func firstButton(accessibilityIdentifier: String) -> UIButton? {
        if let button = self as? UIButton, button.accessibilityIdentifier == accessibilityIdentifier {
            return button
        }
        for subview in subviews {
            if let button = subview.firstButton(accessibilityIdentifier: accessibilityIdentifier) {
                return button
            }
        }
        return nil
    }
}
