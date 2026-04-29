//
//  NodeSeekSplashAnimatorTests.swift
//  nodeseekTests
//

import Testing
import UIKit
@testable import nodeseek

@MainActor
struct NodeSeekSplashAnimatorTests {
    @Test func animatorInstallsExpectedLogoLayers() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let animator = NodeSeekSplashAnimator(reduceMotion: false)

        animator.install(in: container)

        let layerNames = container.layer.sublayers?.compactMap(\.name) ?? []
        #expect(layerNames.contains("splash.background"))
        #expect(layerNames.contains("splash.n"))
        #expect(layerNames.contains("splash.s"))
        #expect(layerNames.contains("splash.dot"))
        #expect(layerNames.contains("splash.lightSweep"))
        #expect(layerNames.contains("splash.finalLogo"))
    }

    @Test func animatorUsesStrokeMasksForHandwrittenReveal() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let animator = NodeSeekSplashAnimator(reduceMotion: false)

        animator.install(in: container)

        let layers = container.layer.sublayers ?? []
        let nLayer = layers.first { $0.name == "splash.n" }
        let sLayer = layers.first { $0.name == "splash.s" }

        #expect(nLayer?.mask is CAShapeLayer)
        #expect(sLayer?.mask is CAShapeLayer)
        #expect(nLayer?.mask?.name == "splash.n.strokeMask")
        #expect(sLayer?.mask?.name == "splash.s.strokeMask")
    }

    @Test func reduceMotionCompletesWithoutLongAnimation() async {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let animator = NodeSeekSplashAnimator(reduceMotion: true)
        var completed = false

        animator.install(in: container)
        animator.play {
            completed = true
        }

        try? await Task.sleep(nanoseconds: 300_000_000)
        #expect(completed)
    }

    @Test func animatorKeepsVectorLayersAsFinalFrameBeforeCompletion() async {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let animator = NodeSeekSplashAnimator(reduceMotion: false, animationDuration: 0.01)
        var completed = false

        animator.install(in: container)
        animator.play {
            completed = true
        }

        try? await Task.sleep(nanoseconds: 50_000_000)

        let layers = container.layer.sublayers ?? []
        #expect(completed)
        #expect(layers.first { $0.name == "splash.n" }?.opacity == 1)
        #expect(layers.first { $0.name == "splash.s" }?.opacity == 1)
        #expect(layers.first { $0.name == "splash.dot" }?.opacity == 1)
        #expect(layers.first { $0.name == "splash.lightSweep" }?.opacity == 0)
        #expect(layers.first { $0.name == "splash.finalLogo" }?.opacity == 0)
    }
}
