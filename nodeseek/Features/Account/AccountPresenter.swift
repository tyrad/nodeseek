//
//  AccountPresenter.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation

class AccountPresenter: AccountPresenterProtocol {
    
    // MARK: - Properties
    private weak var view: AccountViewProtocol?
    private let interactor: AccountInteractorInput
    private let router: AccountRouterProtocol
    
    // MARK: - Initialization
    init(
        interactor: AccountInteractorInput,
        router: AccountRouterProtocol
    ) {
        self.interactor = interactor
        self.router = router
    }
    
    // MARK: - Setup
    func setView(_ view: AccountViewProtocol) {
        self.view = view
    }
    
    // MARK: - Methods
    func viewDidLoad() {
        view?.showLoading()
        interactor.loadAccount()
    }

    func didTapLogin() {
        router.navigateToLogin { [weak self] in
            self?.view?.showLoading()
            self?.interactor.loadAccount()
        }
    }
}

// MARK: - Interactor Output
extension AccountPresenter: AccountInteractorOutput {
    
    func didLoadAccount(_ response: AccountResponse) {
        view?.hideLoading()
        view?.render(response)
    }
    
    func didFailLoadAccount(error: String) {
        view?.hideLoading()
        view?.showError(message: error)
    }
}
