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
    func showLoadingMoreComments()
    func hideLoadingMoreComments()
    func hideLoading()
    func showError(message: String)
    func showToast(message: String)
    func setReplySubmitting(_ isSubmitting: Bool)
    func setFavoriteSubmitting(_ isSubmitting: Bool)
    func finishReplySubmission()
    func render(detail: PostDetail)
    func refreshCurrentCommentPage(detail: PostDetail)
    func appendCommentPage(detail: PostDetail)
    func updatePostBody(detail: PostDetail)
    func updateCommentLike(commentID: String, count: Int?, isClicked: Bool)
    func updateCommentChickenLeg(commentID: String, count: Int?, isClicked: Bool)
    func updateCommentOppose(commentID: String, count: Int?, isClicked: Bool)
    func renderLoginRequired(message: String)
}

// MARK: - Presenter Protocol (View -> Presenter)
protocol PostDetailPresenterProtocol: AnyObject {
    func viewDidLoad()
    func refreshInitialPage()
    func didTapLogin()
    func didApproachCommentEnd()
    func didTapRefreshCommentsAtEnd()
    func didTapSendReply(content: String)
    func didTapFavorite()
    func didTapPostLike()
    func didTapPostChickenLeg()
    func didTapPostOppose()
    func didTapCommentLike(_ comment: Comment)
    func didTapCommentChickenLeg(_ comment: Comment)
    func didTapCommentOppose(_ comment: Comment)
}

// MARK: - Interactor Input (Presenter -> Interactor)
protocol PostDetailInteractorInput: AnyObject {
    func loadPostDetail()
    func loadPostDetail(page: Int)
    func submitReply(content: String)
    func addFavorite()
    func removeFavorite()
    func addPostLike()
    func addCommentLike(commentID: String)
    func addPostChickenLeg()
    func addCommentChickenLeg(commentID: String)
    func addPostOppose()
    func addCommentOppose(commentID: String)
}

// MARK: - Interactor Output (Interactor -> Presenter)
protocol PostDetailInteractorOutput: AnyObject {
    func didLoadPostDetail(_ response: PostDetailResponse)
    func didRequireLogin(message: String)
    func didFailLoadPostDetail(error: String)
    func didCancelLoadPostDetail()
    func didSubmitReply(_ response: PostDetailSubmitReplyResponse)
    func didFailSubmitReply(error: String)
    func didAddFavorite(_ response: PostCollectionResponse)
    func didFailAddFavorite(error: String)
    func didRemoveFavorite(_ response: PostCollectionResponse)
    func didFailRemoveFavorite(error: String)
    func didAddPostLike(_ response: PostUpvoteResponse)
    func didFailAddPostLike(error: String)
    func didAddCommentLike(commentID: String, response: CommentUpvoteResponse)
    func didFailAddCommentLike(commentID: String, error: String)
    func didAddPostChickenLeg(_ response: PostChickenLegResponse)
    func didFailAddPostChickenLeg(error: String)
    func didAddCommentChickenLeg(commentID: String, response: CommentChickenLegResponse)
    func didFailAddCommentChickenLeg(commentID: String, error: String)
    func didAddPostOppose(_ response: PostDislikeResponse)
    func didFailAddPostOppose(error: String)
    func didAddCommentOppose(commentID: String, response: CommentDislikeResponse)
    func didFailAddCommentOppose(commentID: String, error: String)
}

// MARK: - Router Protocol (Presenter -> Router)
protocol PostDetailRouterProtocol: AnyObject {
    func navigateToLogin(onClose: @escaping @MainActor () -> Void)
}
