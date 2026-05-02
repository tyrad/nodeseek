//
//  NodeSeekSiteTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/5/2.
//

import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import NodeSeekCore
#else
@testable import nodeseek
#endif

struct NodeSeekSiteTests {
    @Test func exposesCanonicalSiteURLsAndDomains() throws {
        #expect(NodeSeekSite.baseURL.absoluteString == "https://www.nodeseek.com")
        #expect(NodeSeekSite.rootHost == "nodeseek.com")
        #expect(NodeSeekSite.allowedCookieDomains == ["nodeseek.com"])
        #expect(NodeSeekSite.referer == "https://www.nodeseek.com/")
        #expect(NodeSeekSite.loginURL.absoluteString == "https://www.nodeseek.com/signIn.html")
        #expect(NodeSeekSite.newDiscussionURL.absoluteString == "https://www.nodeseek.com/new-discussion")
        #expect(NodeSeekSite.defaultPostListURL.absoluteString == "https://www.nodeseek.com/page-1?sortBy=replyTime")
        #expect(NodeSeekSite.postURL(id: "705039", page: 2).absoluteString == "https://www.nodeseek.com/post-705039-2")
    }

    @Test func recognizesRootAndSubdomainHostsOnly() throws {
        let rootURL = try #require(URL(string: "https://nodeseek.com/post-1"))
        let wwwURL = try #require(URL(string: "https://www.nodeseek.com/post-1"))
        let staticURL = try #require(URL(string: "https://static.nodeseek.com/image.png"))
        let unrelatedURL = try #require(URL(string: "https://example.com/post-1"))
        let lookalikeURL = try #require(URL(string: "https://evilnodeseek.com/post-1"))

        #expect(NodeSeekSite.isNodeSeekHost(rootURL))
        #expect(NodeSeekSite.isNodeSeekHost(wwwURL))
        #expect(NodeSeekSite.isNodeSeekHost(staticURL))
        #expect(NodeSeekSite.isNodeSeekHost(unrelatedURL) == false)
        #expect(NodeSeekSite.isNodeSeekHost(lookalikeURL) == false)
    }
}
