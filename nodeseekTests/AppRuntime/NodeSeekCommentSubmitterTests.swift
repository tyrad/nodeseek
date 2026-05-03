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
            baseURL: URL(string: "https://www.nodeseek.com")!,
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
            baseURL: URL(string: "https://www.nodeseek.com")!,
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
            baseURL: URL(string: "https://www.nodeseek.com")!,
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
            baseURL: URL(string: "https://www.nodeseek.com")!,
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
            baseURL: URL(string: "https://www.nodeseek.com")!,
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
