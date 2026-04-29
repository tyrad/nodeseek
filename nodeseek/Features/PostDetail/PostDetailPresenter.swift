//
//  PostDetailPresenter.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation

class PostDetailPresenter: PostDetailPresenterProtocol {
    
    // MARK: - Properties
    private weak var view: PostDetailViewProtocol?
    private let interactor: PostDetailInteractorInput
    private let router: PostDetailRouterProtocol
    
    // MARK: - Initialization
    init(
        interactor: PostDetailInteractorInput,
        router: PostDetailRouterProtocol
    ) {
        self.interactor = interactor
        self.router = router
    }
    
    // MARK: - Setup
    func setView(_ view: PostDetailViewProtocol) {
        self.view = view
    }
    
    // MARK: - Methods
    func viewDidLoad() {
        view?.showLoading()
        interactor.loadPostDetail()
    }

    func didTapLogin() {
        router.navigateToLogin { [weak self] in
            self?.view?.showLoading()
            self?.interactor.loadPostDetail()
        }
    }
}

// MARK: - Interactor Output
extension PostDetailPresenter: PostDetailInteractorOutput {
    
    func didLoadPostDetail(_ response: PostDetailResponse) {
        view?.hideLoading()
        view?.render(detail: response.detail)
    }

    func didRequireLogin(message: String) {
        view?.hideLoading()
        view?.renderLoginRequired(message: message)
    }
    
    func didFailLoadPostDetail(error: String) {
        view?.hideLoading()
        view?.showError(message: error)
    }
}
