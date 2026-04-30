//
//  ArchitectureSkeletonTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/4/27.
//

import Testing
import UIKit
@testable import nodeseek

@MainActor
struct ArchitectureSkeletonTests {

    @Test func appRouterCreatesNodeSeekNavigationRoot() {
        let root = AppRouter().makeRootViewController()

        #expect(root is UINavigationController)
        let navigationController = root as? UINavigationController
        let postListViewController = navigationController?.topViewController as? PostListViewController
        postListViewController?.loadViewIfNeeded()
        
        #expect(postListViewController != nil)
        #expect(postListViewController?.navigationItem.title != "NodeSeek")
        #expect(postListViewController?.navigationItem.leftBarButtonItem == nil)
        #expect(postListViewController?.hasCompactTopButton == true)
    }

    @Test func basicDomainModelsCanBeCreated() {
        let post = PostSummary(
            id: "123",
            title: "测试帖子",
            url: URL(string: "https://www.nodeseek.com/post-123")!,
            authorName: "mist",
            nodeName: "VPS",
            replyCount: 2,
            lastActivityText: "1 分钟前"
        )

        #expect(post.id == "123")
        #expect(post.title == "测试帖子")
        #expect(post.replyCount == 2)
    }
}
