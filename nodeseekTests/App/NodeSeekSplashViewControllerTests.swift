//
//  NodeSeekSplashViewControllerTests.swift
//  nodeseekTests
//

import Testing
import UIKit
@testable import nodeseek

@MainActor
struct NodeSeekSplashViewControllerTests {
    @Test func splashCallsCompletionWhenReduceMotionIsEnabled() async {
        var didFinish = false
        let controller = NodeSeekSplashViewController(reduceMotion: true) {
            didFinish = true
        }

        controller.loadViewIfNeeded()
        controller.viewDidAppear(false)

        try? await Task.sleep(nanoseconds: 300_000_000)
        #expect(didFinish)
    }
}
