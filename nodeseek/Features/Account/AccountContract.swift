//
//  AccountContract.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation
import UIKit

// MARK: - View Protocol (Presenter -> View)
protocol AccountViewProtocol: AnyObject {
    func showLoading()
    func hideLoading()
    func showError(message: String)
    func render(_ account: AccountResponse)
}

// MARK: - Presenter Protocol (View -> Presenter)
protocol AccountPresenterProtocol: AnyObject {
    func viewDidLoad()
    func didTapLogin()
}

// MARK: - Interactor Input (Presenter -> Interactor)
protocol AccountInteractorInput: AnyObject {
    func loadAccount()
}

// MARK: - Interactor Output (Interactor -> Presenter)
protocol AccountInteractorOutput: AnyObject {
    func didLoadAccount(_ response: AccountResponse)
    func didFailLoadAccount(error: String)
}

// MARK: - Router Protocol (Presenter -> Router)
protocol AccountRouterProtocol: AnyObject {
    func navigateToLogin(onClose: @escaping @MainActor () -> Void)
}
