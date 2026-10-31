//
//  AppRouter.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import UIKit

final class AppRouter {

    weak var window: UIWindow?
    private let layoutSettings: AppNavigationLayoutSettings
    private var layoutObserver: NSObjectProtocol?
    private weak var rootViewController: UIViewController?

    init(layoutSettings: AppNavigationLayoutSettings = .shared) {
        self.layoutSettings = layoutSettings
        layoutObserver = NotificationCenter.default.addObserver(
            forName: AppNavigationLayoutSettings.didChangeNotification,
            object: layoutSettings,
            queue: .main
        ) { [weak self] _ in
            self?.applyCurrentLayout()
        }
    }

    deinit {
        if let layoutObserver {
            NotificationCenter.default.removeObserver(layoutObserver)
        }
    }

    /// 当前可见的导航栈：多 Tab 模式取选中 Tab 的导航栈。
    var navigationController: UINavigationController? {
        if let tabBarController = rootViewController as? MainTabBarController {
            return tabBarController.selectedNavigationController
        }
        return rootViewController as? UINavigationController
    }

    func makeRootViewController() -> UIViewController {
        let root: UIViewController
        switch layoutSettings.layout {
        case .reading:
            root = UINavigationController(rootViewController: PostListRouter.createModule())
        case .tabs:
            root = MainTabBarController()
        }
        rootViewController = root
        PushNotificationDeepLink.attach(self)
        return root
    }

    @MainActor
    func push(_ viewController: UIViewController) {
        navigationController?.pushViewController(viewController, animated: true)
    }

    /// 布局设置变化后直接替换根界面；登录态存在 Cookie 中，不受影响。
    private func applyCurrentLayout() {
        // 开屏动画期间根界面还没建好，结束时会按新设置构建
        guard let window, let current = window.rootViewController, current === rootViewController else { return }
        let replaceRoot = { [weak self, weak window] in
            guard let self, let window else { return }
            let newRoot = self.makeRootViewController()
            UIView.transition(
                with: window,
                duration: 0.3,
                options: [.transitionCrossDissolve, .allowAnimatedContent],
                animations: {
                    UIView.performWithoutAnimation {
                        window.rootViewController = newRoot
                    }
                }
            )
        }
        if current.presentedViewController != nil {
            current.dismiss(animated: true, completion: replaceRoot)
        } else {
            replaceRoot()
        }
    }
}
