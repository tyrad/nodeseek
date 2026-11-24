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
    static func createModule(
        post: PostSummary? = nil,
        page: Int = 1,
        initialAnchorID: String? = nil
    ) -> UIViewController {
        let router = PostDetailRouter()
        let interactor = PostDetailInteractor(
            post: post,
            actionPagePreparer: WebViewPostActionPagePreparer(),
            page: page
        )
        let presenter = PostDetailPresenter(
            interactor: interactor,
            router: router,
            initialPage: page,
            visitedStore: VisitedPostStore.shared
        )
        
        interactor.presenter = presenter
        
        let view = PostDetailViewController(
            presenter: presenter,
            initialHeader: post.map(PostDetailHeaderContent.init(post:)),
            sourcePostURL: post?.url,
            currentPage: page,
            initialAnchorID: initialAnchorID
        )
        
        presenter.setView(view)
        router.viewController = view
        
        return view
    }

    func presentEditPost(_ editable: EditableDiscussion, onSaved: @escaping () -> Void) {
        let editor = NewDiscussionRouter.createEditModule(editable: editable, onSaved: onSaved)
        viewController?.present(editor, animated: true)
    }

    func presentEditComment(_ editable: EditableComment, onSaved: @escaping () -> Void) {
        let editor = NewDiscussionRouter.createEditModule(editable: editable, onSaved: onSaved)
        viewController?.present(editor, animated: true)
    }

    func navigateToLogin(onClose: @escaping @MainActor () -> Void) {
        LoginWebViewController.open(from: viewController, onClose: onClose)
    }
}
