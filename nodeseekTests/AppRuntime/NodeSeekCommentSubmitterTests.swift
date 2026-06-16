//
//  NodeSeekCommentSubmitterTests.swift
//  nodeseekTests
//

import Foundation
import Testing
@testable import nodeseek

@MainActor
@Suite(.serialized)
struct NodeSeekCommentSubmitterTests {
    @Test func submitsCommentThroughPageAutomation() async throws {
        let automation = CapturingCommentAutomation(response: .init(ok: true, statusCode: 200, message: nil, reason: "submitted"))
        let submitter = NodeSeekCommentSubmitter(
            automation: automation
        )

        let result = try await submitter.submitComment(
            postID: "706958",
            content: "bdbd",
            referer: URL(string: "https://www.nodeseek.com/post-706958-1")!
        )

        let submission = try #require(automation.submissions.first)
        #expect(result.message == nil)
        #expect(submission.postID == 706958)
        #expect(submission.content == "bdbd")
        #expect(submission.referer.absoluteString == "https://www.nodeseek.com/post-706958-1")
    }

    @Test func surfacesServerMessageFromPageAutomation() async throws {
        let automation = CapturingCommentAutomation(response: .init(ok: false, statusCode: 400, message: "内容不能为空", reason: "server_error"))
        let submitter = NodeSeekCommentSubmitter(
            automation: automation
        )

        do {
            _ = try await submitter.submitComment(
                postID: "706958",
                content: "",
                referer: URL(string: "https://www.nodeseek.com/post-706958-1")!
            )
            Issue.record("空内容错误应抛出")
        } catch let error as NodeSeekCommentSubmitterError {
            #expect(error.errorDescription == "内容不能为空")
        }
    }

    @Test func surfacesChallengeFromPageAutomation() async throws {
        let automation = CapturingCommentAutomation(response: .init(ok: false, statusCode: 403, message: "站点当前返回了拦截页面，请稍后重试。", reason: "challenge"))
        let submitter = NodeSeekCommentSubmitter(
            automation: automation
        )

        do {
            _ = try await submitter.submitComment(
                postID: "706958",
                content: "bdbd",
                referer: URL(string: "https://www.nodeseek.com/post-706958-1")!
            )
            Issue.record("站点挑战错误应抛出")
        } catch let error as NodeSeekCommentSubmitterError {
            #expect(error == .challengeRequired("站点当前返回了拦截页面，请稍后重试。"))
        }
    }

    @Test func favoritePostUsesPageAutomationToAvoidRiskAction() async throws {
        let automation = CapturingCollectionAutomation(response: .init(
            ok: true,
            statusCode: 200,
            response: PostCollectionResponse(
                success: true,
                message: "added",
                postCollectionCount: 1,
                userCollectionCount: 2
            ),
            reason: "submitted"
        ))
        let submitter = NodeSeekPostCollectionSubmitter(
            automation: automation
        )

        let response = try await submitter.addFavorite(
            postID: "711860",
            referer: URL(string: "https://www.nodeseek.com/post-711860-1")!
        )

        let submission = try #require(automation.submissions.first)
        #expect(response.success == true)
        #expect(response.message == "added")
        #expect(response.postCollectionCount == 1)
        #expect(response.userCollectionCount == 2)
        #expect(submission.postID == 711860)
        #expect(submission.action == "add")
        #expect(submission.referer.absoluteString == "https://www.nodeseek.com/post-711860-1")
    }

    @Test func removingFavoriteUsesPageAutomationWithRemoveAction() async throws {
        let automation = CapturingCollectionAutomation(response: .init(
            ok: true,
            statusCode: 200,
            response: PostCollectionResponse(
                success: true,
                message: "removed",
                postCollectionCount: 0,
                userCollectionCount: 1
            ),
            reason: "submitted"
        ))
        let submitter = NodeSeekPostCollectionSubmitter(
            automation: automation
        )

        let response = try await submitter.removeFavorite(
            postID: "711898",
            referer: URL(string: "https://www.nodeseek.com/post-711898-1")!
        )

        let submission = try #require(automation.submissions.first)
        #expect(response.message == "removed")
        #expect(response.postCollectionCount == 0)
        #expect(response.userCollectionCount == 1)
        #expect(submission.postID == 711898)
        #expect(submission.action == "remove")
        #expect(submission.referer.absoluteString == "https://www.nodeseek.com/post-711898-1")
    }

