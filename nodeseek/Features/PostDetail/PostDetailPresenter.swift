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
    private let visitedStore: VisitedPostStoreProtocol
    private var currentPage: Int
    private var loadingPage: Int?
    private var currentDetail: PostDetail?
    private var isSubmittingReply = false
    private var isRefreshingAfterReplySubmission = false
    
    // MARK: - Initialization
    init(
        interactor: PostDetailInteractorInput,
        router: PostDetailRouterProtocol,
        initialPage: Int = 1,
        visitedStore: VisitedPostStoreProtocol = EmptyVisitedPostStore()
    ) {
        self.interactor = interactor
        self.router = router
        self.visitedStore = visitedStore
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

    func didTapSendReply(content: String) {
        guard isSubmittingReply == false else { return }

        let normalizedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedContent.isEmpty == false else {
            view?.showError(message: "回复内容不能为空。")
            return
        }

        isSubmittingReply = true
        view?.setReplySubmitting(true)
        interactor.submitReply(content: normalizedContent)
    }

    private func markDetailVisited(_ detail: PostDetail) {
        let page = max(1, detail.page)
        let url = NodeSeekSite.postURL(id: detail.id, page: page)

        let post = PostSummary(
            id: detail.id,
            title: detail.title,
            url: url,
            authorName: detail.authorName,
            nodeName: nil,
            replyCount: detail.comments.count,
            viewCount: 0,
            lastActivityText: detail.metadataText,
            avatarURL: detail.avatarURL
        )
        visitedStore.markVisited(post: post, visitedAt: Date())
    }
}

// MARK: - Interactor Output
extension PostDetailPresenter: PostDetailInteractorOutput {
    
    func didLoadPostDetail(_ response: PostDetailResponse) {
        loadingPage = nil
        isRefreshingAfterReplySubmission = false
        currentPage = max(1, response.detail.page)
        currentDetail = response.detail
        markDetailVisited(response.detail)
        view?.hideLoading()
        view?.render(detail: response.detail)
    }

    func didRequireLogin(message: String) {
        loadingPage = nil
        isRefreshingAfterReplySubmission = false
        view?.hideLoading()
        view?.renderLoginRequired(message: message)
    }
    
    func didFailLoadPostDetail(error: String) {
        let isReplyRefresh = isRefreshingAfterReplySubmission
        loadingPage = nil
        isRefreshingAfterReplySubmission = false
        view?.hideLoading()
        if isReplyRefresh == false {
            view?.showError(message: error)
        }
    }

    func didCancelLoadPostDetail() {
        loadingPage = nil
        isRefreshingAfterReplySubmission = false
        view?.hideLoading()
    }

    func didSubmitReply(_ response: PostDetailSubmitReplyResponse) {
        isSubmittingReply = false
        view?.setReplySubmitting(false)
        view?.finishReplySubmission()

        let responseMessage = response.message?.trimmingCharacters(in: .whitespacesAndNewlines)
        if currentDetail?.isLastPage == true {
            let toastMessage: String
            if let responseMessage, responseMessage.isEmpty == false {
                toastMessage = responseMessage
            } else {
                toastMessage = "评论已发布"
            }
            view?.showToast(message: toastMessage)
            isRefreshingAfterReplySubmission = true
            interactor.loadPostDetail(page: currentPage)
        } else {
            view?.showToast(message: "评论已发布，可到最后一页查看")
        }
    }

    func didFailSubmitReply(error: String) {
        isSubmittingReply = false
        view?.setReplySubmitting(false)
        view?.showError(message: error)
    }
}
