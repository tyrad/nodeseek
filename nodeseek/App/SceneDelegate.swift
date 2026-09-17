//
//  SceneDelegate.swift
//  nodeseek
//
//  Created by mist on 2026/4/27.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    private let appRouter = AppRouter()

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        let launchedFromPush = connectionOptions.notificationResponse != nil
        if launchedFromPush {
            window.rootViewController = appRouter.makeRootViewController()
        } else {
            window.rootViewController = NodeSeekSplashViewController { [weak window, appRouter] in
                guard let window else { return }
                UIView.performWithoutAnimation {
                    window.rootViewController = appRouter.makeRootViewController()
                    window.layoutIfNeeded()
                }
            }
        }
        window.makeKeyAndVisible()
        self.window = window

        if let response = connectionOptions.notificationResponse {
            PushNotificationDeepLink.handle(userInfo: response.notification.request.content.userInfo)
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let presentationContext = self.autoCheckInPresentationContext() else { return }
            await AutoCheckInModule.runIfNeeded(
                presentationContext: presentationContext,
                trigger: .sceneBecomeActive
            )
        }
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        VisitedPostStore.shared.flush()
    }

    private func autoCheckInPresentationContext() -> UIViewController? {
        var controller = window?.rootViewController
        guard let root = controller, (root is NodeSeekSplashViewController) == false else {
            return nil
        }
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}
