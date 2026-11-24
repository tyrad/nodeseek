import SafariServices
import UIKit

@MainActor
final class AppDeepLinkRouter {
    private var pending: (route: AppDeepLink, url: URL)?
    private weak var lastPage: UIViewController?
    private var lastURL: String?
    private var composeTask: Task<Void, Never>?

    /// 清理旧会话期间 Scene 可能已收到新链接，优先打开最后一次点按的地址。
    func openPending(in app: AppRouter) -> Bool {
        guard let pending else { return false }
        self.pending = nil
        open(pending.route, url: pending.url, in: app)
        return true
    }

    func open(_ route: AppDeepLink, url: URL, in app: AppRouter) {
        guard let nav = app.navigationController, let top = nav.topViewController else {
            pending = (route, url)
            return
        }
        guard nav.presentedViewController == nil, !(top is LoginWebViewController) else { return }
        let visible = (top as? UITabBarController)?.selectedViewController ?? top
        if visible === lastPage, lastURL == url.absoluteString { return }
        composeTask?.cancel()
        switch route {
        case let .post(id, page, floor, target):
            app.open(.reply(postID: id, page: page, floor: floor, url: target))
        case let .probe(link):
            app.open(.probe(link))
        case let .externalWebPage(target):
            nav.present(SFSafariViewController(url: target), animated: true)
            return
        case let .user(uid):
            app.push(UserProfileViewController(uid: uid))
        case let .search(query, scope):
            let search: SearchViewController
            if let tabs = top as? MainTabBarController, tabs.tabItems.contains(.search) {
                tabs.select(.search)
                guard let selected = tabs.selectedViewController as? SearchViewController else { return }
                search = selected
            } else if let current = top as? SearchViewController {
                search = current
            } else {
                search = SearchViewController()
                app.push(search)
            }
            search.submitDeepLinkSearch(query: query, scope: scope == .user ? .user : .post)
            lastPage = search
            lastURL = url.absoluteString
            return
        case let .compose(title, body):
            composeTask = Task { [weak app, weak nav, weak top] in
                // 模拟器和真机都可能留有过期的账号快照，预填前确认当前会话。
                let account = await CurrentAccountRefresher.shared.refreshIfNeeded(maxAge: 60)
                guard !Task.isCancelled, let nav, let top, nav === app?.navigationController,
                      nav.topViewController === top, nav.presentedViewController == nil else { return }
                guard account?.isLoggedIn == true else {
                    LoginWebViewController.open(from: top)
                    return
                }
                let editor = NewDiscussionRouter.createModule(initialDraft: .init(title: title, content: body)) { [weak app] route in
                    guard let route else { return }
                    app?.open(.reply(postID: route.postID, page: route.page, floor: route.anchorID, url: route.url))
                }
                nav.present(editor, animated: true)
            }
            return
        }
        lastPage = nav.topViewController
        lastURL = url.absoluteString
    }
}
