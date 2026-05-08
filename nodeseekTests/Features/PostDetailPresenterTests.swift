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

    @Test func approachingCommentEndLoadsNextPage() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let view = SpyPostDetailView()
        let presenter = PostDetailPresenter(interactor: interactor, router: router, initialPage: 1)
        presenter.setView(view)
        presenter.didLoadPostDetail(PostDetailResponse(detail: PostDetail(
            id: "706958",
            title: "标题",
            authorName: "mist",
            avatarURL: nil,
            metadataText: nil,
            contentHTML: "<p>正文</p>",
            comments: [
                Comment(id: "1", authorName: "a", avatarURL: nil, floorText: "#1", createdAtText: nil, contentHTML: "<p>第一页</p>")
            ],
            page: 1,
            pagination: PostDetailPagination(
                currentPage: 1,
                items: [
                    PostDetailPageItem(page: 1, url: nil, isCurrent: true),
                    PostDetailPageItem(page: 2, url: nil, isCurrent: false)
                ],
                previousPage: nil,
                nextPage: 2
            )
        )))

        presenter.didApproachCommentEnd()

        #expect(interactor.loadedPages == [2])
        #expect(view.showLoadingMoreCommentsCount == 1)
    }

    @Test func approachingCommentEndWithoutNextPageDoesNotLoadMore() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let presenter = PostDetailPresenter(interactor: interactor, router: router, initialPage: 2)
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

        presenter.didApproachCommentEnd()

        #expect(interactor.loadedPages.isEmpty)
    }

    @Test func approachingCommentEndWhileLoadingMoreDoesNotDuplicateRequest() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let presenter = PostDetailPresenter(interactor: interactor, router: router, initialPage: 1)
        presenter.didLoadPostDetail(PostDetailResponse(detail: PostDetail(
            id: "706958",
            title: "标题",
            authorName: "mist",
            avatarURL: nil,
            metadataText: nil,
            contentHTML: "<p>正文</p>",
            comments: [],
            page: 1,
            pagination: PostDetailPagination(
                currentPage: 1,
                items: [
                    PostDetailPageItem(page: 1, url: nil, isCurrent: true),
                    PostDetailPageItem(page: 2, url: nil, isCurrent: false)
                ],
                previousPage: nil,
                nextPage: 2
            )
        )))

        presenter.didApproachCommentEnd()
        presenter.didApproachCommentEnd()

        #expect(interactor.loadedPages == [2])
    }

    @Test func failedCommentPageLoadCanRetry() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let view = SpyPostDetailView()
        let presenter = PostDetailPresenter(interactor: interactor, router: router, initialPage: 1)
        presenter.setView(view)
        presenter.didLoadPostDetail(PostDetailResponse(detail: PostDetail(
            id: "706958",
            title: "标题",
            authorName: "mist",
            avatarURL: nil,
            metadataText: nil,
            contentHTML: "<p>正文</p>",
            comments: [],
            page: 1,
            pagination: PostDetailPagination(
                currentPage: 1,
                items: [
                    PostDetailPageItem(page: 1, url: nil, isCurrent: true),
                    PostDetailPageItem(page: 2, url: nil, isCurrent: false)
                ],
                previousPage: nil,
                nextPage: 2
            )
        )))

        presenter.didApproachCommentEnd()
        presenter.didFailLoadPostDetail(error: "网络错误")
        presenter.didApproachCommentEnd()

        #expect(interactor.loadedPages == [2, 2])
        #expect(view.hideLoadingMoreCommentsCount == 1)
    }

    @Test func loadedNextCommentPageAppendsInsteadOfReplacingDetail() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let view = SpyPostDetailView()
        let presenter = PostDetailPresenter(interactor: interactor, router: router, initialPage: 1)
        presenter.setView(view)
        presenter.didLoadPostDetail(PostDetailResponse(detail: PostDetail(
            id: "706958",
            title: "标题",
            authorName: "mist",
            avatarURL: nil,
            metadataText: nil,
            contentHTML: "<p>正文</p>",
            comments: [
                Comment(id: "1", authorName: "a", avatarURL: nil, floorText: "#1", createdAtText: nil, contentHTML: "<p>第一页</p>")
            ],
            page: 1,
            pagination: PostDetailPagination(
                currentPage: 1,
                items: [
                    PostDetailPageItem(page: 1, url: nil, isCurrent: true),
                    PostDetailPageItem(page: 2, url: nil, isCurrent: false)
                ],
                previousPage: nil,
                nextPage: 2
            )
        )))

        presenter.didApproachCommentEnd()
        presenter.didLoadPostDetail(PostDetailResponse(detail: PostDetail(
            id: "706958",
            title: "标题",
            authorName: "mist",
            avatarURL: nil,
            metadataText: nil,
            contentHTML: "<p>第二页不应替换正文</p>",
            comments: [
                Comment(id: "2", authorName: "b", avatarURL: nil, floorText: "#2", createdAtText: nil, contentHTML: "<p>第二页</p>")
            ],
            page: 2,
            pagination: PostDetailPagination(
                currentPage: 2,
                items: [
                    PostDetailPageItem(page: 1, url: nil, isCurrent: false),
                    PostDetailPageItem(page: 2, url: nil, isCurrent: true)
                ],
                previousPage: 1,
                nextPage: nil
            )
        )))

        #expect(view.renderedDetails.count == 1)
        #expect(view.appendedCommentPageDetails.map(\.page) == [2])
        #expect(view.hideLoadingMoreCommentsCount == 1)
    }

    @Test func refreshingAtCommentEndWithOnlyOneLoadedPageReloadsCurrentPage() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let view = SpyPostDetailView()
        let presenter = PostDetailPresenter(interactor: interactor, router: router, initialPage: 1)
        presenter.setView(view)
        presenter.didLoadPostDetail(PostDetailResponse(detail: PostDetail(
            id: "706958",
            title: "标题",
            authorName: "mist",
            avatarURL: nil,
            metadataText: nil,
            contentHTML: "<p>正文</p>",
            comments: [
                Comment(id: "1", authorName: "a", avatarURL: nil, floorText: "#1", createdAtText: nil, contentHTML: "<p>第一页</p>"),
                Comment(id: "2", authorName: "b", avatarURL: nil, floorText: "#2", createdAtText: nil, contentHTML: "<p>第一页</p>")
            ],
            page: 1,
            pagination: PostDetailPagination(currentPage: 1, items: [PostDetailPageItem(page: 1, url: nil, isCurrent: true)], previousPage: nil, nextPage: nil)
        )))

        presenter.didTapRefreshCommentsAtEnd()

        #expect(interactor.loadedPages == [1])
        #expect(view.showLoadingMoreCommentsCount == 1)

        presenter.didLoadPostDetail(PostDetailResponse(detail: PostDetail(
            id: "706958",
            title: "标题",
            authorName: "mist",
            avatarURL: nil,
            metadataText: nil,
            contentHTML: "<p>正文</p>",
            comments: [
                Comment(id: "1", authorName: "a", avatarURL: nil, floorText: "#1", createdAtText: nil, contentHTML: "<p>第一页</p>"),
                Comment(id: "2", authorName: "b", avatarURL: nil, floorText: "#2", createdAtText: nil, contentHTML: "<p>第一页</p>")
            ],
            page: 1,
            pagination: PostDetailPagination(currentPage: 1, items: [PostDetailPageItem(page: 1, url: nil, isCurrent: true)], previousPage: nil, nextPage: nil)
        )))

        #expect(view.refreshedCommentPageDetails.map(\.page) == [1])
        #expect(view.hideLoadingMoreCommentsCount == 1)
        #expect(view.toastMessage == "暂无新评论")
    }

    @Test func refreshingAtCommentEndWithShortLastPageReloadsCurrentPage() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let view = SpyPostDetailView()
        let presenter = PostDetailPresenter(interactor: interactor, router: router, initialPage: 1)
        presenter.setView(view)
        presenter.didLoadPostDetail(PostDetailResponse(detail: PostDetail(
            id: "706958",
            title: "标题",
            authorName: "mist",
            avatarURL: nil,
            metadataText: nil,
            contentHTML: "<p>正文</p>",
            comments: [
                Comment(id: "1", authorName: "a", avatarURL: nil, floorText: "#1", createdAtText: nil, contentHTML: "<p>第一页</p>"),
                Comment(id: "2", authorName: "b", avatarURL: nil, floorText: "#2", createdAtText: nil, contentHTML: "<p>第一页</p>")
            ],
            page: 1,
            pagination: PostDetailPagination(
                currentPage: 1,
                items: [
                    PostDetailPageItem(page: 1, url: nil, isCurrent: true),
                    PostDetailPageItem(page: 2, url: nil, isCurrent: false)
                ],
                previousPage: nil,
                nextPage: 2
            )
        )))
        presenter.didApproachCommentEnd()
        presenter.didLoadPostDetail(PostDetailResponse(detail: PostDetail(
            id: "706958",
            title: "标题",
            authorName: "mist",
            avatarURL: nil,
            metadataText: nil,
            contentHTML: "<p>第二页</p>",
            comments: [
                Comment(id: "3", authorName: "c", avatarURL: nil, floorText: "#3", createdAtText: nil, contentHTML: "<p>第二页</p>")
            ],
            page: 2,
            pagination: PostDetailPagination(
                currentPage: 2,
                items: [
                    PostDetailPageItem(page: 1, url: nil, isCurrent: false),
                    PostDetailPageItem(page: 2, url: nil, isCurrent: true)
                ],
                previousPage: 1,
                nextPage: nil
            )
        )))

        presenter.didTapRefreshCommentsAtEnd()

        #expect(interactor.loadedPages == [2, 2])
        #expect(view.showLoadingMoreCommentsCount == 2)
    }

    @Test func refreshingAtCommentEndWithFullLastPageRequestsNextPage() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let view = SpyPostDetailView()
        let presenter = PostDetailPresenter(interactor: interactor, router: router, initialPage: 1)
        presenter.setView(view)
        presenter.didLoadPostDetail(PostDetailResponse(detail: PostDetail(
            id: "706958",
            title: "标题",
            authorName: "mist",
            avatarURL: nil,
            metadataText: nil,
            contentHTML: "<p>正文</p>",
            comments: [
                Comment(id: "1", authorName: "a", avatarURL: nil, floorText: "#1", createdAtText: nil, contentHTML: "<p>第一页</p>"),
                Comment(id: "2", authorName: "b", avatarURL: nil, floorText: "#2", createdAtText: nil, contentHTML: "<p>第一页</p>")
            ],
            page: 1,
            pagination: PostDetailPagination(
                currentPage: 1,
                items: [
                    PostDetailPageItem(page: 1, url: nil, isCurrent: true),
                    PostDetailPageItem(page: 2, url: nil, isCurrent: false)
                ],
                previousPage: nil,
                nextPage: 2
            )
        )))
        presenter.didApproachCommentEnd()
        presenter.didLoadPostDetail(PostDetailResponse(detail: PostDetail(
            id: "706958",
            title: "标题",
            authorName: "mist",
            avatarURL: nil,
            metadataText: nil,
            contentHTML: "<p>第二页</p>",
            comments: [
                Comment(id: "3", authorName: "c", avatarURL: nil, floorText: "#3", createdAtText: nil, contentHTML: "<p>第二页</p>"),
                Comment(id: "4", authorName: "d", avatarURL: nil, floorText: "#4", createdAtText: nil, contentHTML: "<p>第二页</p>")
            ],
            page: 2,
            pagination: PostDetailPagination(
                currentPage: 2,
                items: [
                    PostDetailPageItem(page: 1, url: nil, isCurrent: false),
                    PostDetailPageItem(page: 2, url: nil, isCurrent: true)
                ],
                previousPage: 1,
                nextPage: nil
            )
        )))

        presenter.didTapRefreshCommentsAtEnd()

        #expect(interactor.loadedPages == [2, 3])
        #expect(view.showLoadingMoreCommentsCount == 2)
    }

    @Test func refreshingAtCommentEndProbeReturningCurrentPageRefreshesInPlace() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let view = SpyPostDetailView()
        let presenter = PostDetailPresenter(interactor: interactor, router: router, initialPage: 1)
        presenter.setView(view)
        presenter.didLoadPostDetail(PostDetailResponse(detail: PostDetail(
            id: "706958",
            title: "标题",
            authorName: "mist",
            avatarURL: nil,
            metadataText: nil,
            contentHTML: "<p>正文</p>",
            comments: [
                Comment(id: "1", authorName: "a", avatarURL: nil, floorText: "#1", createdAtText: nil, contentHTML: "<p>第一页</p>"),
                Comment(id: "2", authorName: "b", avatarURL: nil, floorText: "#2", createdAtText: nil, contentHTML: "<p>第一页</p>")
            ],
            page: 1,
            pagination: PostDetailPagination(
                currentPage: 1,
                items: [
                    PostDetailPageItem(page: 1, url: nil, isCurrent: true),
                    PostDetailPageItem(page: 2, url: nil, isCurrent: false)
                ],
                previousPage: nil,
                nextPage: 2
            )
        )))
        presenter.didApproachCommentEnd()
        presenter.didLoadPostDetail(PostDetailResponse(detail: PostDetail(
            id: "706958",
            title: "标题",
            authorName: "mist",
            avatarURL: nil,
            metadataText: nil,
            contentHTML: "<p>第二页</p>",
            comments: [
                Comment(id: "3", authorName: "c", avatarURL: nil, floorText: "#3", createdAtText: nil, contentHTML: "<p>第二页</p>"),
                Comment(id: "4", authorName: "d", avatarURL: nil, floorText: "#4", createdAtText: nil, contentHTML: "<p>第二页</p>")
            ],
            page: 2,
            pagination: PostDetailPagination(
                currentPage: 2,
                items: [
                    PostDetailPageItem(page: 1, url: nil, isCurrent: false),
                    PostDetailPageItem(page: 2, url: nil, isCurrent: true)
                ],
                previousPage: 1,
                nextPage: nil
            )
        )))

        presenter.didTapRefreshCommentsAtEnd()
        presenter.didLoadPostDetail(PostDetailResponse(detail: PostDetail(
            id: "706958",
            title: "标题",
            authorName: "mist",
            avatarURL: nil,
            metadataText: nil,
            contentHTML: "<p>第二页更新</p>",
            comments: [
                Comment(id: "3", authorName: "c", avatarURL: nil, floorText: "#3", createdAtText: nil, contentHTML: "<p>第二页更新</p>"),
                Comment(id: "4", authorName: "d", avatarURL: nil, floorText: "#4", createdAtText: nil, contentHTML: "<p>第二页</p>")
            ],
            page: 2,
            pagination: PostDetailPagination(
                currentPage: 2,
                items: [
                    PostDetailPageItem(page: 1, url: nil, isCurrent: false),
                    PostDetailPageItem(page: 2, url: nil, isCurrent: true)
                ],
                previousPage: 1,
                nextPage: nil
            )
        )))

        #expect(interactor.loadedPages == [2, 3])
        #expect(view.renderedDetails.count == 1)
        #expect(view.refreshedCommentPageDetails.map(\.page) == [2])
        #expect(view.hideLoadingMoreCommentsCount == 2)
        #expect(view.toastMessage == "暂无新评论")
    }

    @Test func replySubmissionSuccessFinishesComposerAndReloadsCurrentPage() async throws {
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
        #expect(interactor.loadedPages.isEmpty)

        try await Task.sleep(nanoseconds: 350_000_000)

        #expect(interactor.loadedPages == [2])
        #expect(view.loadingCount == 0)
    }

    @Test func replySubmissionBeforeLastCommentPageDoesNotRefreshCurrentPage() async throws {
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
            isLastPage: false
        )))

        presenter.didTapSendReply(content: "测试回复")
        presenter.didSubmitReply(PostDetailSubmitReplyResponse(message: "已发布"))

        #expect(interactor.loadedPages.isEmpty)

        try await Task.sleep(nanoseconds: 350_000_000)

        #expect(interactor.loadedPages.isEmpty)
    }

    @Test func replySubmissionRefreshesLastPageWithPartialCommentUpdate() async throws {
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
            comments: [
                Comment(id: "1", authorName: "a", avatarURL: nil, floorText: "#1", createdAtText: nil, contentHTML: "<p>旧评论</p>")
            ],
            page: 2,
            isLastPage: true
        )))

        presenter.didTapSendReply(content: "测试回复")
        presenter.didSubmitReply(PostDetailSubmitReplyResponse(message: "已发布"))

        try await Task.sleep(nanoseconds: 350_000_000)
        presenter.didLoadPostDetail(PostDetailResponse(detail: PostDetail(
            id: "706958",
            title: "标题",
            authorName: "mist",
            avatarURL: nil,
            metadataText: nil,
            contentHTML: "<p>正文</p>",
            comments: [
                Comment(id: "1", authorName: "a", avatarURL: nil, floorText: "#1", createdAtText: nil, contentHTML: "<p>旧评论</p>"),
                Comment(id: "2", authorName: "b", avatarURL: nil, floorText: "#2", createdAtText: nil, contentHTML: "<p>新评论</p>")
            ],
            page: 2,
            isLastPage: true
        )))

        #expect(view.renderedDetails.count == 1)
        #expect(view.refreshedCommentPageDetails.map(\.page) == [2])
    }

    @Test func cancelledRefreshAfterReplySubmissionDoesNotShowError() async throws {
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

        try await Task.sleep(nanoseconds: 350_000_000)

        presenter.didCancelLoadPostDetail()

        #expect(view.errorMessage == nil)
        #expect(view.toastMessage == "已发布")
        #expect(interactor.loadedPages == [2])
        #expect(view.hideLoadingCount == 2)
    }

    @Test func cancelledNormalDetailLoadDoesNotShowError() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let presenter = PostDetailPresenter(interactor: interactor, router: router, initialPage: 1)
        let view = SpyPostDetailView()
        presenter.setView(view)

        presenter.didApproachCommentEnd()
        presenter.didCancelLoadPostDetail()

        #expect(view.errorMessage == nil)
        #expect(interactor.loadedPages.isEmpty)
    }

    @Test func failedRefreshAfterReplySubmissionKeepsPublishedToast() async throws {
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

        try await Task.sleep(nanoseconds: 350_000_000)

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

    @Test func tappingPostLikeSubmitsUpvoteAndUpdatesPostBody() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let presenter = PostDetailPresenter(interactor: interactor, router: router, initialPage: 1)
        let view = SpyPostDetailView()
        presenter.setView(view)
        presenter.didLoadPostDetail(PostDetailResponse(detail: .init(
            id: "712073",
            title: "标题",
            authorName: "mist",
            avatarURL: nil,
            metadataText: nil,
            contentHTML: "<p>正文</p>",
            likeCount: 0,
            comments: []
        )))

        presenter.didTapPostLike()
        presenter.didAddPostLike(PostUpvoteResponse(message: "added", current: 1))

        #expect(interactor.postLikeSubmitCount == 1)
        #expect(view.updatedPostBodyDetails.last?.likeCount == 1)
        #expect(view.updatedPostBodyDetails.last?.isLikeClicked == true)
        #expect(view.toastMessage == "已点赞")
    }

    @Test func tappingAlreadyLikedPostOnlyShowsToast() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let presenter = PostDetailPresenter(interactor: interactor, router: router, initialPage: 1)
        let view = SpyPostDetailView()
        presenter.setView(view)
        presenter.didLoadPostDetail(PostDetailResponse(detail: .init(
            id: "712073",
            title: "标题",
            authorName: "mist",
            avatarURL: nil,
            metadataText: nil,
            contentHTML: "<p>正文</p>",
            likeCount: 1,
            isLikeClicked: true,
            comments: []
        )))

        presenter.didTapPostLike()

        #expect(interactor.postLikeSubmitCount == 0)
        #expect(view.toastMessage == "该帖子已点赞")
    }

    @Test func tappingCommentLikeSubmitsUpvoteAndShowsToastOnSuccess() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let presenter = PostDetailPresenter(interactor: interactor, router: router, initialPage: 1)
        let view = SpyPostDetailView()
        presenter.setView(view)
        let comment = Comment(
            id: "9835758",
            authorName: "mist",
            avatarURL: nil,
            floorText: "#1",
            createdAtText: "刚刚",
            contentHTML: "<p>内容</p>",
            likeCount: 0
        )
        presenter.didLoadPostDetail(PostDetailResponse(detail: PostDetail(
            id: "712073",
            title: "标题",
            authorName: "mist",
            avatarURL: nil,
            metadataText: nil,
            contentHTML: "<p>正文</p>",
            comments: [comment]
        )))

        presenter.didTapCommentLike(comment)
        presenter.didAddCommentLike(commentID: "9835758", response: CommentUpvoteResponse(message: "added", current: 1))

        #expect(interactor.submittedCommentLikeIDs == ["9835758"])
        #expect(view.updatedCommentLikeEvents.last?.commentID == "9835758")
        #expect(view.updatedCommentLikeEvents.last?.count == 1)
        #expect(view.updatedCommentLikeEvents.last?.isClicked == true)
        #expect(view.toastMessage == "已点赞")
    }

    @Test func tappingAlreadyLikedCommentOnlyShowsToast() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let presenter = PostDetailPresenter(interactor: interactor, router: router, initialPage: 1)
        let view = SpyPostDetailView()
        presenter.setView(view)
        let comment = Comment(
            id: "9835758",
            authorName: "mist",
            avatarURL: nil,
            floorText: "#1",
            createdAtText: "刚刚",
            contentHTML: "<p>内容</p>",
            likeCount: 1,
            isLikeClicked: true
        )

        presenter.didTapCommentLike(comment)

        #expect(interactor.submittedCommentLikeIDs.isEmpty)
        #expect(view.toastMessage == "该评论已点赞")
    }

    @Test func tappingPostChickenLegSubmitsAndUpdatesPostBody() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let presenter = PostDetailPresenter(interactor: interactor, router: router, initialPage: 1)
        let view = SpyPostDetailView()
        presenter.setView(view)
        presenter.didLoadPostDetail(PostDetailResponse(detail: .init(
            id: "712073",
            title: "标题",
            authorName: "mist",
            avatarURL: nil,
            metadataText: nil,
            contentHTML: "<p>正文</p>",
            chickenLegCount: 2,
            comments: []
        )))

        presenter.didTapPostChickenLeg()
        presenter.didAddPostChickenLeg(PostChickenLegResponse(message: "added", current: 3))

        #expect(interactor.postChickenLegSubmitCount == 1)
        #expect(view.updatedPostBodyDetails.last?.chickenLegCount == 3)
        #expect(view.updatedPostBodyDetails.last?.isChickenLegClicked == true)
        #expect(view.toastMessage == "已投放鸡腿")
    }

    @Test func tappingPostChickenLegFallsBackToIncrementWhenResponseHasNoCurrent() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let presenter = PostDetailPresenter(interactor: interactor, router: router, initialPage: 1)
        let view = SpyPostDetailView()
        presenter.setView(view)
        presenter.didLoadPostDetail(PostDetailResponse(detail: .init(
            id: "712073",
            title: "标题",
            authorName: "mist",
            avatarURL: nil,
            metadataText: nil,
            contentHTML: "<p>正文</p>",
            chickenLegCount: 2,
            comments: []
        )))

        presenter.didTapPostChickenLeg()
        presenter.didAddPostChickenLeg(PostChickenLegResponse(message: "added", current: nil))

        #expect(view.updatedPostBodyDetails.last?.chickenLegCount == 3)
        #expect(view.updatedPostBodyDetails.last?.isChickenLegClicked == true)
    }

    @Test func tappingAlreadyChickenLeggedPostOnlyShowsToast() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let presenter = PostDetailPresenter(interactor: interactor, router: router, initialPage: 1)
        let view = SpyPostDetailView()
        presenter.setView(view)
        presenter.didLoadPostDetail(PostDetailResponse(detail: .init(
            id: "712073",
            title: "标题",
            authorName: "mist",
            avatarURL: nil,
            metadataText: nil,
            contentHTML: "<p>正文</p>",
            chickenLegCount: 3,
            isChickenLegClicked: true,
            comments: []
        )))

        presenter.didTapPostChickenLeg()

        #expect(interactor.postChickenLegSubmitCount == 0)
        #expect(view.toastMessage == "该帖子已投放鸡腿")
    }

    @Test func tappingCommentChickenLegSubmitsAndUpdatesCell() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let presenter = PostDetailPresenter(interactor: interactor, router: router, initialPage: 1)
        let view = SpyPostDetailView()
        presenter.setView(view)
        let comment = Comment(
            id: "9835758",
            authorName: "mist",
            avatarURL: nil,
            floorText: "#1",
            createdAtText: "刚刚",
            contentHTML: "<p>内容</p>",
            chickenLegCount: 1
        )
        presenter.didLoadPostDetail(PostDetailResponse(detail: PostDetail(
            id: "712073",
            title: "标题",
            authorName: "mist",
            avatarURL: nil,
            metadataText: nil,
            contentHTML: "<p>正文</p>",
            comments: [comment]
        )))

        presenter.didTapCommentChickenLeg(comment)
        presenter.didAddCommentChickenLeg(commentID: "9835758", response: CommentChickenLegResponse(message: "added", current: 2))

        #expect(interactor.submittedCommentChickenLegIDs == ["9835758"])
        #expect(view.updatedCommentChickenLegEvents.last?.commentID == "9835758")
        #expect(view.updatedCommentChickenLegEvents.last?.count == 2)
        #expect(view.updatedCommentChickenLegEvents.last?.isClicked == true)
        #expect(view.toastMessage == "已投放鸡腿")
    }

    @Test func tappingAlreadyChickenLeggedCommentOnlyShowsToast() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let presenter = PostDetailPresenter(interactor: interactor, router: router, initialPage: 1)
        let view = SpyPostDetailView()
        presenter.setView(view)
        let comment = Comment(
            id: "9835758",
            authorName: "mist",
            avatarURL: nil,
            floorText: "#1",
            createdAtText: "刚刚",
            contentHTML: "<p>内容</p>",
            chickenLegCount: 2,
            isChickenLegClicked: true
        )

        presenter.didTapCommentChickenLeg(comment)

        #expect(interactor.submittedCommentChickenLegIDs.isEmpty)
        #expect(view.toastMessage == "该评论已投放鸡腿")
    }

    @Test func tappingPostOpposeSubmitsDislikeAndUpdatesPostBody() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let presenter = PostDetailPresenter(interactor: interactor, router: router, initialPage: 1)
        let view = SpyPostDetailView()
        presenter.setView(view)
        presenter.didLoadPostDetail(PostDetailResponse(detail: .init(
            id: "712073",
            title: "标题",
            authorName: "mist",
            avatarURL: nil,
            metadataText: nil,
            contentHTML: "<p>正文</p>",
            opposeCount: 0,
            comments: []
        )))

        presenter.didTapPostOppose()
        presenter.didAddPostOppose(PostDislikeResponse(message: "added", current: 1))

        #expect(interactor.postOpposeSubmitCount == 1)
        #expect(view.updatedPostBodyDetails.last?.opposeCount == 1)
        #expect(view.updatedPostBodyDetails.last?.isOpposeClicked == true)
        #expect(view.toastMessage == "已反对")
    }

    @Test func tappingAlreadyOpposedPostOnlyShowsToast() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let presenter = PostDetailPresenter(interactor: interactor, router: router, initialPage: 1)
        let view = SpyPostDetailView()
        presenter.setView(view)
        presenter.didLoadPostDetail(PostDetailResponse(detail: .init(
            id: "712073",
            title: "标题",
            authorName: "mist",
            avatarURL: nil,
            metadataText: nil,
            contentHTML: "<p>正文</p>",
            opposeCount: 1,
            isOpposeClicked: true,
            comments: []
        )))

        presenter.didTapPostOppose()

        #expect(interactor.postOpposeSubmitCount == 0)
        #expect(view.toastMessage == "该帖子已反对")
    }

    @Test func tappingCommentOpposeSubmitsDislikeAndUpdatesCell() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let presenter = PostDetailPresenter(interactor: interactor, router: router, initialPage: 1)
        let view = SpyPostDetailView()
        presenter.setView(view)
        let comment = Comment(
            id: "9835758",
            authorName: "mist",
            avatarURL: nil,
            floorText: "#1",
            createdAtText: "刚刚",
            contentHTML: "<p>内容</p>",
            opposeCount: 0
        )
        presenter.didLoadPostDetail(PostDetailResponse(detail: PostDetail(
            id: "712073",
            title: "标题",
            authorName: "mist",
            avatarURL: nil,
            metadataText: nil,
            contentHTML: "<p>正文</p>",
            comments: [comment]
        )))

        presenter.didTapCommentOppose(comment)
        presenter.didAddCommentOppose(commentID: "9835758", response: CommentDislikeResponse(message: "added", current: 1))

        #expect(interactor.submittedCommentOpposeIDs == ["9835758"])
        #expect(view.updatedCommentOpposeEvents.last?.commentID == "9835758")
        #expect(view.updatedCommentOpposeEvents.last?.count == 1)
        #expect(view.updatedCommentOpposeEvents.last?.isClicked == true)
        #expect(view.toastMessage == "已反对")
    }
}

