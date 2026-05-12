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
    let diagnostics: [String]

    init(
        ok: Bool,
        statusCode: Int? = nil,
        message: String? = nil,
        reason: String,
        body: String? = nil,
        diagnostics: [String] = []
    ) {
        self.ok = ok
        self.statusCode = statusCode
        self.message = message
        self.reason = reason
        self.body = body
        self.diagnostics = diagnostics
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
    private let automation: CommentSubmissionAutomating

    init(
        automation: CommentSubmissionAutomating = WebViewCommentSubmissionAutomator()
    ) {
        self.automation = automation
    }

    func submitComment(postID: String, content: String, referer: URL) async throws -> CommentSubmitResponse {
        let startedAt = Date()
        AppLog.info(.postDetail, "Submitter 收到回复提交: postID=\(postID), contentLength=\(content.count), referer=\(referer.absoluteString)")
        guard let numericPostID = Int(postID) else {
            AppLog.error(.postDetail, "Submitter 中止回复提交: postID 无法转 Int, postID=\(postID), elapsedMs=\(AppLog.elapsedMilliseconds(since: startedAt))")
            throw NodeSeekCommentSubmitterError.invalidPostID
        }

        AppLog.info(.postDetail, "Submitter 即将调用自动化: postID=\(numericPostID), elapsedMs=\(AppLog.elapsedMilliseconds(since: startedAt))")
        let response = try await automation.submitComment(
            postID: numericPostID,
            content: content,
            referer: referer
        )
        AppLog.info(.postDetail, "Submitter 自动化返回: postID=\(numericPostID), ok=\(response.ok), status=\(response.statusCode.map(String.init) ?? "nil"), reason=\(response.reason), message=\(response.message ?? "nil"), bodyLength=\(response.body?.count ?? 0), diagnosticsCount=\(response.diagnostics.count), elapsedMs=\(AppLog.elapsedMilliseconds(since: startedAt))")

        if response.reason == "challenge" {
            AppLog.warning(.postDetail, "Submitter 识别为挑战页: postID=\(numericPostID), message=\(response.message ?? "nil")")
            throw NodeSeekCommentSubmitterError.challengeRequired(
                response.message ?? "站点当前返回了拦截页面，请稍后重试。"
            )
        }

        if let statusCode = response.statusCode, !(200..<300).contains(statusCode) {
            AppLog.warning(.postDetail, "Submitter 收到非 2xx 状态: postID=\(numericPostID), status=\(statusCode), message=\(response.message ?? "nil")")
            if let message = response.message?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
                throw NodeSeekCommentSubmitterError.serverMessage(message)
            }
            throw NodeSeekCommentSubmitterError.httpStatus(statusCode)
        }

        guard response.ok else {
            AppLog.warning(.postDetail, "Submitter 自动化标记失败: postID=\(numericPostID), reason=\(response.reason), message=\(response.message ?? "nil")")
            if let message = response.message?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
                throw NodeSeekCommentSubmitterError.serverMessage(message)
            }
            throw NodeSeekCommentSubmitterError.pageAutomationFailed(Self.message(forAutomationReason: response.reason))
        }

        AppLog.info(.postDetail, "Submitter 回复提交成功: postID=\(numericPostID), elapsedMs=\(AppLog.elapsedMilliseconds(since: startedAt))")
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
        let startedAt = Date()
        AppLog.info(.webView, "WebViewCommentSubmissionAutomator 开始: postID=\(postID), contentLength=\(content.count), referer=\(referer.absoluteString)")
        let response = try await client.submitComment(postID: postID, content: content, referer: referer)
        AppLog.info(.webView, "WebViewCommentSubmissionAutomator 结束: postID=\(postID), ok=\(response.ok), reason=\(response.reason), elapsedMs=\(AppLog.elapsedMilliseconds(since: startedAt))")
        return response
    }
}

struct PostCollectionResponse: Equatable, Sendable {
    let success: Bool?
    let message: String?
    let postCollectionCount: Int?
    let userCollectionCount: Int?

    init(
        success: Bool? = nil,
        message: String? = nil,
        postCollectionCount: Int? = nil,
        userCollectionCount: Int? = nil
    ) {
        self.success = success
        self.message = message
        self.postCollectionCount = postCollectionCount
        self.userCollectionCount = userCollectionCount
    }
}

