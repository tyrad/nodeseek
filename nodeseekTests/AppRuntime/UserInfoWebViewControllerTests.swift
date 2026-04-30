//
//  UserInfoWebViewControllerTests.swift
//  nodeseekTests
//

import Testing
import Foundation
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
}
