//
//  PostDetailPresenterTests.swift
//  nodeseekTests
//

import Foundation
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

    @Test func loadingDetailMarksPostAsVisited() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let visitedStore = SpyVisitedPostStore()
        let presenter = PostDetailPresenter(
            interactor: interactor,
            router: router,
            initialPage: 2,
            visitedStore: visitedStore
        )
        let detail = PostDetail(
            id: "706958",
            title: "详情标题",
            authorName: "mist",
            avatarURL: nil,
            metadataText: nil,
            contentHTML: "<p>正文</p>",
            comments: [],
            page: 2,
            isLastPage: true
        )

        presenter.didLoadPostDetail(PostDetailResponse(detail: detail))

        #expect(visitedStore.markedPosts.map(\.id) == ["706958"])
        #expect(visitedStore.markedPosts.first?.title == "详情标题")
        #expect(visitedStore.markedPosts.first?.url.absoluteString == "https://www.nodeseek.com/post-706958-2")
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

    @Test func replySubmissionSuccessFinishesComposerAndReloadsCurrentPage() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let presenter = PostDetailPresenter(interactor: interactor, router: router, initialPage: 2)
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
            page: 2,
            isLastPage: true
        )))

        presenter.didTapSendReply(content: "  测试回复  ")
        presenter.didSubmitReply(PostDetailSubmitReplyResponse(message: "已发布"))

        #expect(interactor.submittedReplyContent == "测试回复")
        #expect(view.replySubmittingStates == [true, false])
        #expect(view.finishReplySubmissionCount == 1)
        #expect(view.toastMessage == "已发布")
        #expect(interactor.loadedPages == [2])
        #expect(view.loadingCount == 0)
    }

    @Test func cancelledRefreshAfterReplySubmissionDoesNotShowError() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let presenter = PostDetailPresenter(interactor: interactor, router: router, initialPage: 2)
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
            page: 2,
            isLastPage: true
        )))

        presenter.didTapSendReply(content: "测试回复")
        presenter.didSubmitReply(PostDetailSubmitReplyResponse(message: "已发布"))
        presenter.didCancelLoadPostDetail()

        #expect(view.errorMessage == nil)
        #expect(view.toastMessage == "已发布")
        #expect(view.hideLoadingCount == 2)
    }

    @Test func cancelledNormalDetailLoadDoesNotShowError() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let presenter = PostDetailPresenter(interactor: interactor, router: router, initialPage: 1)
        let view = SpyPostDetailView()
        presenter.setView(view)

        presenter.didSelectPage(2)
        presenter.didCancelLoadPostDetail()

        #expect(view.errorMessage == nil)
        #expect(view.pageLoadingCount == 1)
        #expect(interactor.loadedPages == [2])
    }

    @Test func failedRefreshAfterReplySubmissionKeepsPublishedToast() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let presenter = PostDetailPresenter(interactor: interactor, router: router, initialPage: 2)
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
            page: 2,
            isLastPage: true
        )))

        presenter.didTapSendReply(content: "测试回复")
        presenter.didSubmitReply(PostDetailSubmitReplyResponse(message: "已发布"))
        presenter.didFailLoadPostDetail(error: "网络错误")

        #expect(view.errorMessage == nil)
        #expect(view.toastMessage == "已发布")
    }

    @Test func tappingFavoriteSubmitsCollectionForCurrentPost() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let presenter = PostDetailPresenter(interactor: interactor, router: router, initialPage: 1)
        let view = SpyPostDetailView()
        presenter.setView(view)

        presenter.didTapFavorite()
        #expect(view.toastMessage == "正在处理")
        presenter.didAddFavorite(PostCollectionResponse(message: "已收藏"))

        #expect(interactor.favoriteSubmitCount == 1)
        #expect(view.favoriteSubmittingStates == [true, false])
        #expect(view.toastMessage == "已收藏")
    }

    @Test func duplicateFavoriteTapWhileSubmittingIsIgnored() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let presenter = PostDetailPresenter(interactor: interactor, router: router, initialPage: 1)

        presenter.didTapFavorite()
        presenter.didTapFavorite()

        #expect(interactor.favoriteSubmitCount == 1)
    }

    @Test func secondFavoriteTapAfterAddRemovesCollection() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let presenter = PostDetailPresenter(interactor: interactor, router: router, initialPage: 1)
        let view = SpyPostDetailView()
        presenter.setView(view)

        presenter.didTapFavorite()
        presenter.didAddFavorite(PostCollectionResponse(message: "added"))
        presenter.didTapFavorite()
        presenter.didRemoveFavorite(PostCollectionResponse(message: "removed"))

        #expect(interactor.favoriteSubmitCount == 1)
        #expect(interactor.favoriteRemoveCount == 1)
        #expect(view.favoriteSubmittingStates == [true, false, true, false])
        #expect(view.toastMessage == "已取消收藏")
    }

    @Test func tappingFavoriteOnInitiallyCollectedPostRemovesCollection() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let presenter = PostDetailPresenter(interactor: interactor, router: router, initialPage: 1)
        let view = SpyPostDetailView()
        presenter.setView(view)

        presenter.didLoadPostDetail(PostDetailResponse(detail: .init(
            id: "711898",
            title: "已收藏帖子",
            authorName: "mist",
            avatarURL: nil,
            metadataText: nil,
            contentHTML: "<p>正文</p>",
            isFavoriteCollected: true,
            comments: []
        )))
        presenter.didTapFavorite()

        #expect(interactor.favoriteSubmitCount == 0)
        #expect(interactor.favoriteRemoveCount == 1)
    }

    @Test func addingFavoriteUpdatesPostBodyFromResponse() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let presenter = PostDetailPresenter(interactor: interactor, router: router, initialPage: 1)
        let view = SpyPostDetailView()
        presenter.setView(view)

        presenter.didLoadPostDetail(PostDetailResponse(detail: .init(
            id: "711898",
            title: "未收藏帖子",
            authorName: "mist",
            avatarURL: nil,
            metadataText: nil,
            contentHTML: "<p>正文</p>",
            favoriteCount: 1,
            isFavoriteCollected: false,
            comments: []
        )))
        presenter.didTapFavorite()
        presenter.didAddFavorite(PostCollectionResponse(message: "added", postCollectionCount: 2))

        #expect(view.updatedPostBodyDetails.last?.favoriteCount == 2)
        #expect(view.updatedPostBodyDetails.last?.isFavoriteCollected == true)
        #expect(view.favoriteSubmittingStates == [true, false])
        #expect(view.toastMessage == "已收藏")
    }

    @Test func removingFavoriteUpdatesPostBodyFromResponseWithoutReloadingPage() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let presenter = PostDetailPresenter(interactor: interactor, router: router, initialPage: 1)
        let view = SpyPostDetailView()
        presenter.setView(view)

        presenter.didLoadPostDetail(PostDetailResponse(detail: .init(
            id: "711898",
            title: "已收藏帖子",
            authorName: "mist",
            avatarURL: nil,
            metadataText: nil,
            contentHTML: "<p>正文</p>",
            favoriteCount: 2,
            isFavoriteCollected: true,
            comments: [],
            page: 3
        )))
        presenter.didTapFavorite()
        presenter.didRemoveFavorite(PostCollectionResponse(message: "removed", postCollectionCount: 1))

        #expect(interactor.loadedPages == [])
        #expect(view.pageLoadingCount == 0)
        #expect(view.favoriteSubmittingStates == [true, false])
        #expect(view.updatedPostBodyDetails.last?.favoriteCount == 1)
        #expect(view.updatedPostBodyDetails.last?.isFavoriteCollected == false)
        #expect(view.toastMessage == "已取消收藏")
    }

    @Test func favoriteSuccessSkipsPostBodyUpdateWhenStateAndCountAreUnchanged() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let presenter = PostDetailPresenter(interactor: interactor, router: router, initialPage: 1)
        let view = SpyPostDetailView()
        presenter.setView(view)

        presenter.didLoadPostDetail(PostDetailResponse(detail: .init(
            id: "711898",
            title: "已收藏帖子",
            authorName: "mist",
            avatarURL: nil,
            metadataText: nil,
            contentHTML: "<p>正文</p>",
            favoriteCount: 2,
            isFavoriteCollected: true,
            comments: []
        )))
        presenter.didAddFavorite(PostCollectionResponse(postCollectionCount: 2))

        #expect(view.updatedPostBodyDetails.isEmpty)
        #expect(view.favoriteSubmittingStates == [false])
        #expect(view.toastMessage == "已收藏")
    }

    @Test func favoriteFailureCanRetry() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let presenter = PostDetailPresenter(interactor: interactor, router: router, initialPage: 1)
        let view = SpyPostDetailView()
        presenter.setView(view)

        presenter.didTapFavorite()
        presenter.didFailAddFavorite(error: "请先登录")
        presenter.didTapFavorite()

        #expect(interactor.favoriteSubmitCount == 2)
        #expect(view.favoriteSubmittingStates == [true, false, true])
        #expect(view.errorMessage == "请先登录")
    }

    @Test func optimisticFavoriteRevertsWhenAddFails() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let presenter = PostDetailPresenter(interactor: interactor, router: router, initialPage: 1)
        let view = SpyPostDetailView()
        presenter.setView(view)

        presenter.didLoadPostDetail(PostDetailResponse(detail: .init(
            id: "711898",
            title: "未收藏帖子",
            authorName: "mist",
            avatarURL: nil,
            metadataText: nil,
            contentHTML: "<p>正文</p>",
            favoriteCount: 2,
            isFavoriteCollected: false,
            comments: []
        )))
        presenter.didTapFavorite()
        presenter.didFailAddFavorite(error: "网络错误")

        #expect(view.updatedPostBodyDetails.map(\.favoriteCount) == [3, 2])
        #expect(view.updatedPostBodyDetails.map(\.isFavoriteCollected) == [true, false])
        #expect(view.favoriteSubmittingStates == [true, false])
        #expect(view.errorMessage == "网络错误")
    }
}

