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
    static func createModule(post: PostSummary? = nil) -> UIViewController {
        let router = PostDetailRouter()
        let interactor = PostDetailInteractor(post: post)
        let presenter = PostDetailPresenter(
            interactor: interactor,
            router: router
        )
        
        interactor.presenter = presenter
        
        let view = PostDetailViewController(
            presenter: presenter,
            initialHeader: post.map(PostDetailHeaderContent.init(post:))
        )
        
        presenter.setView(view)
        router.viewController = view
        
        return view
    }
}
