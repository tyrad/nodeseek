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
        let detailViewController = PostDetailRouter.createModule(post: post, page: page)
        viewController?.navigationController?.pushViewController(detailViewController, animated: true)
    }

    func navigateToLogin(onClose: @escaping @MainActor () -> Void) {
        let loginViewController = LoginWebViewController(onClose: onClose)
        if let navigationController = viewController?.navigationController {
            navigationController.pushViewController(loginViewController, animated: true)
            return
        }

        let navigationWrapper = UINavigationController(rootViewController: loginViewController)
        viewController?.present(navigationWrapper, animated: true)
    }

    func navigateToRecentVisitedPosts(visitedStore: VisitedPostStoreProtocol) {
        let recentViewController = RecentVisitedPostsViewController(visitedStore: visitedStore)
        recentViewController.onSelectRecord = { [weak self, weak recentViewController] record in
            let post = Self.postSummary(from: record)
            let page = Self.page(from: record.url)
            let detailViewController = PostDetailRouter.createModule(post: post, page: page)
            if let navigationController = recentViewController?.navigationController {
                navigationController.pushViewController(detailViewController, animated: true)
                return
            }
            self?.viewController?.navigationController?.pushViewController(detailViewController, animated: true)
        }

        if let navigationController = viewController?.navigationController {
            navigationController.pushViewController(recentViewController, animated: true)
            return
        }

        let navigationWrapper = UINavigationController(rootViewController: recentViewController)
        viewController?.present(navigationWrapper, animated: true)
    }

    #if DEBUG
    func navigateToLogFile() {
        let logViewController = LogFileViewController()
        if let navigationController = viewController?.navigationController {
            navigationController.pushViewController(logViewController, animated: true)
            return
        }

        let navigationWrapper = UINavigationController(rootViewController: logViewController)
        viewController?.present(navigationWrapper, animated: true)
    }
    #endif

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

    private static func page(from url: URL) -> Int {
        let components = url.lastPathComponent.split(separator: "-")
        guard components.count >= 3,
              components.first == "post",
              let page = Int(components[2]) else {
            return 1
        }
        return max(page, 1)
    }

}
