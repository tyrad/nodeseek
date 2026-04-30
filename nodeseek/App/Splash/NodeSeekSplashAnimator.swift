//
//  NodeSeekSplashAnimator.swift
//  nodeseek
//

import UIKit

enum NodeSeekSplashTimeline {
    static let animationDuration: CFTimeInterval = 1.65
    static let reduceMotionDuration: CFTimeInterval = 0.18

    static let nDuration: CFTimeInterval = 0.72
    static let nLeftDuration: CFTimeInterval = nDuration * 0.31
    static let nDiagonalDuration: CFTimeInterval = nDuration * 0.39
    static let nFinalDuration: CFTimeInterval = nDuration - nLeftDuration - nDiagonalDuration

    static let sDuration: CFTimeInterval = 0.58
    static let lightSweepBegin: CFTimeInterval = 0.35
    static let lightSweepDuration: CFTimeInterval = 0.72
    static let dotBegin: CFTimeInterval = 1.30
    static let dotDuration: CFTimeInterval = 0.30
}

@MainActor
final class NodeSeekSplashAnimator: NSObject {
    private weak var containerView: UIView?
    private let reduceMotion: Bool
    private let animationDuration: CFTimeInterval

    private let backgroundLayer = CALayer()
    private let nLeftStrokeLayer = CAShapeLayer()
    private let nDiagonalStrokeLayer = CAShapeLayer()
    private let nFinalStrokeLayer = CAShapeLayer()
    private let sLayer = CAShapeLayer()
    private let dotLayer = CAShapeLayer()
    private let lightSweepLayer = CAGradientLayer()
    private var completion: (() -> Void)?

    init(
        reduceMotion: Bool? = nil,
        animationDuration: CFTimeInterval = NodeSeekSplashTimeline.animationDuration
    ) {
        self.reduceMotion = reduceMotion ?? UIAccessibility.isReduceMotionEnabled
        self.animationDuration = animationDuration
        super.init()
    }

    func install(in view: UIView) {
        containerView = view
        configureLayerNames()
        layoutLayers(in: view.bounds)
        view.layer.addSublayer(backgroundLayer)
        view.layer.addSublayer(nLeftStrokeLayer)
        view.layer.addSublayer(nDiagonalStrokeLayer)
        view.layer.addSublayer(nFinalStrokeLayer)
        view.layer.addSublayer(sLayer)
        view.layer.addSublayer(dotLayer)
        view.layer.addSublayer(lightSweepLayer)
    }

    func play(completion: @escaping () -> Void) {
        self.completion = completion

        guard !reduceMotion else {
            pinModelLayersToFinalFrame()
            DispatchQueue.main.asyncAfter(deadline: .now() + NodeSeekSplashTimeline.reduceMotionDuration) { [weak self] in
                self?.complete()
            }
            return
        }

        startAnimationTimeline()
    }

    func relayout() {
        guard let containerView else { return }
        layoutLayers(in: containerView.bounds)
    }

    func updateColors(for traitCollection: UITraitCollection) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        applyColors(for: traitCollection)
        CATransaction.commit()
    }
}

private extension NodeSeekSplashAnimator {
    func configureLayerNames() {
        backgroundLayer.name = "splash.background"
        nLeftStrokeLayer.name = "splash.n.leftStroke"
        nDiagonalStrokeLayer.name = "splash.n.diagonalStroke"
        nFinalStrokeLayer.name = "splash.n.finalStroke"
        sLayer.name = "splash.s"
        dotLayer.name = "splash.dot"
        lightSweepLayer.name = "splash.lightSweep"
    }

    func layoutLayers(in bounds: CGRect) {
        backgroundLayer.frame = bounds

        let logoFrame = aspectFitFrame(for: NodeSeekSplashVector.canvasSize, in: bounds)
        configureShapeLayer(nLeftStrokeLayer, frame: logoFrame, path: NodeSeekSplashVector.nBodyPath())
        configureShapeLayer(nDiagonalStrokeLayer, frame: logoFrame, path: NodeSeekSplashVector.nBodyPath())
        configureShapeLayer(nFinalStrokeLayer, frame: logoFrame, path: NodeSeekSplashVector.nFinalStrokePath())
        configureShapeLayer(sLayer, frame: logoFrame, path: NodeSeekSplashVector.sBodyPath())
        configureDotLayer(in: logoFrame)

        nLeftStrokeLayer.mask = strokeRevealMask(
            name: "splash.n.leftStrokeMask",
            path: NodeSeekSplashVector.nLeftStrokeRevealPath(),
            lineWidth: 104,
            in: logoFrame
        )
        nDiagonalStrokeLayer.mask = strokeRevealMask(
            name: "splash.n.diagonalStrokeMask",
            path: NodeSeekSplashVector.nDiagonalStrokeRevealPath(),
            lineWidth: 128,
            lineCap: .butt,
            in: logoFrame
        )
        nFinalStrokeLayer.mask = strokeRevealMask(
            name: "splash.n.finalStrokeMask",
            path: NodeSeekSplashVector.nFinalStrokeRevealPath(),
            lineWidth: 104,
            lineCap: .butt,
            in: logoFrame
        )
        sLayer.mask = strokeRevealMask(
            name: "splash.s.strokeMask",
            path: NodeSeekSplashVector.sStrokeRevealPath(),
            lineWidth: 146,
            in: logoFrame
        )

        configureLightSweep(in: logoFrame)
        if let containerView {
            applyColors(for: containerView.traitCollection)
        }
    }