struct CommentUpvoteResponse: Equatable, Sendable {
    let success: Bool?
    let message: String?
    let current: Int?

    init(
        success: Bool? = nil,
        message: String? = nil,
        current: Int? = nil
    ) {
        self.success = success
        self.message = message
        self.current = current
    }
}

typealias PostUpvoteResponse = CommentUpvoteResponse
typealias CommentChickenLegResponse = CommentUpvoteResponse
typealias PostChickenLegResponse = CommentUpvoteResponse
typealias CommentDislikeResponse = CommentUpvoteResponse
typealias PostDislikeResponse = CommentUpvoteResponse

struct PostCollectionAutomationResponse: Equatable, Sendable {
    let ok: Bool
    let statusCode: Int?
    let response: PostCollectionResponse
    let reason: String
    let body: String?

    init(
        ok: Bool,
        statusCode: Int? = nil,
        response: PostCollectionResponse,
        reason: String,
        body: String? = nil
    ) {
        self.ok = ok
        self.statusCode = statusCode
        self.response = response
        self.reason = reason
        self.body = body
    }
}

struct CommentUpvoteAutomationResponse: Equatable, Sendable {
    let ok: Bool
    let statusCode: Int?
    let response: CommentUpvoteResponse
    let reason: String
    let body: String?

    init(
        ok: Bool,
        statusCode: Int? = nil,
        response: CommentUpvoteResponse,
        reason: String,
        body: String? = nil
    ) {
        self.ok = ok
        self.statusCode = statusCode
        self.response = response
        self.reason = reason
        self.body = body
    }
}

typealias PostUpvoteAutomationResponse = CommentUpvoteAutomationResponse
typealias CommentChickenLegAutomationResponse = CommentUpvoteAutomationResponse
typealias PostChickenLegAutomationResponse = CommentUpvoteAutomationResponse
typealias CommentDislikeAutomationResponse = CommentUpvoteAutomationResponse
typealias PostDislikeAutomationResponse = CommentUpvoteAutomationResponse

@MainActor
protocol PostCollectionAutomating: AnyObject {
    func submitCollection(postID: Int, action: String, referer: URL) async throws -> PostCollectionAutomationResponse
}

@MainActor
protocol CommentUpvoteAutomating: AnyObject {
    func submitUpvote(commentID: Int, action: String, referer: URL) async throws -> CommentUpvoteAutomationResponse
}

@MainActor
protocol PostUpvoteAutomating: AnyObject {
    func submitUpvote(postID: Int, action: String, referer: URL) async throws -> PostUpvoteAutomationResponse
}

@MainActor
protocol CommentChickenLegAutomating: AnyObject {
    func submitChickenLeg(commentID: Int, action: String, referer: URL) async throws -> CommentChickenLegAutomationResponse
}

@MainActor
protocol PostChickenLegAutomating: AnyObject {
    func submitChickenLeg(postID: Int, action: String, referer: URL) async throws -> PostChickenLegAutomationResponse
}

@MainActor
protocol CommentDislikeAutomating: AnyObject {
    func submitDislike(commentID: Int, action: String, referer: URL) async throws -> CommentDislikeAutomationResponse
}

@MainActor
protocol PostDislikeAutomating: AnyObject {
    func submitDislike(postID: Int, action: String, referer: URL) async throws -> PostDislikeAutomationResponse
}

final class WebViewPostCollectionAutomator: PostCollectionAutomating {
    private let client: HiddenWebViewPostCollectionClient

    init(client: HiddenWebViewPostCollectionClient = HiddenWebViewPostCollectionClient()) {
        self.client = client
    }

    func submitCollection(postID: Int, action: String, referer: URL) async throws -> PostCollectionAutomationResponse {
        try await client.submitCollection(postID: postID, action: action, referer: referer)
    }
}

final class WebViewCommentUpvoteAutomator: CommentUpvoteAutomating {
    private let client: HiddenWebViewCommentUpvoteClient

    init(client: HiddenWebViewCommentUpvoteClient = HiddenWebViewCommentUpvoteClient()) {
        self.client = client
    }

