//
//  AppRouter.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import UIKit

final class AppRouter {

    private(set) weak var navigationController: UINavigationController?

    func makeRootViewController() -> UIViewController {
        let navigationController = UINavigationController(rootViewController: PostListRouter.createModule())
        self.navigationController = navigationController
        PushNotificationDeepLink.attach(self)
        return navigationController
    }

    @MainActor
    func push(_ viewController: UIViewController) {
        navigationController?.pushViewController(viewController, animated: true)
    }
}
