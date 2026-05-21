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
        AppLog.info(.postList, "Router 开始导航到发帖页")
        show(NewDiscussionWebViewController())
        AppLog.info(.postList, "Router 已触发发帖页展示")
    }

    func navigateToCheckIn(boardURL: URL) {
        show(UserInfoWebViewController(profileURL: boardURL, title: "签到"))
    }

    func navigateToNotification(notificationURL: URL) {
        show(UserInfoWebViewController(profileURL: notificationURL, title: "通知"))
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
