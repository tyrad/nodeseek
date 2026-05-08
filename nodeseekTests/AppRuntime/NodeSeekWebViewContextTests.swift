//
//  NodeSeekWebViewContextTests.swift
//  nodeseekTests
//

import Testing
import UIKit
import WebKit
@testable import nodeseek

@MainActor
struct NodeSeekWebViewContextTests {
    @Test func disablesScrollBounceForSharedWebView() {
        let context = NodeSeekWebViewContext()

        #expect(context.webView.scrollView.bounces == false)
        #expect(context.webView.scrollView.alwaysBounceVertical == false)
        #expect(context.webView.scrollView.alwaysBounceHorizontal == false)
    }
}
