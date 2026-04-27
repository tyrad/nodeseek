//
//  PostDetailViewControllerTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/4/27.
//

import Foundation
import Testing
import UIKit
@testable import nodeseek

@MainActor
struct PostDetailViewControllerTests {
    @Test func usesTableViewWithPostSummaryHeaderAndCommentCells() throws {
        let post = PostSummary(
            id: "703863",
            title: "列表标题",
            url: URL(string: "https://www.nodeseek.com/post-703863-1")!,
            authorName: "ipv4",
            nodeName: "日常",
            replyCount: 2,
            lastActivityText: "刚刚",
            avatarURL: URL(string: "https://www.nodeseek.com/avatar/34378.png")
        )
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(
            presenter: presenter,
            initialHeader: PostDetailHeaderContent(post: post)
        )

        viewController.loadViewIfNeeded()

        let tableView = try #require(viewController.view.firstSubview(of: UITableView.self))
        #expect(tableView.tableHeaderView != nil)
        #expect(tableView.numberOfRows(inSection: 0) == 0)

        viewController.render(detail: PostDetail(
            id: "703863",
            title: "详情标题",
            authorName: "ipv4",
            avatarURL: URL(string: "https://www.nodeseek.com/avatar/34378.png"),
            metadataText: "36min ago · 日常",
            contentHTML: "<p>正文</p>",
            comments: [
                Comment(id: "1", authorName: "a", avatarURL: nil, floorText: "#1", createdAtText: "1min ago", contentHTML: "<p>评论一</p>"),
                Comment(id: "2", authorName: "b", avatarURL: nil, floorText: "#2", createdAtText: "2min ago", contentHTML: "<p>评论二</p>")
            ],
            replyForm: nil
        ))

        #expect(tableView.numberOfRows(inSection: 0) == 2)
    }
}

private final class SpyPostDetailPresenter: PostDetailPresenterProtocol {
    private(set) var didLoad = false

    func viewDidLoad() {
        didLoad = true
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
}
