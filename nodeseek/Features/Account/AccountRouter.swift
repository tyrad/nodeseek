//
//  AccountRouter.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation
import UIKit

class AccountRouter: AccountRouterProtocol {
    
    // MARK: - Properties
    weak var viewController: UIViewController?
    
    // MARK: - Static Methods
    static func createModule() -> UIViewController {
        let router = AccountRouter()
        let interactor = AccountInteractor()
        let presenter = AccountPresenter(
            interactor: interactor,
            router: router
        )
        
        interactor.presenter = presenter
        
        let view = AccountViewController(presenter: presenter)
        
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
