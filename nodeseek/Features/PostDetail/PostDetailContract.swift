//
//  PostDetailContract.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation
import UIKit

// MARK: - View Protocol (Presenter -> View)
protocol PostDetailViewProtocol: AnyObject {
    func showLoading()
    func hideLoading()
    func showError(message: String)
    func render(detail: PostDetail)
    func renderLoginRequired(message: String)
}

// MARK: - Presenter Protocol (View -> Presenter)
protocol PostDetailPresenterProtocol: AnyObject {
    func viewDidLoad()
    func didTapLogin()
}

// MARK: - Interactor Input (Presenter -> Interactor)
protocol PostDetailInteractorInput: AnyObject {
    func loadPostDetail()
}

// MARK: - Interactor Output (Interactor -> Presenter)
protocol PostDetailInteractorOutput: AnyObject {
    func didLoadPostDetail(_ response: PostDetailResponse)
    func didRequireLogin(message: String)
    func didFailLoadPostDetail(error: String)
}

// MARK: - Router Protocol (Presenter -> Router)
protocol PostDetailRouterProtocol: AnyObject {
    func navigateToLogin(onClose: @escaping @MainActor () -> Void)
}
