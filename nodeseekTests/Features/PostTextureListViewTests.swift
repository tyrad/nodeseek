//
//  PostTextureListViewTests.swift
//  nodeseekTests
//

import Testing
import UIKit
@testable import nodeseek

@MainActor
struct PostTextureListViewTests {
    @Test func footerHeightStaysFixedAfterHidingLoadingMore() throws {
        let view = PostTextureListView()
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        view.layoutIfNeeded()

        view.showLoadingMore()
        view.hideLoadingMore()

        let tableView = try #require(view.firstSubview(of: UITableView.self))
        let footer = try #require(tableView.tableFooterView)
        #expect(footer.frame.height == 56)
    }

    @Test func canRefreshVisibleCellAppearanceWithoutReloadingItems() throws {
        let view = PostTextureListView()
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

    @Test func retryButtonNotifiesDelegateAfterFirstPageError() throws {
        let view = PostTextureListView()
        let delegate = SpyPostTextureListViewDelegate()
        view.delegate = delegate

        view.showFirstPageError(message: "网络超时")

        let retryButton = try #require(view.firstButton(accessibilityIdentifier: "post-list-first-page-retry-button"))
        retryButton.sendActions(for: .touchUpInside)

        #expect(delegate.retryRequestCount == 1)
    }
}

private final class SpyPostTextureListViewDelegate: PostTextureListViewDelegate {
    private(set) var retryRequestCount = 0

    func postTextureListView(_ textureListView: PostTextureListView, didSelectPostAt index: Int) {}

    func postTextureListViewDidRequestRefresh(_ textureListView: PostTextureListView) {}

    func postTextureListViewDidRequestFirstPageRetry(_ textureListView: PostTextureListView) {
        retryRequestCount += 1
    }

    func postTextureListView(_ textureListView: PostTextureListView, didApproachBottomAt index: Int, totalCount: Int) {}
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