    @Test func addCommentUpvoteUsesPageAutomation() async throws {
        let automation = CapturingCommentUpvoteAutomation(response: .init(
            ok: true,
            statusCode: 200,
            response: CommentUpvoteResponse(
                success: true,
                message: "added",
                current: 1
            ),
            reason: "submitted"
        ))
        let submitter = NodeSeekCommentUpvoteSubmitter(automation: automation)

        let response = try await submitter.addUpvote(
            commentID: "9835758",
            referer: URL(string: "https://www.nodeseek.com/post-712073-1")!
        )

        let submission = try #require(automation.submissions.first)
        #expect(response.success == true)
        #expect(response.message == "added")
        #expect(response.current == 1)
        #expect(submission.commentID == 9835758)
        #expect(submission.action == "add")
        #expect(submission.referer.absoluteString == "https://www.nodeseek.com/post-712073-1")
    }

    @Test func alreadyUpvotedMessageIsSurfaced() async throws {
        let automation = CapturingCommentUpvoteAutomation(response: .init(
            ok: false,
            statusCode: 200,
            response: CommentUpvoteResponse(
                success: false,
                message: "该评论已点赞",
                current: 1
            ),
            reason: "already_clicked"
        ))
        let submitter = NodeSeekCommentUpvoteSubmitter(automation: automation)

        do {
            _ = try await submitter.addUpvote(
                commentID: "9835758",
                referer: URL(string: "https://www.nodeseek.com/post-712073-1")!
            )
            Issue.record("已点赞应抛出错误")
        } catch let error as NodeSeekCommentUpvoteSubmitterError {
            #expect(error.errorDescription == "该评论已点赞")
        }
    }

    @Test func addPostUpvoteUsesPageAutomation() async throws {
        let automation = CapturingPostUpvoteAutomation(response: .init(
            ok: true,
            statusCode: 200,
            response: PostUpvoteResponse(
                success: true,
                message: "added",
                current: 1
            ),
            reason: "submitted"
        ))
        let submitter = NodeSeekPostUpvoteSubmitter(automation: automation)

        let response = try await submitter.addUpvote(
            postID: "712073",
            referer: URL(string: "https://www.nodeseek.com/post-712073-1")!
        )

        let submission = try #require(automation.submissions.first)
        #expect(response.success == true)
        #expect(response.message == "added")
        #expect(response.current == 1)
        #expect(submission.postID == 712073)
        #expect(submission.action == "add")
        #expect(submission.referer.absoluteString == "https://www.nodeseek.com/post-712073-1")
    }

    @Test func postUpvoteScriptSubmitsMainContentCommentID() {
        let source = PostUpvoteAutomationScript.source

        #expect(source.contains("data-comment-id"))
        #expect(source.contains("commentId: commentID"))
        #expect(source.contains("postId: postID") == false)
    }

    @Test func commentUpvoteScriptSubmitsWithoutReadingRenderedCommentNode() {
        let source = CommentUpvoteAutomationScript.source

        #expect(source.contains("commentId: commentID"))
        #expect(source.contains("locateCommentRoot") == false)
        #expect(source.contains("data-comment-id") == false)
        #expect(source.contains("already_clicked") == false)
        #expect(source.contains("reason: \"comment_not_found\"") == false)
    }

    @Test func addCommentChickenLegUsesPageAutomation() async throws {
        let automation = CapturingCommentChickenLegAutomation(response: .init(
            ok: true,
            statusCode: 200,
            response: CommentChickenLegResponse(
                success: true,
                message: "added",
                current: 2
            ),
            reason: "submitted"
        ))
        let submitter = NodeSeekCommentChickenLegSubmitter(automation: automation)

        let response = try await submitter.addChickenLeg(
            commentID: "9835758",
            referer: URL(string: "https://www.nodeseek.com/post-712073-1")!
        )

        let submission = try #require(automation.submissions.first)
        #expect(response.success == true)
        #expect(response.message == "added")
        #expect(response.current == 2)
        #expect(submission.commentID == 9835758)
        #expect(submission.action == "add")
        #expect(submission.referer.absoluteString == "https://www.nodeseek.com/post-712073-1")
    }