private final class SpyPostDetailInteractor: PostDetailInteractorInput {
    private(set) var loadedPages: [Int] = []
    private(set) var loadPostDetailCount = 0
    private(set) var submittedReplyContent: String?
    private(set) var favoriteSubmitCount = 0
    private(set) var favoriteRemoveCount = 0
    private(set) var postLikeSubmitCount = 0
    private(set) var postChickenLegSubmitCount = 0
    private(set) var postOpposeSubmitCount = 0
    private(set) var submittedCommentLikeIDs: [String] = []
    private(set) var submittedCommentChickenLegIDs: [String] = []
    private(set) var submittedCommentOpposeIDs: [String] = []

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

    func addPostLike() {
        postLikeSubmitCount += 1
    }

    func addCommentLike(commentID: String) {
        submittedCommentLikeIDs.append(commentID)
    }

    func addPostChickenLeg() {
        postChickenLegSubmitCount += 1
    }

    func addCommentChickenLeg(commentID: String) {
        submittedCommentChickenLegIDs.append(commentID)
    }

    func addPostOppose() {
        postOpposeSubmitCount += 1
    }

    func addCommentOppose(commentID: String) {
        submittedCommentOpposeIDs.append(commentID)
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
    private(set) var showLoadingMoreCommentsCount = 0
    private(set) var hideLoadingMoreCommentsCount = 0
    var errorMessage: String?
    var toastMessage: String?
    private(set) var replySubmittingStates: [Bool] = []
    private(set) var favoriteSubmittingStates: [Bool] = []
    private(set) var finishReplySubmissionCount = 0
    private(set) var hideLoadingCount = 0
    private(set) var renderedDetails: [PostDetail] = []
    private(set) var refreshedCommentPageDetails: [PostDetail] = []
    private(set) var appendedCommentPageDetails: [PostDetail] = []
    private(set) var updatedPostBodyDetails: [PostDetail] = []
    private(set) var updatedCommentLikeEvents: [(commentID: String, count: Int?, isClicked: Bool)] = []
    private(set) var updatedCommentChickenLegEvents: [(commentID: String, count: Int?, isClicked: Bool)] = []
    private(set) var updatedCommentOpposeEvents: [(commentID: String, count: Int?, isClicked: Bool)] = []

    func showLoading() { loadingCount += 1 }
    func showLoadingMoreComments() { showLoadingMoreCommentsCount += 1 }
    func hideLoadingMoreComments() { hideLoadingMoreCommentsCount += 1 }
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
    func refreshCurrentCommentPage(detail: PostDetail) { refreshedCommentPageDetails.append(detail) }
    func appendCommentPage(detail: PostDetail) { appendedCommentPageDetails.append(detail) }
    func updatePostBody(detail: PostDetail) { updatedPostBodyDetails.append(detail) }
    func updateCommentLike(commentID: String, count: Int?, isClicked: Bool) {
        updatedCommentLikeEvents.append((commentID: commentID, count: count, isClicked: isClicked))
    }
    func updateCommentChickenLeg(commentID: String, count: Int?, isClicked: Bool) {
        updatedCommentChickenLegEvents.append((commentID: commentID, count: count, isClicked: isClicked))
    }
    func updateCommentOppose(commentID: String, count: Int?, isClicked: Bool) {
        updatedCommentOpposeEvents.append((commentID: commentID, count: count, isClicked: isClicked))
    }
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
