//
//  NodeSeekCommentSubmitter.swift
//  nodeseek
//

import Foundation

struct CommentSubmitResponse: Equatable, Sendable {
    let message: String?
}

struct CommentAutomationResponse: Equatable, Sendable {
    let ok: Bool
    let statusCode: Int?
    let message: String?
    let reason: String
    let body: String?

    init(ok: Bool, statusCode: Int? = nil, message: String? = nil, reason: String, body: String? = nil) {
        self.ok = ok
        self.statusCode = statusCode
        self.message = message
        self.reason = reason
        self.body = body
    }
}

protocol CommentSubmissionAutomating: AnyObject {
    func submitComment(postID: Int, content: String, referer: URL) async throws -> CommentAutomationResponse
}

enum NodeSeekCommentSubmitterError: LocalizedError, Equatable {
    case invalidPostID
    case serverMessage(String)
    case httpStatus(Int)
    case challengeRequired(String)
    case pageAutomationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidPostID:
            return "帖子 ID 无效，无法发表评论。"
        case .serverMessage(let message):
            return message
        case .httpStatus(let statusCode):
            return "评论发送失败，状态码 \(statusCode)。"
        case .challengeRequired(let message):
            return message
        case .pageAutomationFailed(let message):
            return message
        }
    }
}

final class NodeSeekCommentSubmitter {
    private let baseURL: URL
    private let automation: CommentSubmissionAutomating

    init(
        baseURL: URL = URL(string: "https://www.nodeseek.com")!,
        automation: CommentSubmissionAutomating = WebViewCommentSubmissionAutomator()
    ) {
        self.baseURL = baseURL
        self.automation = automation
    }

    func submitComment(postID: String, content: String, referer: URL) async throws -> CommentSubmitResponse {
        guard let numericPostID = Int(postID) else {
            throw NodeSeekCommentSubmitterError.invalidPostID
        }

        let response = try await automation.submitComment(
            postID: numericPostID,
            content: content,
            referer: referer
        )

        if response.reason == "challenge" {
            throw NodeSeekCommentSubmitterError.challengeRequired(
                response.message ?? "站点当前返回了拦截页面，请稍后重试。"
            )
        }

        if let statusCode = response.statusCode, !(200..<300).contains(statusCode) {
            if let message = response.message?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
                throw NodeSeekCommentSubmitterError.serverMessage(message)
            }
            throw NodeSeekCommentSubmitterError.httpStatus(statusCode)
        }

        guard response.ok else {
            if let message = response.message?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
                throw NodeSeekCommentSubmitterError.serverMessage(message)
            }
            throw NodeSeekCommentSubmitterError.pageAutomationFailed(Self.message(forAutomationReason: response.reason))
        }

        return CommentSubmitResponse(message: response.message)
    }

    private static func message(forAutomationReason reason: String) -> String {
        switch reason {
        case "editor_not_found":
            return "网页评论编辑器未找到，请稍后重试。"
        case "fill_failed":
            return "评论内容未能填入网页编辑器，请稍后重试。"
        case "submit_button_not_found":
            return "网页评论提交按钮未找到，请稍后重试。"
        case "submit_timeout":
            return "已点击网页提交按钮，但未等到站点响应。"
        case "javascript_exception":
            return "网页脚本执行失败，请稍后重试。"
        default:
            return "网页模拟提交失败，请稍后重试。"
        }
    }
}

final class WebViewCommentSubmissionAutomator: CommentSubmissionAutomating {
    private let client: HiddenWebViewCommentSubmissionClient

    init(client: HiddenWebViewCommentSubmissionClient = HiddenWebViewCommentSubmissionClient()) {
        self.client = client
    }

    func submitComment(postID: Int, content: String, referer: URL) async throws -> CommentAutomationResponse {
        try await client.submitComment(postID: postID, content: content, referer: referer)
    }
}
