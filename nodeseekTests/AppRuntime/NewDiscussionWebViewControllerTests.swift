//
//  NewDiscussionWebViewControllerTests.swift
//  nodeseekTests
//

import Foundation
import Testing
@testable import nodeseek

@MainActor
struct NewDiscussionWebViewControllerTests {
    @Test func usesDedicatedNewDiscussionURL() {
        #expect(NewDiscussionWebViewController.newDiscussionURL.absoluteString == "https://www.nodeseek.com/new-discussion")
    }

    @Test func mapsUserNotFound404ToLoginHint() {
        let message = NewDiscussionWebViewController.loginRequiredMessage(
            statusCode: 404,
            responseText: #"{"message":"USER NOT FOUND","status":404,"success":false}"#
        )

        #expect(message == "用户可能还未登录，请先登录。")
    }

    @Test func ignoresUnrelated404Responses() {
        let message = NewDiscussionWebViewController.loginRequiredMessage(
            statusCode: 404,
            responseText: #"{"message":"NOT FOUND","status":404,"success":false}"#
        )

        #expect(message == nil)
    }
}
