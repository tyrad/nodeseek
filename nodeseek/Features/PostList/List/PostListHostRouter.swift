//
//  PostListHostRouter.swift
//  nodeseek
//

import Foundation

final class PostListHostRouter: PostListHostRouterProtocol {
    private init() {}

    static func createModule(
        category: PostListCategoryItem,
        visitedStore: VisitedPostStoreProtocol = EmptyVisitedPostStore(),
        delegate: PostListHostPresenterDelegate? = nil
    ) -> PostListHostViewController {
        let interactor = PostListInteractor()
        let presenter = PostListHostPresenter(
            category: category,
            interactor: interactor,
            visitedStore: visitedStore
        )
        presenter.delegate = delegate

        let view = PostListHostViewController(
            category: category,
            presenter: presenter
        )

        presenter.setView(view)
        return view
    }
}
