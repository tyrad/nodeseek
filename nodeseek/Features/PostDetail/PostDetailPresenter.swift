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
    private var currentPage: Int
    private var loadingPage: Int?
    private var currentDetail: PostDetail?
    private var isSubmittingComment = false
    
    // MARK: - Initialization
    init(
        interactor: PostDetailInteractorInput,
        router: PostDetailRouterProtocol,
        initialPage: Int = 1
    ) {
        self.interactor = interactor
        self.router = router
        self.currentPage = max(1, initialPage)
    }
    
    // MARK: - Setup
    func setView(_ view: PostDetailViewProtocol) {
        self.view = view
    }
    
    // MARK: - Methods
    func viewDidLoad() {
        view?.showLoading()
        interactor.loadPostDetail(page: currentPage)
    }

    func didTapLogin() {
        router.navigateToLogin { [weak self] in
            self?.view?.showLoading()
            guard let self else { return }
            self.interactor.loadPostDetail(page: self.currentPage)
        }
    }

    func didSelectPage(_ page: Int) {
        let normalizedPage = max(1, page)
        guard normalizedPage != currentPage else { return }
        guard normalizedPage != loadingPage else { return }
        loadingPage = normalizedPage
        view?.showPageLoading()
        interactor.loadPostDetail(page: normalizedPage)
    }

    func didSubmitComment(content: String) {
        guard isSubmittingComment == false else { return }

        let normalizedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedContent.isEmpty else {
            view?.showError(message: "评论内容不能为空。")
            return
        }

        isSubmittingComment = true
        view?.setCommentComposerSubmitting(true)
        interactor.submitComment(content: normalizedContent) { [weak self] result in
            guard let self else { return }
            self.isSubmittingComment = false
            self.view?.setCommentComposerSubmitting(false)
            switch result {
            case .success(let response):
                self.view?.clearCommentComposer()
                if let message = response.message, !message.isEmpty {
                    self.view?.showToast(message: message)
                }
                if self.currentDetail?.isLastPage == true {
                    self.interactor.loadPostDetail(page: self.currentPage)
                } else {
                    self.view?.showToast(message: "评论已发布，可到最后一页查看")
                }
            case .failure(let error):
                self.view?.showError(message: error.localizedDescription)
            }
        }
    }
}

// MARK: - Interactor Output
extension PostDetailPresenter: PostDetailInteractorOutput {
    
    func didLoadPostDetail(_ response: PostDetailResponse) {
        loadingPage = nil
        currentPage = max(1, response.detail.page)
        currentDetail = response.detail
        view?.hideLoading()
        view?.render(detail: response.detail)
    }

    func didRequireLogin(message: String) {
        loadingPage = nil
        view?.hideLoading()
        view?.renderLoginRequired(message: message)
    }
    
    func didFailLoadPostDetail(error: String) {
        loadingPage = nil
        view?.hideLoading()
        view?.showError(message: error)
    }
}
