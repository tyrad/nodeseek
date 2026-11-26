//
//  SceneDelegate.swift
//  nodeseek
//
//  Created by mist on 2026/4/27.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    private var launchTask: Task<Void, Never>?
    private let appRouter = AppRouter()
    private let deepLinkRouter = AppDeepLinkRouter()

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        self.window = window
        let appDelegate = UIApplication.shared.delegate as? AppDelegate
        if let preparation = appDelegate?.accountLaunchPreparation ?? appDelegate?.logoutCleanup {
            // 系统启动屏退场前先显示同款底色和标志。账号恢复完成后再创建业务页面。
            let logo = UIImageView(image: UIImage(named: "SplashLogo"))
            logo.backgroundColor = UIColor(named: "SplashBackground")
            logo.contentMode = .center
            let placeholder = UIViewController()
            placeholder.view = logo
            window.rootViewController = placeholder
            launchTask = Task { @MainActor [weak self] in
                await preparation.value
                guard !Task.isCancelled else { return }
                self?.showRoot(in: window, options: connectionOptions)
            }
        } else {
            showRoot(in: window, options: connectionOptions)
        }
        window.makeKeyAndVisible()
    }

    private func showRoot(in window: UIWindow, options connectionOptions: UIScene.ConnectionOptions) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-DetailTextKitPrototype") {
            window.rootViewController = UINavigationController(rootViewController: DetailMarkdownPrototypeController.demo())
            return
        }
        #endif
        appRouter.window = window
        let launchedFromPush = connectionOptions.notificationResponse != nil || !connectionOptions.urlContexts.isEmpty
        window.rootViewController = appRouter.makeRootViewController()

        // 窗口显示后异步预热 WebView，供验证页回退使用；推送冷启动不弹引导，避免挡住跳转。
        DispatchQueue.main.async { [weak self, weak window] in
            NodeSeekWebViewPrewarmer.prewarm()
            guard !launchedFromPush, let self, let window, let root = window.rootViewController else { return }
            self.presentOnboarding(from: root, in: window)
        }

        if let response = connectionOptions.notificationResponse {
            PushNotificationDeepLink.handle(response)
        }
        if !deepLinkRouter.openPending(in: appRouter) {
            handle(urlContexts: connectionOptions.urlContexts)
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        handle(urlContexts: URLContexts)
    }

    private func handle(urlContexts: Set<UIOpenURLContext>) {
        for context in urlContexts {
            guard let route = AppDeepLink.route(for: context.url) else { continue }
            deepLinkRouter.open(route, url: context.url, in: appRouter)
            return
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
        launchTask?.cancel()
        launchTask = nil
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await launchTask?.value
            guard scene.activationState == .foregroundActive else { return }
            guard let presentationContext = self.autoCheckInPresentationContext() else { return }
            await AutoCheckInModule.runIfNeeded(
                presentationContext: presentationContext,
                trigger: .sceneBecomeActive
            )
        }
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
