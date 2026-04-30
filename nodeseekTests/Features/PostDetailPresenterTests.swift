//
//  PostDetailPresenterTests.swift
//  nodeseekTests
//

import Testing
@testable import nodeseek

@MainActor
struct PostDetailPresenterTests {
    @Test func loginCloseReloadsPostDetail() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let presenter = PostDetailPresenter(interactor: interactor, router: router, initialPage: 3)

        presenter.didTapLogin()

        #expect(router.navigateToLoginCount == 1)
        #expect(interactor.loadedPages.isEmpty)

        router.capturedOnClose?()

        #expect(interactor.loadedPages == [3])
    }

    @Test func selectingOtherPageReloadsThatPage() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let view = SpyPostDetailView()
        let presenter = PostDetailPresenter(interactor: interactor, router: router, initialPage: 1)
        presenter.setView(view)

        presenter.didSelectPage(2)

        #expect(interactor.loadedPages == [2])
        #expect(view.pageLoadingCount == 1)
        #expect(view.loadingCount == 0)
    }

    @Test func selectingCurrentPageDoesNotReload() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let presenter = PostDetailPresenter(interactor: interactor, router: router, initialPage: 2)

        presenter.didSelectPage(2)

        #expect(interactor.loadedPages.isEmpty)
    }

    @Test func selectingPageInFlightDoesNotDuplicateRequest() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let presenter = PostDetailPresenter(interactor: interactor, router: router, initialPage: 1)

        presenter.didSelectPage(2)
        presenter.didSelectPage(2)

        #expect(interactor.loadedPages == [2])
    }

    @Test func selectingFailedPageCanRetry() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let presenter = PostDetailPresenter(interactor: interactor, router: router, initialPage: 1)

        presenter.didSelectPage(2)
        presenter.didFailLoadPostDetail(error: "网络错误")
        presenter.didSelectPage(2)

        #expect(interactor.loadedPages == [2, 2])
    }

    @Test func commentSubmitSuccessReloadsWhenCurrentDetailIsLastPage() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let presenter = PostDetailPresenter(interactor: interactor, router: router)
        let view = SpyPostDetailView()
        presenter.setView(view)
        presenter.didLoadPostDetail(PostDetailResponse(detail: PostDetail(
            id: "706958",
            title: "标题",
            authorName: "mist",
            avatarURL: nil,
            metadataText: nil,
            contentHTML: "<p>正文</p>",
            comments: [],
            replyForm: nil,
            isLastPage: true
        )))

        presenter.didSubmitComment(content: "bdbd")
        interactor.capturedCommentCompletion?(.success(CommentSubmitResponse(message: nil)))

        #expect(interactor.submitCommentCount == 1)
        #expect(interactor.loadPostDetailCount == 1)
        #expect(view.clearComposerCount == 1)
        #expect(view.toastMessage == nil)
    }

    @Test func commentSubmitTogglesSubmittingStateAroundRequest() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let presenter = PostDetailPresenter(interactor: interactor, router: router)
        let view = SpyPostDetailView()
        presenter.setView(view)

        presenter.didSubmitComment(content: "bdbd")

        #expect(view.commentSubmittingStates == [true])

        interactor.capturedCommentCompletion?(.success(CommentSubmitResponse(message: nil)))

        #expect(view.commentSubmittingStates == [true, false])
    }

    @Test func commentSubmitSuccessShowsToastWhenCurrentDetailIsNotLastPage() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let presenter = PostDetailPresenter(interactor: interactor, router: router)
        let view = SpyPostDetailView()
        presenter.setView(view)
        presenter.didLoadPostDetail(PostDetailResponse(detail: PostDetail(
            id: "706958",
            title: "标题",
            authorName: "mist",
            avatarURL: nil,
            metadataText: nil,
            contentHTML: "<p>正文</p>",
            comments: [],
            replyForm: nil,
            isLastPage: false
        )))

        presenter.didSubmitComment(content: "bdbd")
        interactor.capturedCommentCompletion?(.success(CommentSubmitResponse(message: nil)))

        #expect(interactor.submitCommentCount == 1)
        #expect(interactor.loadPostDetailCount == 0)
        #expect(view.clearComposerCount == 1)
        #expect(view.toastMessage == "评论已发布，可到最后一页查看")
    }

    @Test func emptyCommentShowsErrorWithoutSubmitting() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let presenter = PostDetailPresenter(interactor: interactor, router: router)
        let view = SpyPostDetailView()
        presenter.setView(view)

        presenter.didSubmitComment(content: "  \n ")

        #expect(interactor.submitCommentCount == 0)
        #expect(view.errorMessage == "评论内容不能为空。")
    }
}

private final class SpyPostDetailInteractor: PostDetailInteractorInput {
    private(set) var loadedPages: [Int] = []
    private(set) var loadPostDetailCount = 0
    private(set) var submitCommentCount = 0
    var capturedCommentCompletion: ((Result<CommentSubmitResponse, Error>) -> Void)?

    func loadPostDetail() {
        loadPostDetail(page: 1)
    }

    func loadPostDetail(page: Int) {
        loadPostDetailCount += 1
        loadedPages.append(page)
    }

    func submitComment(content: String, completion: @escaping @MainActor (Result<CommentSubmitResponse, Error>) -> Void) {
        submitCommentCount += 1
        capturedCommentCompletion = completion
    }
}

private final class SpyPostDetailRouter: PostDetailRouterProtocol {
    private(set) var navigateToLoginCount = 0
    private(set) var capturedOnClose: (@MainActor () -> Void)?

    func navigateToLogin(onClose: @escaping @MainActor () -> Void) {
        navigateToLoginCount += 1
        capturedOnClose = onClose
    }
}

private final class SpyPostDetailView: PostDetailViewProtocol {
    private(set) var loadingCount = 0
    private(set) var pageLoadingCount = 0
    var errorMessage: String?
    var toastMessage: String?
    private(set) var commentSubmittingStates: [Bool] = []
    private(set) var clearComposerCount = 0

    func showLoading() { loadingCount += 1 }
    func showPageLoading() { pageLoadingCount += 1 }
    func hideLoading() {}
    func showError(message: String) { errorMessage = message }
    func showToast(message: String) { toastMessage = message }
    func setCommentComposerSubmitting(_ isSubmitting: Bool) { commentSubmittingStates.append(isSubmitting) }
    func clearCommentComposer() { clearComposerCount += 1 }
    func render(detail: PostDetail) {}
    func renderLoginRequired(message: String) {}
}
