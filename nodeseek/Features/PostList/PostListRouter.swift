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

}
