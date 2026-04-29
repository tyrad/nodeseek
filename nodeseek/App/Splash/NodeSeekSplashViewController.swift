//
//  NodeSeekSplashViewController.swift
//  nodeseek
//

import UIKit

@MainActor
final class NodeSeekSplashViewController: UIViewController {
    private let animator: NodeSeekSplashAnimator
    private let onFinish: () -> Void
    private var didStartAnimation = false

    init(
        reduceMotion: Bool = UIAccessibility.isReduceMotionEnabled,
        onFinish: @escaping () -> Void
    ) {
        self.animator = NodeSeekSplashAnimator(reduceMotion: reduceMotion)
        self.onFinish = onFinish
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("NodeSeekSplashViewController does not support storyboard initialization")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        animator.install(in: view)
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
}