    func submitUpvote(commentID: Int, action: String, referer: URL) async throws -> CommentUpvoteAutomationResponse {
        try await client.submitUpvote(commentID: commentID, action: action, referer: referer)
    }
}

final class WebViewPostUpvoteAutomator: PostUpvoteAutomating {
    private let client: HiddenWebViewPostUpvoteClient

    init(client: HiddenWebViewPostUpvoteClient = HiddenWebViewPostUpvoteClient()) {
        self.client = client
    }

    func submitUpvote(postID: Int, action: String, referer: URL) async throws -> PostUpvoteAutomationResponse {
        try await client.submitUpvote(postID: postID, action: action, referer: referer)
    }
}

final class WebViewCommentChickenLegAutomator: CommentChickenLegAutomating {
    private let client: HiddenWebViewCommentChickenLegClient

    init(client: HiddenWebViewCommentChickenLegClient = HiddenWebViewCommentChickenLegClient()) {
        self.client = client
    }

    func submitChickenLeg(commentID: Int, action: String, referer: URL) async throws -> CommentChickenLegAutomationResponse {
        try await client.submitChickenLeg(commentID: commentID, action: action, referer: referer)
    }
}

final class WebViewPostChickenLegAutomator: PostChickenLegAutomating {
    private let client: HiddenWebViewPostChickenLegClient

    init(client: HiddenWebViewPostChickenLegClient = HiddenWebViewPostChickenLegClient()) {
        self.client = client
    }

    func submitChickenLeg(postID: Int, action: String, referer: URL) async throws -> PostChickenLegAutomationResponse {
        try await client.submitChickenLeg(postID: postID, action: action, referer: referer)
    }
}

final class WebViewCommentDislikeAutomator: CommentDislikeAutomating {
    private let client: HiddenWebViewCommentDislikeClient

    init(client: HiddenWebViewCommentDislikeClient = HiddenWebViewCommentDislikeClient()) {
        self.client = client
    }

    func submitDislike(commentID: Int, action: String, referer: URL) async throws -> CommentDislikeAutomationResponse {
        try await client.submitDislike(commentID: commentID, action: action, referer: referer)
    }
}

final class WebViewPostDislikeAutomator: PostDislikeAutomating {
    private let client: HiddenWebViewPostDislikeClient

    init(client: HiddenWebViewPostDislikeClient = HiddenWebViewPostDislikeClient()) {
        self.client = client
    }

    func submitDislike(postID: Int, action: String, referer: URL) async throws -> PostDislikeAutomationResponse {
        try await client.submitDislike(postID: postID, action: action, referer: referer)
    }
}

@MainActor
protocol PostCollectionSubmitting: AnyObject {
    func addFavorite(postID: String, referer: URL) async throws -> PostCollectionResponse
    func removeFavorite(postID: String, referer: URL) async throws -> PostCollectionResponse
}

@MainActor
protocol CommentUpvoteSubmitting: AnyObject {
    func addUpvote(commentID: String, referer: URL) async throws -> CommentUpvoteResponse
}

@MainActor
protocol PostUpvoteSubmitting: AnyObject {
    func addUpvote(postID: String, referer: URL) async throws -> PostUpvoteResponse
}

@MainActor
protocol CommentChickenLegSubmitting: AnyObject {
    func addChickenLeg(commentID: String, referer: URL) async throws -> CommentChickenLegResponse
}

@MainActor
protocol PostChickenLegSubmitting: AnyObject {
    func addChickenLeg(postID: String, referer: URL) async throws -> PostChickenLegResponse
}

@MainActor
protocol CommentDislikeSubmitting: AnyObject {
    func addDislike(commentID: String, referer: URL) async throws -> CommentDislikeResponse
}

@MainActor
protocol PostDislikeSubmitting: AnyObject {
    func addDislike(postID: String, referer: URL) async throws -> PostDislikeResponse
}

enum NodeSeekPostCollectionSubmitterError: LocalizedError, Equatable {
    case invalidPostID
    case serverMessage(String)
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidPostID:
            return "帖子 ID 无效，无法收藏。"
        case .serverMessage(let message):
            return message
        case .httpStatus(let statusCode):
            return "收藏失败，状态码 \(statusCode)。"
        }
    }
}