    func configureShapeLayer(_ layer: CAShapeLayer, frame: CGRect, path: CGPath) {
        layer.frame = frame
        let scale = frame.width / NodeSeekSplashVector.canvasSize.width
        var transform = CGAffineTransform(scaleX: scale, y: scale)
        layer.path = path.copy(using: &transform)
        layer.fillRule = .evenOdd
        layer.contentsScale = UIScreen.main.scale
    }

    func configureDotLayer(in logoFrame: CGRect) {
        let scale = logoFrame.width / NodeSeekSplashVector.canvasSize.width
        let bounds = NodeSeekSplashVector.dotBounds
        let dotFrame = CGRect(
            x: logoFrame.minX + bounds.minX * scale,
            y: logoFrame.minY + bounds.minY * scale,
            width: bounds.width * scale,
            height: bounds.height * scale
        )
        dotLayer.frame = dotFrame

        var transform = CGAffineTransform(scaleX: scale, y: scale)
            .translatedBy(x: -bounds.minX, y: -bounds.minY)
        dotLayer.path = NodeSeekSplashVector.accentPath().copy(using: &transform)
        dotLayer.fillRule = .evenOdd
        dotLayer.contentsScale = UIScreen.main.scale
    }

    func configureLightSweep(in logoFrame: CGRect) {
        let scale = logoFrame.width / NodeSeekSplashVector.canvasSize.width
        let bounds = NodeSeekSplashVector.logoBounds
        lightSweepLayer.frame = CGRect(
            x: logoFrame.minX + bounds.minX * scale,
            y: logoFrame.minY + bounds.minY * scale,
            width: bounds.width * scale,
            height: bounds.height * scale
        )
        lightSweepLayer.locations = [0, 0.5, 1]
        lightSweepLayer.startPoint = CGPoint(x: 0, y: 0.5)
        lightSweepLayer.endPoint = CGPoint(x: 1, y: 0.5)
        lightSweepLayer.opacity = 0
    }

    func applyColors(for traitCollection: UITraitCollection) {
        backgroundLayer.backgroundColor = NodeSeekSplashVector.backgroundColor(for: traitCollection).cgColor

        let wordmarkColor = NodeSeekSplashVector.wordmarkColor(for: traitCollection).cgColor
        nLeftStrokeLayer.fillColor = wordmarkColor
        nDiagonalStrokeLayer.fillColor = wordmarkColor
        nFinalStrokeLayer.fillColor = wordmarkColor
        sLayer.fillColor = wordmarkColor
        dotLayer.fillColor = NodeSeekSplashVector.accentColor.cgColor

        let sweepColor = NodeSeekSplashVector.lightSweepColor(for: traitCollection)
        lightSweepLayer.colors = [
            sweepColor.withAlphaComponent(0).cgColor,
            sweepColor.cgColor,
            sweepColor.withAlphaComponent(0).cgColor
        ]
    }

    func strokeRevealMask(
        name: String,
        path: CGPath,
        lineWidth: CGFloat,
        lineCap: CAShapeLayerLineCap = .round,
        in logoFrame: CGRect
    ) -> CAShapeLayer {
        let scale = logoFrame.width / NodeSeekSplashVector.canvasSize.width
        let mask = CAShapeLayer()
        mask.name = name
        mask.frame = CGRect(origin: .zero, size: logoFrame.size)
        var transform = CGAffineTransform(scaleX: scale, y: scale)
        mask.path = path.copy(using: &transform)
        mask.fillColor = UIColor.clear.cgColor
        mask.strokeColor = UIColor.black.cgColor
        mask.lineWidth = lineWidth * scale
        mask.lineCap = lineCap
        mask.lineJoin = .round
        mask.strokeStart = 0
        mask.strokeEnd = 0
        return mask
    }

