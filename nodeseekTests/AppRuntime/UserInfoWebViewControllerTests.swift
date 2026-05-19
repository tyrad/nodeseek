//
//  UserInfoWebViewControllerTests.swift
//  nodeseekTests
//

import Testing
import Foundation
import UIKit
import WebKit
@testable import nodeseek

@MainActor
struct UserInfoWebViewControllerTests {
    @Test func normalizesSpaceURLToGeneralTab() throws {
        let url = try #require(URL(string: "https://www.nodeseek.com/space/1541"))

        let normalizedURL = UserInfoWebViewController.normalizedProfileURL(url)

        #expect(normalizedURL.absoluteString == "https://www.nodeseek.com/space/1541#/general")
    }

    @Test func preservesExistingGeneralFragment() throws {
        let url = try #require(URL(string: "https://www.nodeseek.com/space/1541#/general"))

        let normalizedURL = UserInfoWebViewController.normalizedProfileURL(url)

        #expect(normalizedURL.absoluteString == "https://www.nodeseek.com/space/1541#/general")
    }

    @Test func normalizesRelativeSpaceURLToAbsoluteGeneralTab() throws {
        let url = try #require(URL(string: "/space/1541"))

        let normalizedURL = UserInfoWebViewController.normalizedProfileURL(url)

        #expect(normalizedURL.absoluteString == "https://www.nodeseek.com/space/1541#/general")
    }

    @Test func moreMenuIncludesWebRefreshAction() throws {
        let url = try #require(URL(string: "https://www.nodeseek.com/space/1541"))
        let viewController = UserInfoWebViewController(profileURL: url, automaticallyLoadsPage: false)

        viewController.loadViewIfNeeded()

        let moreButton = try #require(viewController.navigationItem.rightBarButtonItem)
        _ = try #require(moreButton.menu?.children.first { $0.title == "刷新" } as? UIAction)
    }

    @Test func classifiesPostLinkAsNativeRoute() throws {
        let baseURL = try #require(URL(string: "https://www.nodeseek.com/space/1541"))
        let url = try #require(URL(string: "/post-704174-2#8", relativeTo: baseURL))

        let route = try #require(UserInfoWebViewController.nativePostRoute(for: url, baseURL: baseURL))

        #expect(route.postID == "704174")
        #expect(route.page == 2)
        #expect(route.anchorID == "8")
    }

    @Test func classifiesScriptDrivenPostNavigationAsNativeRoute() throws {
        let baseURL = try #require(URL(string: "https://www.nodeseek.com/space/1541#/general"))
        let url = try #require(URL(string: "/post-704174-2#8", relativeTo: baseURL))

        let route = try #require(UserInfoWebViewController.nativePostRoute(
            for: url,
            baseURL: baseURL,
            navigationType: .other
        ))

        #expect(route.postID == "704174")
        #expect(route.page == 2)
        #expect(route.anchorID == "8")
    }

    @Test func doesNotClassifyNonPostNodeSeekLinkAsNativeRoute() throws {
        let baseURL = try #require(URL(string: "https://www.nodeseek.com/space/1541"))
        let url = try #require(URL(string: "/space/2000", relativeTo: baseURL))

        #expect(UserInfoWebViewController.nativePostRoute(for: url, baseURL: baseURL) == nil)
    }
}