enum NodeSeekCommentUpvoteSubmitterError: LocalizedError, Equatable {
    case invalidCommentID
    case serverMessage(String)
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidCommentID:
            return "评论 ID 无效，无法点赞。"
        case .serverMessage(let message):
            return message
        case .httpStatus(let statusCode):
            return "点赞失败，状态码 \(statusCode)。"
        }
    }
}

enum NodeSeekPostUpvoteSubmitterError: LocalizedError, Equatable {
    case invalidPostID
    case serverMessage(String)
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidPostID:
            return "帖子 ID 无效，无法点赞。"
        case .serverMessage(let message):
            return message
        case .httpStatus(let statusCode):
            return "点赞失败，状态码 \(statusCode)。"
        }
    }
}

enum NodeSeekCommentChickenLegSubmitterError: LocalizedError, Equatable {
    case invalidCommentID
    case serverMessage(String)
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidCommentID:
            return "评论 ID 无效，无法投放鸡腿。"
        case .serverMessage(let message):
            return message
        case .httpStatus(let statusCode):
            return "投放鸡腿失败，状态码 \(statusCode)。"
        }
    }
}

enum NodeSeekPostChickenLegSubmitterError: LocalizedError, Equatable {
    case invalidPostID
    case serverMessage(String)
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidPostID:
            return "帖子 ID 无效，无法投放鸡腿。"
        case .serverMessage(let message):
            return message
        case .httpStatus(let statusCode):
            return "投放鸡腿失败，状态码 \(statusCode)。"
        }
    }
}

enum NodeSeekCommentDislikeSubmitterError: LocalizedError, Equatable {
    case invalidCommentID
    case serverMessage(String)
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidCommentID:
            return "评论 ID 无效，无法反对。"
        case .serverMessage(let message):
            return message
        case .httpStatus(let statusCode):
            return "反对失败，状态码 \(statusCode)。"
        }
    }
}

enum NodeSeekPostDislikeSubmitterError: LocalizedError, Equatable {
    case invalidPostID
    case serverMessage(String)
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidPostID:
            return "帖子 ID 无效，无法反对。"
        case .serverMessage(let message):
            return message
        case .httpStatus(let statusCode):
            return "反对失败，状态码 \(statusCode)。"
        }
    }
}

private struct ReactionSubmitterErrors {
    let invalidID: Error
    let serverMessage: (String) -> Error
    let httpStatus: (Int) -> Error
    let fallbackMessage: String
}

@MainActor
private func submitReaction(
    targetID: String,
    action: String,
    referer: URL,
    errors: ReactionSubmitterErrors,
    automation: (Int, String, URL) async throws -> CommentUpvoteAutomationResponse
) async throws -> CommentUpvoteResponse {
    guard let numericTargetID = Int(targetID) else {
        throw errors.invalidID
    }

    let automationResponse = try await automation(numericTargetID, action, referer)
    let response = automationResponse.response

    if let statusCode = automationResponse.statusCode, !(200..<300).contains(statusCode) {
        if let message = response.message {
            throw errors.serverMessage(message)
        }
        throw errors.httpStatus(statusCode)
    }

    guard automationResponse.ok, response.success != false else {
        if let message = response.message {
            throw errors.serverMessage(message)
        }
        throw errors.serverMessage(errors.fallbackMessage)
    }

    return response
}

@MainActor
final class NodeSeekPostCollectionSubmitter: PostCollectionSubmitting {
    private let automation: PostCollectionAutomating

    init(
        automation: PostCollectionAutomating? = nil
    ) {
        self.automation = automation ?? WebViewPostCollectionAutomator()
    }

    func addFavorite(postID: String, referer: URL) async throws -> PostCollectionResponse {
        try await submit(postID: postID, action: "add", referer: referer)
    }

    func removeFavorite(postID: String, referer: URL) async throws -> PostCollectionResponse {
        try await submit(postID: postID, action: "remove", referer: referer)
    }

