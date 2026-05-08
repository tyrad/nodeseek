//
//  PostListRouterTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/5/8.
//

import Testing
import UIKit
@testable import nodeseek

@MainActor
struct PostListRouterTests {
    @Test func recentVisitedSelectionAlwaysOpensFirstPageWithoutAnchor() throws {
        let router = PostListRouter()
        let rootViewController = UIViewController()
        let navigationController = UINavigationController(rootViewController: rootViewController)
        router.viewController = rootViewController
        let visitedStore = RouterFakeVisitedPostStore(records: [
            VisitedPostRecord(
                postID: "717963",
                title: "详情标题",
                url: try #require(URL(string: "https://www.nodeseek.com/post-717963-6#52")),
                visitedAt: Date(timeIntervalSince1970: 100),
                avatarURL: nil
            )
        ])

        router.navigateToRecentVisitedPosts(visitedStore: visitedStore)
        let recentViewController = try #require(navigationController.topViewController as? RecentVisitedPostsViewController)
        recentViewController.loadViewIfNeeded()
        recentViewController.tableView(recentViewController.tableView, didSelectRowAt: IndexPath(row: 0, section: 0))

        let detailViewController = try #require(navigationController.topViewController as? PostDetailViewController)
        #expect(detailViewController.initialPage == 1)
        #expect(detailViewController.currentPage == 1)
        #expect(detailViewController.pendingInitialAnchorID == nil)
        #expect(detailViewController.wasOpenedFromInitialAnchor == false)
    }
}

@MainActor
private final class RouterFakeVisitedPostStore: VisitedPostStoreProtocol {
    private let records: [VisitedPostRecord]

    init(records: [VisitedPostRecord]) {
        self.records = records
    }

    func isVisited(postID: String) -> Bool {
        records.contains { $0.postID == postID }
    }

    func markVisited(post: PostSummary, visitedAt: Date) {}

    func recentRecords(limit: Int) -> [VisitedPostRecord] {
        Array(records.prefix(limit))
    }

    func recentRecords(offset: Int, limit: Int) -> [VisitedPostRecord] {
        guard offset < records.count else { return [] }
        return Array(records.dropFirst(offset).prefix(limit))
    }

    func clearAll() {}
}

