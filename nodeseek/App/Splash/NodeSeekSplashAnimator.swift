//
//  NodeSeekSplashAnimator.swift
//  nodeseek
//

import UIKit

@MainActor
final class NodeSeekSplashAnimator: NSObject {
    private weak var containerView: UIView?
    private let reduceMotion: Bool
    private let animationDuration: CFTimeInterval

    private let backgroundLayer = CALayer()
    private let nLayer = CAShapeLayer()
    private let sLayer = CAShapeLayer()
    private let dotLayer = CAShapeLayer()
    private let lightSweepLayer = CAGradientLayer()
    private let finalLogoLayer = CALayer()
    private var completion: (() -> Void)?

    init(
        reduceMotion: Bool = UIAccessibility.isReduceMotionEnabled,
        animationDuration: CFTimeInterval = 1.25
    ) {
        self.reduceMotion = reduceMotion
        self.animationDuration = animationDuration
        super.init()
    }

    func install(in view: UIView) {
        containerView = view
        configureLayerNames()
        layoutLayers(in: view.bounds)
        view.layer.addSublayer(backgroundLayer)
        view.layer.addSublayer(nLayer)
        view.layer.addSublayer(sLayer)
        view.layer.addSublayer(dotLayer)
        view.layer.addSublayer(lightSweepLayer)
        view.layer.addSublayer(finalLogoLayer)
    }

    func play(completion: @escaping () -> Void) {
        self.completion = completion

        guard !reduceMotion else {
            finalLogoLayer.opacity = 1
            nLayer.opacity = 0
            sLayer.opacity = 0
            dotLayer.opacity = 0
            lightSweepLayer.opacity = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                completion()
            }
            return
        }

        startAnimationTimeline()
    }

    func relayout() {
        guard let containerView else { return }
        layoutLayers(in: containerView.bounds)
    }
}

private extension NodeSeekSplashAnimator {
    func configureLayerNames() {
        backgroundLayer.name = "splash.background"
        nLayer.name = "splash.n"
        sLayer.name = "splash.s"
        dotLayer.name = "splash.dot"
        lightSweepLayer.name = "splash.lightSweep"
        finalLogoLayer.name = "splash.finalLogo"
    }

    func layoutLayers(in bounds: CGRect) {
        backgroundLayer.frame = bounds
        backgroundLayer.backgroundColor = UIColor.white.cgColor

        let logoFrame = aspectFitFrame(for: NodeSeekSplashVector.canvasSize, in: bounds)
        configureShapeLayer(nLayer, frame: logoFrame, path: NodeSeekSplashVector.wordmarkPath(), color: NodeSeekSplashVector.wordmarkColor)
        configureShapeLayer(sLayer, frame: logoFrame, path: NodeSeekSplashVector.wordmarkPath(), color: NodeSeekSplashVector.wordmarkColor)
        configureDotLayer(in: logoFrame)

        nLayer.mask = strokeRevealMask(
            name: "splash.n.strokeMask",
            path: NodeSeekSplashVector.nStrokeRevealPath(),
            lineWidth: 128,
            in: logoFrame
        )
        sLayer.mask = strokeRevealMask(
            name: "splash.s.strokeMask",
            path: NodeSeekSplashVector.sStrokeRevealPath(),
            lineWidth: 128,
            in: logoFrame
        )

        configureLightSweep(in: logoFrame)

        finalLogoLayer.frame = logoFrame
        finalLogoLayer.contentsGravity = .resizeAspect
        finalLogoLayer.contentsScale = UIScreen.main.scale
        finalLogoLayer.opacity = 0
        finalLogoLayer.contents = UIImage(named: "SplashFinalLogo")?.cgImage
    }

