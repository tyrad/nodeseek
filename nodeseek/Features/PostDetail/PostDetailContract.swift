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
    func showPageLoading()
    func hideLoading()
    func showError(message: String)
    func showToast(message: String)
    func setCommentComposerSubmitting(_ isSubmitting: Bool)
    func clearCommentComposer()
    func render(detail: PostDetail)
    func renderLoginRequired(message: String)
}

// MARK: - Presenter Protocol (View -> Presenter)
protocol PostDetailPresenterProtocol: AnyObject {
    func viewDidLoad()
    func didTapLogin()
    func didSelectPage(_ page: Int)
    func didSubmitComment(content: String)
}

// MARK: - Interactor Input (Presenter -> Interactor)
protocol PostDetailInteractorInput: AnyObject {
    func loadPostDetail()
    func loadPostDetail(page: Int)
    func submitComment(content: String, completion: @escaping @MainActor (Result<CommentSubmitResponse, Error>) -> Void)
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
