//
//  CookieSharedWebViewControllerTests.swift
//  nodeseekTests
//

import Foundation
import Testing
import UIKit
@testable import nodeseek

@MainActor
struct CookieSharedWebViewControllerTests {
    @Test func moreMenuIncludesWebRefreshAction() throws {
        let url = try #require(URL(string: "https://www.nodeseek.com/post-1-1"))
        let viewController = CookieSharedWebViewController(url: url, automaticallyLoadsPage: false)

        viewController.loadViewIfNeeded()

        let moreButton = try #require(viewController.navigationItem.rightBarButtonItem)
        _ = try #require(moreButton.menu?.children.first { $0.title == "刷新" } as? UIAction)
    }

    @Test func classifiesPostLinkAsNativeRoute() throws {
        let baseURL = try #require(URL(string: "https://www.nodeseek.com/post-1-1"))
        let url = try #require(URL(string: "/post-704174-2#8", relativeTo: baseURL))

        let route = try #require(CookieSharedWebViewController.nativePostRoute(for: url, baseURL: baseURL))

        #expect(route.postID == "704174")
        #expect(route.page == 2)
        #expect(route.anchorID == "8")
    }
}
