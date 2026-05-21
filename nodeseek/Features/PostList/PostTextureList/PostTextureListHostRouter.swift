//
//  PostTextureListHostRouter.swift
//  nodeseek
//

import Foundation

final class PostTextureListHostRouter: PostTextureListHostRouterProtocol {
    private init() {}

    static func createModule(
        category: PostListCategoryItem,
        visitedStore: VisitedPostStoreProtocol = EmptyVisitedPostStore(),
        delegate: PostTextureListHostPresenterDelegate? = nil
    ) -> PostTextureListHostViewController {
        let interactor = PostTextureListInteractor()
        let presenter = PostTextureListHostPresenter(
            category: category,
            interactor: interactor,
            visitedStore: visitedStore
        )
        presenter.delegate = delegate

        let view = PostTextureListHostViewController(
            category: category,
            presenter: presenter
        )

        presenter.setView(view)
        return view
    }
}