private final class SpyPostDetailInteractor: PostDetailInteractorInput {
    private(set) var loadedPages: [Int] = []
    private(set) var loadPostDetailCount = 0
    private(set) var submittedReplyContent: String?
    private(set) var favoriteSubmitCount = 0
    private(set) var favoriteRemoveCount = 0

    func loadPostDetail() {
        loadPostDetail(page: 1)
    }

    func loadPostDetail(page: Int) {
        loadPostDetailCount += 1
        loadedPages.append(page)
    }

    func submitReply(content: String) {
        submittedReplyContent = content
    }

    func addFavorite() {
        favoriteSubmitCount += 1
    }

    func removeFavorite() {
        favoriteRemoveCount += 1
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
    private(set) var replySubmittingStates: [Bool] = []
    private(set) var favoriteSubmittingStates: [Bool] = []
    private(set) var finishReplySubmissionCount = 0
    private(set) var hideLoadingCount = 0
    private(set) var renderedDetails: [PostDetail] = []
    private(set) var updatedPostBodyDetails: [PostDetail] = []

    func showLoading() { loadingCount += 1 }
    func showPageLoading() { pageLoadingCount += 1 }
    func hideLoading() { hideLoadingCount += 1 }
    func showError(message: String) { errorMessage = message }
    func showToast(message: String) { toastMessage = message }
    func setReplySubmitting(_ isSubmitting: Bool) { replySubmittingStates.append(isSubmitting) }
    func setFavoriteSubmitting(_ isSubmitting: Bool) {
        favoriteSubmittingStates.append(isSubmitting)
        if isSubmitting {
            toastMessage = "正在处理"
        }
    }
    func finishReplySubmission() { finishReplySubmissionCount += 1 }
    func render(detail: PostDetail) { renderedDetails.append(detail) }
    func updatePostBody(detail: PostDetail) { updatedPostBodyDetails.append(detail) }
    func renderLoginRequired(message: String) {}
}

@MainActor
private final class SpyVisitedPostStore: VisitedPostStoreProtocol {
    private(set) var markedPosts: [PostSummary] = []

    func isVisited(postID: String) -> Bool {
        false
    }

    func markVisited(post: PostSummary, visitedAt: Date) {
        markedPosts.append(post)
    }

    func recentRecords(limit: Int) -> [VisitedPostRecord] {
        []
    }

    func recentRecords(offset: Int, limit: Int) -> [VisitedPostRecord] {
        []
    }

    func clearAll() {
    }
}
