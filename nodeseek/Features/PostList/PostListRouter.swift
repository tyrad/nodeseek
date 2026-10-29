//
//  PostListRouter.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import UIKit

class PostListRouter: PostListRouterProtocol {
    
    // MARK: - Properties
    weak var viewController: UIViewController?
    
    // MARK: - Static Methods
    static func createModule() -> UIViewController {
        let router = PostListRouter()
        let presenter = PostListPresenter(
            router: router,
            visitedStore: VisitedPostStore.shared
        )
        
        let view = PostListViewController(
            presenter: presenter,
            visitedStore: VisitedPostStore.shared
        )
        
        presenter.setView(view)
        router.viewController = view
        
        return view
    }
    
    // MARK: - Navigation
    func navigateToPostDetail(post: PostSummary) {
        navigateToPostDetail(post: post, page: 1)
    }

    func navigateToPostDetail(post: PostSummary, page: Int) {
        navigateToPostDetail(post: post, page: page, initialAnchorID: nil)
    }

    func navigateToPostDetail(post: PostSummary, page: Int, initialAnchorID: String?) {
        let detailViewController = PostDetailRouter.createModule(
            post: post,
            page: page,
            initialAnchorID: initialAnchorID
        )
        viewController?.navigationController?.pushViewController(detailViewController, animated: true)
    }

    func navigateToLogin(onClose: @escaping @MainActor () -> Void) {
        let loginViewController = LoginWebViewController(onClose: onClose)
        show(loginViewController)
    }

    func navigateToUserProfile(profileURL: URL) {
        show(UserInfoWebViewController(profileURL: profileURL))
    }

    func navigateToNewDiscussion() {
        AppLog.info(.postList, "Router 开始导航到原生发帖页")
        let composer = NewDiscussionRouter.createModule { [weak self] route in
            self?.openPublishedDiscussion(route: route)
        }
        viewController?.present(composer, animated: true)
        AppLog.info(.postList, "Router 已触发发帖页展示")
    }

    /// 发帖成功：能解析出新帖地址就直接打开，否则留在列表由用户下拉刷新。
    private func openPublishedDiscussion(route: NodeSeekPostRoute?) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        guard let route else {
            AppLog.warning(.postList, "发帖成功但没有解析出新帖地址")
            return
        }
        let post = PostSummary(
            id: route.postID,
            title: "",
            url: route.url,
            authorName: "",
            nodeName: nil,
            replyCount: 0,
            lastActivityText: nil
        )
        let detailViewController = PostDetailRouter.createModule(post: post, page: route.page, initialAnchorID: nil)
        viewController?.navigationController?.pushViewController(detailViewController, animated: true)
    }

    func navigateToCheckIn(boardURL: URL) {
        show(UserInfoWebViewController(profileURL: boardURL, title: "签到"))
    }

    func navigateToNotification(notificationURL: URL) {
        show(NotificationViewController())
    }

    func navigateToSearch() {
        show(SearchViewController())
    }

    func navigateToPostCategoryPreferences() {
        show(PostCategoryPreferencesViewController())
    }

    func navigateToRecentVisitedPosts(visitedStore: VisitedPostStoreProtocol) {
        let recentViewController = RecentVisitedPostsViewController(visitedStore: visitedStore)
        recentViewController.onSelectRecord = { [weak self, weak recentViewController] record in
            let post = Self.postSummary(from: record)
            let detailViewController = PostDetailRouter.createModule(
                post: post,
                page: 1,
                initialAnchorID: nil
            )
            if let navigationController = recentViewController?.navigationController {
                navigationController.pushViewController(detailViewController, animated: true)
                return
            }
            self?.viewController?.navigationController?.pushViewController(detailViewController, animated: true)
        }

        show(recentViewController)
    }

    func navigateToUserDiscussions() {
        let viewController = UserDiscussionsViewController()
        viewController.onSelectPost = { [weak self, weak viewController] post, page, anchorID in
            self?.pushPostDetail(post: post, page: page, anchorID: anchorID, from: viewController)
        }
        show(viewController)
    }

    func navigateToUserComments() {
        let viewController = UserCommentsViewController()
        viewController.onSelectPost = { [weak self, weak viewController] post, page, anchorID in
            self?.pushPostDetail(post: post, page: page, anchorID: anchorID, from: viewController)
        }
        show(viewController)
    }

    func navigateToUserCollections() {
        let viewController = UserCollectionsViewController()
        viewController.onSelectPost = { [weak self, weak viewController] post, page, anchorID in
            self?.pushPostDetail(post: post, page: page, anchorID: anchorID, from: viewController)
        }
        show(viewController)
    }

    func navigateToSettings(
        onLogout: @escaping @MainActor () -> Void,
        onLogFile: @escaping @MainActor () -> Void,
        onDetailTest: (@MainActor () -> Void)?
    ) {
        show(SettingsViewController(
            onLogout: onLogout,
            onLogFile: onLogFile,
            onDetailTest: onDetailTest
        ))
    }

    func navigateToLogFile() {
        show(LogFileViewController())
    }

    private func show(_ targetViewController: UIViewController) {
        if let navigationController = viewController?.navigationController {
            navigationController.pushViewController(targetViewController, animated: true)
            return
        }

        let navigationWrapper = UINavigationController(rootViewController: targetViewController)
        viewController?.present(navigationWrapper, animated: true)
    }

    private func pushPostDetail(
        post: PostSummary,
        page: Int,
        anchorID: String?,
        from sourceViewController: UIViewController?
    ) {
        let detailViewController = PostDetailRouter.createModule(
            post: post,
            page: page,
            initialAnchorID: anchorID
        )
        if let navigationController = sourceViewController?.navigationController {
            navigationController.pushViewController(detailViewController, animated: true)
            return
        }
        viewController?.navigationController?.pushViewController(detailViewController, animated: true)
    }

    private static func postSummary(from record: VisitedPostRecord) -> PostSummary {
        PostSummary(
            id: record.postID,
            title: record.title,
            url: record.url,
            authorName: "",
            nodeName: nil,
            replyCount: 0,
            lastActivityText: nil,
            avatarURL: record.avatarURL
        )
    }

}