    @Test func addPostChickenLegUsesPageAutomation() async throws {
        let automation = CapturingPostChickenLegAutomation(response: .init(
            ok: true,
            statusCode: 200,
            response: PostChickenLegResponse(
                success: true,
                message: "added",
                current: 3
            ),
            reason: "submitted"
        ))
        let submitter = NodeSeekPostChickenLegSubmitter(automation: automation)

        let response = try await submitter.addChickenLeg(
            postID: "712073",
            referer: URL(string: "https://www.nodeseek.com/post-712073-1")!
        )

        let submission = try #require(automation.submissions.first)
        #expect(response.success == true)
        #expect(response.message == "added")
        #expect(response.current == 3)
        #expect(submission.postID == 712073)
        #expect(submission.action == "add")
        #expect(submission.referer.absoluteString == "https://www.nodeseek.com/post-712073-1")
    }

    @Test func postChickenLegScriptSubmitsMainContentCommentID() {
        let source = PostChickenLegAutomationScript.source

        #expect(source.contains("/api/statistics/like"))
        #expect(source.contains("data-comment-id"))
        #expect(source.contains("commentId: commentID"))
        #expect(source.contains("postId: postID") == false)
    }

    @Test func commentChickenLegScriptSubmitsWithoutReadingRenderedCommentNode() {
        let source = CommentChickenLegAutomationScript.source

        #expect(source.contains("commentId: commentID"))
        #expect(source.contains("locateCommentRoot") == false)
        #expect(source.contains("data-comment-id") == false)
        #expect(source.contains("already_clicked") == false)
        #expect(source.contains("reason: \"comment_not_found\"") == false)
    }

    @Test func addCommentDislikeUsesPageAutomation() async throws {
        let automation = CapturingCommentDislikeAutomation(response: .init(
            ok: true,
            statusCode: 200,
            response: CommentDislikeResponse(
                success: true,
                message: "added",
                current: 1
            ),
            reason: "submitted"
        ))
        let submitter = NodeSeekCommentDislikeSubmitter(automation: automation)

        let response = try await submitter.addDislike(
            commentID: "9835758",
            referer: URL(string: "https://www.nodeseek.com/post-712073-1")!
        )

        let submission = try #require(automation.submissions.first)
        #expect(response.success == true)
        #expect(response.message == "added")
        #expect(response.current == 1)
        #expect(submission.commentID == 9835758)
        #expect(submission.action == "add")
        #expect(submission.referer.absoluteString == "https://www.nodeseek.com/post-712073-1")
    }

    @Test func addPostDislikeUsesPageAutomation() async throws {
        let automation = CapturingPostDislikeAutomation(response: .init(
            ok: true,
            statusCode: 200,
            response: PostDislikeResponse(
                success: true,
                message: "added",
                current: 1
            ),
            reason: "submitted"
        ))
        let submitter = NodeSeekPostDislikeSubmitter(automation: automation)

        let response = try await submitter.addDislike(
            postID: "712073",
            referer: URL(string: "https://www.nodeseek.com/post-712073-1")!
        )

        let submission = try #require(automation.submissions.first)
        #expect(response.success == true)
        #expect(response.message == "added")
        #expect(response.current == 1)
        #expect(submission.postID == 712073)
        #expect(submission.action == "add")
        #expect(submission.referer.absoluteString == "https://www.nodeseek.com/post-712073-1")
    }

    @Test func postDislikeScriptSubmitsMainContentCommentID() {
        let source = PostDislikeAutomationScript.source

        #expect(source.contains("/api/statistics/dislike"))
        #expect(source.contains("data-comment-id"))
        #expect(source.contains("commentId: commentID"))
        #expect(source.contains("postId: postID") == false)
    }

    @Test func commentDislikeScriptSubmitsWithoutReadingRenderedCommentNode() {
        let source = CommentDislikeAutomationScript.source

        #expect(source.contains("commentId: commentID"))
        #expect(source.contains("locateCommentRoot") == false)
        #expect(source.contains("data-comment-id") == false)
        #expect(source.contains("already_clicked") == false)
        #expect(source.contains("reason: \"comment_not_found\"") == false)
    }
}

