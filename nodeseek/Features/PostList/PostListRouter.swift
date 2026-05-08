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
        let interactor = PostListInteractor()
        let presenter = PostListPresenter(
            interactor: interactor,
            router: router,
            visitedStore: VisitedPostStore.shared
        )
        
        interactor.presenter = presenter
        
        let view = PostListViewController(presenter: presenter)
        
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
        show(NewDiscussionWebViewController())
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
