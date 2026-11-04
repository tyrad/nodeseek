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
        appRouter.window = window
        let launchedFromPush = connectionOptions.notificationResponse != nil
        window.rootViewController = appRouter.makeRootViewController()
        window.makeKeyAndVisible()
        self.window = window

        // 窗口显示后异步预热 WebView，供验证页回退使用；推送冷启动不弹引导，避免挡住跳转。
        DispatchQueue.main.async { [weak self, weak window] in
            NodeSeekWebViewPrewarmer.prewarm()
            guard !launchedFromPush, let self, let window, let root = window.rootViewController else { return }
            self.presentOnboarding(from: root, in: window)
        }

        if let response = connectionOptions.notificationResponse {
            PushNotificationDeepLink.handle(userInfo: response.notification.request.content.userInfo)
        }
    }

    private func presentOnboarding(from root: UIViewController, in window: UIWindow) {
        // 同一次启动只呈现一个引导；根界面已更换或已有弹窗时不抢占。
        guard window.rootViewController === root, root.presentedViewController == nil else { return }
        if !LayoutChooserViewController.presentIfNeeded(from: root) {
            WhatsNewModule.presentIfNeeded(from: root)
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
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}