    func configureShapeLayer(_ layer: CAShapeLayer, frame: CGRect, path: CGPath, color: UIColor) {
        layer.frame = frame
        let scale = frame.width / NodeSeekSplashVector.canvasSize.width
        var transform = CGAffineTransform(scaleX: scale, y: scale)
        layer.path = path.copy(using: &transform)
        layer.fillColor = color.cgColor
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
        dotLayer.fillColor = NodeSeekSplashVector.accentColor.cgColor
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
        lightSweepLayer.colors = [
            UIColor.white.withAlphaComponent(0).cgColor,
            UIColor.white.withAlphaComponent(0.62).cgColor,
            UIColor.white.withAlphaComponent(0).cgColor
        ]
        lightSweepLayer.locations = [0, 0.5, 1]
        lightSweepLayer.startPoint = CGPoint(x: 0, y: 0.5)
        lightSweepLayer.endPoint = CGPoint(x: 1, y: 0.5)
        lightSweepLayer.opacity = 0
    }

    func strokeRevealMask(name: String, path: CGPath, lineWidth: CGFloat, in logoFrame: CGRect) -> CAShapeLayer {
        let scale = logoFrame.width / NodeSeekSplashVector.canvasSize.width
        let mask = CAShapeLayer()
        mask.name = name
        mask.frame = CGRect(origin: .zero, size: logoFrame.size)
        var transform = CGAffineTransform(scaleX: scale, y: scale)
        mask.path = path.copy(using: &transform)
        mask.fillColor = UIColor.clear.cgColor
        mask.strokeColor = UIColor.black.cgColor
        mask.lineWidth = lineWidth * scale
        mask.lineCap = .round
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
        finalLogoLayer.opacity = 0

        animateStrokeReveal(mask: nLayer.mask, beginTime: 0.00, duration: 0.52)
        animateStrokeReveal(mask: sLayer.mask, beginTime: 0.38, duration: 0.47)
        animateLightSweep(beginTime: 0.28)
        animateDotPop(beginTime: 0.82)

        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) { [weak self] in
            guard let self else { return }
            self.pinModelLayersToFinalFrame()
            self.completion?()
            self.completion = nil
        }
    }

    func pinModelLayersToFinalFrame() {
        nLayer.opacity = 1
        sLayer.opacity = 1
        dotLayer.opacity = 1
        lightSweepLayer.opacity = 0
        finalLogoLayer.opacity = 0
    }

    func animateStrokeReveal(mask: CALayer?, beginTime: CFTimeInterval, duration: CFTimeInterval) {
        guard let mask = mask as? CAShapeLayer else { return }
        mask.strokeEnd = 1

        let animation = CABasicAnimation(keyPath: "strokeEnd")
        animation.fromValue = 0
        animation.toValue = 1
        animation.beginTime = CACurrentMediaTime() + beginTime
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        animation.fillMode = .backwards
        animation.isRemovedOnCompletion = true
        mask.add(animation, forKey: "strokeReveal")
    }

    func animateLightSweep(beginTime: CFTimeInterval) {
        let travel = lightSweepLayer.bounds.width
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = -travel
        animation.toValue = travel
        animation.beginTime = CACurrentMediaTime() + beginTime
        animation.duration = 0.57
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.fillMode = .backwards
        animation.isRemovedOnCompletion = true
        lightSweepLayer.add(animation, forKey: "lightSweep")

        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0, 1, 0]
        opacity.keyTimes = [0, 0.45, 1]
        opacity.beginTime = CACurrentMediaTime() + beginTime
        opacity.duration = 0.57
        opacity.fillMode = .forwards
        opacity.isRemovedOnCompletion = false
        lightSweepLayer.add(opacity, forKey: "lightSweepOpacity")
    }

    func animateDotPop(beginTime: CFTimeInterval) {
        dotLayer.opacity = 1

        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0, 1, 1]
        opacity.keyTimes = [0, 0.25, 1]
        opacity.beginTime = CACurrentMediaTime() + beginTime
        opacity.duration = 0.26
        opacity.fillMode = .backwards
        opacity.isRemovedOnCompletion = true
        dotLayer.add(opacity, forKey: "dotOpacity")

        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [0.72, 1.12, 1.0]
        scale.keyTimes = [0, 0.62, 1]
        scale.beginTime = CACurrentMediaTime() + beginTime
        scale.duration = 0.26
        scale.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeInEaseOut)
        ]
        dotLayer.add(scale, forKey: "dotPop")
    }

}