    private func submit(postID: String, action: String, referer: URL) async throws -> PostCollectionResponse {
        guard let numericPostID = Int(postID) else {
            throw NodeSeekPostCollectionSubmitterError.invalidPostID
        }

        let automationResponse = try await automation.submitCollection(
            postID: numericPostID,
            action: action,
            referer: referer
        )
        let collectionResponse = automationResponse.response

        if let statusCode = automationResponse.statusCode, !(200..<300).contains(statusCode) {
            if let message = collectionResponse.message {
                throw NodeSeekPostCollectionSubmitterError.serverMessage(message)
            }
            throw NodeSeekPostCollectionSubmitterError.httpStatus(statusCode)
        }

        guard automationResponse.ok, collectionResponse.success != false else {
            if let message = collectionResponse.message {
                throw NodeSeekPostCollectionSubmitterError.serverMessage(message)
            }
            throw NodeSeekPostCollectionSubmitterError.serverMessage("收藏失败，请稍后重试。")
        }

        return collectionResponse
    }

    static func collectionResponse(from data: Data) -> PostCollectionResponse {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var message: String?
            for key in ["message", "msg", "error"] {
                guard let value = json[key] as? String else { continue }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty == false {
                    message = trimmed
                    break
                }
            }

            return PostCollectionResponse(
                success: json["success"] as? Bool,
                message: message,
                postCollectionCount: json["postCollectionCount"] as? Int,
                userCollectionCount: json["userCollectionCount"] as? Int
            )
        }

        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return PostCollectionResponse(message: trimmed.isEmpty ? nil : trimmed)
    }
}

@MainActor
final class NodeSeekCommentUpvoteSubmitter: CommentUpvoteSubmitting {
    private let automation: CommentUpvoteAutomating

    init(automation: CommentUpvoteAutomating? = nil) {
        self.automation = automation ?? WebViewCommentUpvoteAutomator()
    }

    func addUpvote(commentID: String, referer: URL) async throws -> CommentUpvoteResponse {
        try await submit(commentID: commentID, action: "add", referer: referer)
    }

    private func submit(commentID: String, action: String, referer: URL) async throws -> CommentUpvoteResponse {
        try await submitReaction(
            targetID: commentID,
            action: action,
            referer: referer,
            errors: ReactionSubmitterErrors(
                invalidID: NodeSeekCommentUpvoteSubmitterError.invalidCommentID,
                serverMessage: NodeSeekCommentUpvoteSubmitterError.serverMessage,
                httpStatus: NodeSeekCommentUpvoteSubmitterError.httpStatus,
                fallbackMessage: "点赞失败，请稍后重试。"
            )
        ) { [automation] commentID, action, referer in
            try await automation.submitUpvote(commentID: commentID, action: action, referer: referer)
        }
    }
}

@MainActor
final class NodeSeekPostUpvoteSubmitter: PostUpvoteSubmitting {
    private let automation: PostUpvoteAutomating

    init(automation: PostUpvoteAutomating? = nil) {
        self.automation = automation ?? WebViewPostUpvoteAutomator()
    }

    func addUpvote(postID: String, referer: URL) async throws -> PostUpvoteResponse {
        try await submit(postID: postID, action: "add", referer: referer)
    }

    private func submit(postID: String, action: String, referer: URL) async throws -> PostUpvoteResponse {
        try await submitReaction(
            targetID: postID,
            action: action,
            referer: referer,
            errors: ReactionSubmitterErrors(
                invalidID: NodeSeekPostUpvoteSubmitterError.invalidPostID,
                serverMessage: NodeSeekPostUpvoteSubmitterError.serverMessage,
                httpStatus: NodeSeekPostUpvoteSubmitterError.httpStatus,
                fallbackMessage: "点赞失败，请稍后重试。"
            )
        ) { [automation] postID, action, referer in
            try await automation.submitUpvote(postID: postID, action: action, referer: referer)
        }
    }
}

@MainActor
final class NodeSeekCommentChickenLegSubmitter: CommentChickenLegSubmitting {
    private let automation: CommentChickenLegAutomating

    init(automation: CommentChickenLegAutomating? = nil) {
        self.automation = automation ?? WebViewCommentChickenLegAutomator()
    }

    func addChickenLeg(commentID: String, referer: URL) async throws -> CommentChickenLegResponse {
        try await submit(commentID: commentID, action: "add", referer: referer)
    }

