//
//  NodeSeekCommentSubmitterTests.swift
//  nodeseekTests
//

import Foundation
import Testing
@testable import nodeseek

@MainActor
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
