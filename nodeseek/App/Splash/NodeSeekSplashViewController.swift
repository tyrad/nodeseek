//
//  NodeSeekSplashViewController.swift
//  nodeseek
//

import UIKit

@MainActor
final class NodeSeekSplashViewController: UIViewController {
    private let animator: NodeSeekSplashAnimator
    private let prewarmWebView: @MainActor () -> Void
    private let onFinish: () -> Void
    private var didPrewarmWebView = false
    private var didStartAnimation = false

    init(
        reduceMotion: Bool? = nil,
        prewarmWebView: @escaping @MainActor () -> Void = { NodeSeekWebViewPrewarmer.prewarm() },
        onFinish: @escaping () -> Void
    ) {
        self.animator = NodeSeekSplashAnimator(reduceMotion: reduceMotion)
        self.prewarmWebView = prewarmWebView
        self.onFinish = onFinish
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("NodeSeekSplashViewController does not support storyboard initialization")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        applyColors()
        animator.install(in: view)
        startPrewarmIfNeeded()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (controller: NodeSeekSplashViewController, _) in
            controller.applyColors()
            controller.animator.updateColors(for: controller.traitCollection)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        animator.relayout()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard !didStartAnimation else { return }
        didStartAnimation = true
        animator.play { [weak self] in
            self?.onFinish()
        }
    }

    private func startPrewarmIfNeeded() {
        guard !didPrewarmWebView else { return }
        didPrewarmWebView = true
        prewarmWebView()
    }

    private func applyColors() {
        view.backgroundColor = NodeSeekSplashVector.backgroundColor(for: traitCollection)
    }
}