    private func submit(commentID: String, action: String, referer: URL) async throws -> CommentChickenLegResponse {
        try await submitReaction(
            targetID: commentID,
            action: action,
            referer: referer,
            errors: ReactionSubmitterErrors(
                invalidID: NodeSeekCommentChickenLegSubmitterError.invalidCommentID,
                serverMessage: NodeSeekCommentChickenLegSubmitterError.serverMessage,
                httpStatus: NodeSeekCommentChickenLegSubmitterError.httpStatus,
                fallbackMessage: "投放鸡腿失败，请稍后重试。"
            )
        ) { [automation] commentID, action, referer in
            try await automation.submitChickenLeg(commentID: commentID, action: action, referer: referer)
        }
    }
}

@MainActor
final class NodeSeekPostChickenLegSubmitter: PostChickenLegSubmitting {
    private let automation: PostChickenLegAutomating

    init(automation: PostChickenLegAutomating? = nil) {
        self.automation = automation ?? WebViewPostChickenLegAutomator()
    }

    func addChickenLeg(postID: String, referer: URL) async throws -> PostChickenLegResponse {
        try await submit(postID: postID, action: "add", referer: referer)
    }

    private func submit(postID: String, action: String, referer: URL) async throws -> PostChickenLegResponse {
        try await submitReaction(
            targetID: postID,
            action: action,
            referer: referer,
            errors: ReactionSubmitterErrors(
                invalidID: NodeSeekPostChickenLegSubmitterError.invalidPostID,
                serverMessage: NodeSeekPostChickenLegSubmitterError.serverMessage,
                httpStatus: NodeSeekPostChickenLegSubmitterError.httpStatus,
                fallbackMessage: "投放鸡腿失败，请稍后重试。"
            )
        ) { [automation] postID, action, referer in
            try await automation.submitChickenLeg(postID: postID, action: action, referer: referer)
        }
    }
}

@MainActor
final class NodeSeekCommentDislikeSubmitter: CommentDislikeSubmitting {
    private let automation: CommentDislikeAutomating

    init(automation: CommentDislikeAutomating? = nil) {
        self.automation = automation ?? WebViewCommentDislikeAutomator()
    }

    func addDislike(commentID: String, referer: URL) async throws -> CommentDislikeResponse {
        try await submit(commentID: commentID, action: "add", referer: referer)
    }

    private func submit(commentID: String, action: String, referer: URL) async throws -> CommentDislikeResponse {
        try await submitReaction(
            targetID: commentID,
            action: action,
            referer: referer,
            errors: ReactionSubmitterErrors(
                invalidID: NodeSeekCommentDislikeSubmitterError.invalidCommentID,
                serverMessage: NodeSeekCommentDislikeSubmitterError.serverMessage,
                httpStatus: NodeSeekCommentDislikeSubmitterError.httpStatus,
                fallbackMessage: "反对失败，请稍后重试。"
            )
        ) { [automation] commentID, action, referer in
            try await automation.submitDislike(commentID: commentID, action: action, referer: referer)
        }
    }
}

@MainActor
final class NodeSeekPostDislikeSubmitter: PostDislikeSubmitting {
    private let automation: PostDislikeAutomating

    init(automation: PostDislikeAutomating? = nil) {
        self.automation = automation ?? WebViewPostDislikeAutomator()
    }

    func addDislike(postID: String, referer: URL) async throws -> PostDislikeResponse {
        try await submit(postID: postID, action: "add", referer: referer)
    }

    private func submit(postID: String, action: String, referer: URL) async throws -> PostDislikeResponse {
        try await submitReaction(
            targetID: postID,
            action: action,
            referer: referer,
            errors: ReactionSubmitterErrors(
                invalidID: NodeSeekPostDislikeSubmitterError.invalidPostID,
                serverMessage: NodeSeekPostDislikeSubmitterError.serverMessage,
                httpStatus: NodeSeekPostDislikeSubmitterError.httpStatus,
                fallbackMessage: "反对失败，请稍后重试。"
            )
        ) { [automation] postID, action, referer in
            try await automation.submitDislike(postID: postID, action: action, referer: referer)
        }
    }
}
