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
        let controller = NodeSeekSplashViewController(reduceMotion: true, prewarmWebView: {}) {
            didFinish = true
        }

        controller.loadViewIfNeeded()
        controller.viewDidAppear(false)

        try? await Task.sleep(nanoseconds: 300_000_000)
        #expect(didFinish)
    }

    @Test func splashPrewarmsWebViewWhenAnimationStarts() {
        var prewarmCount = 0
        let controller = NodeSeekSplashViewController(
            reduceMotion: true,
            prewarmWebView: {
                prewarmCount += 1
            },
            onFinish: {}
        )

        controller.loadViewIfNeeded()
        controller.viewDidAppear(false)
        controller.viewDidAppear(false)

        #expect(prewarmCount == 1)
    }
}