private final class CapturingCommentAutomation: CommentSubmissionAutomating {
    private(set) var submissions: [(postID: Int, content: String, referer: URL)] = []
    private let response: CommentAutomationResponse

    init(response: CommentAutomationResponse) {
        self.response = response
    }

    func submitComment(postID: Int, content: String, referer: URL) async throws -> CommentAutomationResponse {
        submissions.append((postID: postID, content: content, referer: referer))
        return response
    }
}

@MainActor
private final class CapturingCollectionAutomation: PostCollectionAutomating {
    private(set) var submissions: [(postID: Int, action: String, referer: URL)] = []
    private let response: PostCollectionAutomationResponse

    init(response: PostCollectionAutomationResponse) {
        self.response = response
    }

    func submitCollection(postID: Int, action: String, referer: URL) async throws -> PostCollectionAutomationResponse {
        submissions.append((postID: postID, action: action, referer: referer))
        return response
    }
}

@MainActor
private final class CapturingCommentUpvoteAutomation: CommentUpvoteAutomating {
    private(set) var submissions: [(commentID: Int, action: String, referer: URL)] = []
    private let response: CommentUpvoteAutomationResponse

    init(response: CommentUpvoteAutomationResponse) {
        self.response = response
    }

    func submitUpvote(commentID: Int, action: String, referer: URL) async throws -> CommentUpvoteAutomationResponse {
        submissions.append((commentID: commentID, action: action, referer: referer))
        return response
    }
}

@MainActor
private final class CapturingPostUpvoteAutomation: PostUpvoteAutomating {
    private(set) var submissions: [(postID: Int, action: String, referer: URL)] = []
    private let response: PostUpvoteAutomationResponse

    init(response: PostUpvoteAutomationResponse) {
        self.response = response
    }

    func submitUpvote(postID: Int, action: String, referer: URL) async throws -> PostUpvoteAutomationResponse {
        submissions.append((postID: postID, action: action, referer: referer))
        return response
    }
}

@MainActor
private final class CapturingCommentChickenLegAutomation: CommentChickenLegAutomating {
    private(set) var submissions: [(commentID: Int, action: String, referer: URL)] = []
    private let response: CommentChickenLegAutomationResponse

    init(response: CommentChickenLegAutomationResponse) {
        self.response = response
    }

    func submitChickenLeg(commentID: Int, action: String, referer: URL) async throws -> CommentChickenLegAutomationResponse {
        submissions.append((commentID: commentID, action: action, referer: referer))
        return response
    }
}

@MainActor
private final class CapturingPostChickenLegAutomation: PostChickenLegAutomating {
    private(set) var submissions: [(postID: Int, action: String, referer: URL)] = []
    private let response: PostChickenLegAutomationResponse

    init(response: PostChickenLegAutomationResponse) {
        self.response = response
    }

    func submitChickenLeg(postID: Int, action: String, referer: URL) async throws -> PostChickenLegAutomationResponse {
        submissions.append((postID: postID, action: action, referer: referer))
        return response
    }
}

@MainActor
private final class CapturingCommentDislikeAutomation: CommentDislikeAutomating {
    private(set) var submissions: [(commentID: Int, action: String, referer: URL)] = []
    private let response: CommentDislikeAutomationResponse

    init(response: CommentDislikeAutomationResponse) {
        self.response = response
    }

    func submitDislike(commentID: Int, action: String, referer: URL) async throws -> CommentDislikeAutomationResponse {
        submissions.append((commentID: commentID, action: action, referer: referer))
        return response
    }
}

@MainActor
private final class CapturingPostDislikeAutomation: PostDislikeAutomating {
    private(set) var submissions: [(postID: Int, action: String, referer: URL)] = []
    private let response: PostDislikeAutomationResponse

    init(response: PostDislikeAutomationResponse) {
        self.response = response
    }

    func submitDislike(postID: Int, action: String, referer: URL) async throws -> PostDislikeAutomationResponse {
        submissions.append((postID: postID, action: action, referer: referer))
        return response
    }
}
