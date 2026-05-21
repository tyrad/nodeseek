//
//  SceneDelegate.swift
//  nodeseek
//
//  Created by mist on 2026/4/27.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    var autoCheckInRunner: @MainActor (UIViewController?) async -> Void = { presentationContext in
        await AutoCheckInModule.runIfNeeded(presentationContext: presentationContext)
    }


    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        let appRouter = AppRouter()
        window.rootViewController = NodeSeekSplashViewController { [weak self, weak window] in
            guard let window else { return }
            UIView.performWithoutAnimation {
                window.rootViewController = appRouter.makeRootViewController()
                window.layoutIfNeeded()
            }
            self?.runAutoCheckInIfNeeded()
        }
        window.makeKeyAndVisible()
        self.window = window
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        runAutoCheckInIfNeeded()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        runAutoCheckInIfNeeded()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        VisitedPostStore.shared.flush()
    }

    func runAutoCheckInIfNeeded() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let presentationContext = self.window?.rootViewController
            guard (presentationContext is NodeSeekSplashViewController) == false else {
                AppLog.info(.autoCheckIn, "skip=presentation_splash")
                return
            }
            await autoCheckInRunner(presentationContext)
        }
    }

}
