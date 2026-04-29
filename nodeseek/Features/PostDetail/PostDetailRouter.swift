//
//  PostDetailRouter.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation
import UIKit

class PostDetailRouter: PostDetailRouterProtocol {
    
    // MARK: - Properties
    weak var viewController: UIViewController?
    
    // MARK: - Static Methods
    static func createModule(post: PostSummary? = nil, page: Int = 1) -> UIViewController {
        let router = PostDetailRouter()
        let interactor = PostDetailInteractor(post: post, page: page)
        let presenter = PostDetailPresenter(
            interactor: interactor,
            router: router
        )
        
        interactor.presenter = presenter
        
        let view = PostDetailViewController(
            presenter: presenter,
            initialHeader: post.map(PostDetailHeaderContent.init(post:)),
            sourcePostURL: post?.url,
            currentPage: page
        )
        
        presenter.setView(view)
        router.viewController = view
        
        return view
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