    func aspectFitFrame(for sourceSize: CGSize, in bounds: CGRect) -> CGRect {
        let scale = min(bounds.width / sourceSize.width, bounds.height / sourceSize.height)
        let size = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

private extension NodeSeekSplashAnimator {
    func startAnimationTimeline() {
        dotLayer.opacity = 0
        lightSweepLayer.opacity = 1

        let timelineBegin = CACurrentMediaTime()
        animateStrokeReveal(
            mask: nLeftStrokeLayer.mask,
            beginTime: timelineBegin,
            duration: NodeSeekSplashTimeline.nLeftDuration
        )
        animateStrokeReveal(
            mask: nDiagonalStrokeLayer.mask,
            beginTime: timelineBegin + NodeSeekSplashTimeline.nLeftDuration,
            duration: NodeSeekSplashTimeline.nDiagonalDuration
        )
        animateStrokeReveal(
            mask: nFinalStrokeLayer.mask,
            beginTime: timelineBegin + NodeSeekSplashTimeline.nLeftDuration + NodeSeekSplashTimeline.nDiagonalDuration,
            duration: NodeSeekSplashTimeline.nFinalDuration
        )
        animateStrokeReveal(
            mask: sLayer.mask,
            beginTime: timelineBegin + NodeSeekSplashTimeline.nDuration,
            duration: NodeSeekSplashTimeline.sDuration
        )
        animateLightSweep(
            beginTime: timelineBegin + NodeSeekSplashTimeline.lightSweepBegin,
            duration: NodeSeekSplashTimeline.lightSweepDuration
        )
        animateDotPop(
            beginTime: timelineBegin + NodeSeekSplashTimeline.dotBegin,
            duration: NodeSeekSplashTimeline.dotDuration
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) { [weak self] in
            guard let self else { return }
            self.pinModelLayersToFinalFrame()
            self.complete()
        }
    }

    func pinModelLayersToFinalFrame() {
        nLeftStrokeLayer.opacity = 1
        nDiagonalStrokeLayer.opacity = 1
        nFinalStrokeLayer.opacity = 1
        sLayer.opacity = 1
        dotLayer.opacity = 1
        lightSweepLayer.opacity = 0
        revealStrokeMask(nLeftStrokeLayer.mask)
        revealStrokeMask(nDiagonalStrokeLayer.mask)
        revealStrokeMask(nFinalStrokeLayer.mask)
        revealStrokeMask(sLayer.mask)
    }

    func complete() {
        completion?()
        completion = nil
    }

    func animateStrokeReveal(mask: CALayer?, beginTime: CFTimeInterval, duration: CFTimeInterval) {
        guard let mask = mask as? CAShapeLayer else { return }
        mask.strokeEnd = 0

        let animation = CABasicAnimation(keyPath: "strokeEnd")
        animation.fromValue = 0
        animation.toValue = 1
        animation.beginTime = beginTime
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
        mask.add(animation, forKey: "strokeReveal")
    }

    func revealStrokeMask(_ mask: CALayer?) {
        guard let mask = mask as? CAShapeLayer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mask.strokeEnd = 1
        mask.removeAnimation(forKey: "strokeReveal")
        CATransaction.commit()
    }

    func animateLightSweep(beginTime: CFTimeInterval, duration: CFTimeInterval) {
        let travel = lightSweepLayer.bounds.width
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = -travel
        animation.toValue = travel
        animation.beginTime = beginTime
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.fillMode = .backwards
        animation.isRemovedOnCompletion = true
        lightSweepLayer.add(animation, forKey: "lightSweep")

        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0, 1, 0]
        opacity.keyTimes = [0, 0.45, 1]
        opacity.beginTime = beginTime
        opacity.duration = duration
        opacity.fillMode = .forwards
        opacity.isRemovedOnCompletion = false
        lightSweepLayer.add(opacity, forKey: "lightSweepOpacity")
    }

    func animateDotPop(beginTime: CFTimeInterval, duration: CFTimeInterval) {
        dotLayer.opacity = 1

        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0, 1, 1]
        opacity.keyTimes = [0, 0.25, 1]
        opacity.beginTime = beginTime
        opacity.duration = duration
        opacity.fillMode = .backwards
        opacity.isRemovedOnCompletion = true
        dotLayer.add(opacity, forKey: "dotOpacity")

        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [0.72, 1.12, 1.0]
        scale.keyTimes = [0, 0.62, 1]
        scale.beginTime = beginTime
        scale.duration = duration
        scale.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeInEaseOut)
        ]
        dotLayer.add(scale, forKey: "dotPop")
    }

}
