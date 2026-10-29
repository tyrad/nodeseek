//
//  NodeSeekDiscussionSubmitter.swift
//  nodeseek
//

import Foundation

enum NodeSeekDiscussionSubmitError: LocalizedError, Equatable {
    case notLoggedIn
    case challenge(String)
    case serverMessage(String)
    /// 请求已经发出但没等到结果，帖子可能已经发出，不能自动重试。
    case resultUnknown
    case network(String)
    case unexpected(String)

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return "登录状态已失效，请重新登录后再发帖。"
        case .challenge(let message), .serverMessage(let message):
            return message
        case .resultUnknown:
            return "可能已经发出，请先到“我的帖子”确认，再决定是否重试。"
        case .network(let message):
            return "网络异常，帖子没有发出：\(message)"
        case .unexpected(let message):
            return "发帖失败：\(message)"
        }
    }
}

protocol NodeSeekDiscussionSubmitting: AnyObject {
    func loadUserLevel() async throws -> Int
    func submit(_ submission: NewDiscussionSubmission) async throws -> NewDiscussionResponse
}

/// 在隐藏 WebView 里打开发帖页，读取用户等级和提交新帖。
final class WebViewNodeSeekDiscussionSubmitter: NodeSeekDiscussionSubmitting {
    private let pageURL: URL
    private let timeoutInterval: TimeInterval

    init(pageURL: URL = NodeSeekSite.newDiscussionURL, timeoutInterval: TimeInterval = 15) {
        self.pageURL = pageURL
        self.timeoutInterval = timeoutInterval
    }

    func loadUserLevel() async throws -> Int {
        let object = try await runScript(
            NewDiscussionAutomationScript.userLevelSource,
            arguments: [:],
            actionName: "发帖读取用户等级"
        )
        try Self.throwIfFailed(object)
        guard let rank = (object["rank"] as? NSNumber)?.intValue else {
            throw NodeSeekDiscussionSubmitError.unexpected("没有读到用户等级")
        }
        return rank
    }

    func submit(_ submission: NewDiscussionSubmission) async throws -> NewDiscussionResponse {
        let startedAt = Date()
        let payload = String(decoding: try submission.jsonData(), as: UTF8.self)
        AppLog.info(.webView, "发帖提交开始: category=\(submission.category.rawValue), rank=\(submission.rank.rawValue), titleLength=\(submission.title.count), contentLength=\(submission.content.count)")
        let object = try await runScript(
            NewDiscussionAutomationScript.submitSource,
            arguments: ["payload": payload],
            actionName: "发帖提交"
        )
        let statusCode = (object["statusCode"] as? NSNumber)?.intValue
        let body = object["body"] as? String
        AppLog.info(.webView, "发帖提交结束: ok=\(object["ok"] as? Bool ?? false), status=\(statusCode.map(String.init) ?? "nil"), reason=\(object["reason"] as? String ?? "nil"), bodyLength=\(body?.count ?? 0), elapsedMs=\(AppLog.elapsedMilliseconds(since: startedAt))")

        guard let body else {
            try Self.throwIfFailed(object)
            throw NodeSeekDiscussionSubmitError.unexpected("接口没有返回内容")
        }
        let response: NewDiscussionResponse
        do {
            response = try NewDiscussionResponseParser.parse(Data(body.utf8))
        } catch {
            // 2xx 却解析不了，帖子可能已经发出去，按结果未知处理，避免重试发出重复帖。
            if let statusCode, (200..<300).contains(statusCode) {
                throw NodeSeekDiscussionSubmitError.resultUnknown
            }
            throw NodeSeekDiscussionSubmitError.unexpected("状态码 \(statusCode.map(String.init) ?? "未知")，返回内容无法识别")
        }
        guard response.success else {
            throw NodeSeekDiscussionSubmitError.serverMessage(response.message ?? "发帖失败，请稍后重试。")
        }
        return response
    }

    private func runScript(_ source: String, arguments: [String: Any], actionName: String) async throws -> [String: Any] {
        let pageURL = pageURL
        let timeoutInterval = timeoutInterval
        return try await withHiddenWebViewPageActionLoader(
            logMessage: "准备通过隐藏 WebView 执行\(actionName): url=\(pageURL.absoluteString)"
        ) { loader in
            try await loader.runPageAutomationScript(
                pageURL: pageURL,
                source: source,
                arguments: arguments,
                timeoutInterval: timeoutInterval,
                actionName: actionName
            )
        }
    }

    private static func throwIfFailed(_ object: [String: Any]) throws {
        guard object["ok"] as? Bool != true else { return }
        let reason = object["reason"] as? String ?? "unknown"
        let message = object["message"] as? String
        switch reason {
        case "not_logged_in":
            throw NodeSeekDiscussionSubmitError.notLoggedIn
        case "challenge":
            throw NodeSeekDiscussionSubmitError.challenge(message ?? "需要先通过站点验证，请稍后重试。")
        case "submit_timeout", "response_unreadable":
            throw NodeSeekDiscussionSubmitError.resultUnknown
        case "network_error":
            throw NodeSeekDiscussionSubmitError.network(message ?? "未知错误")
        default:
            throw NodeSeekDiscussionSubmitError.unexpected(message ?? reason)
        }
    }
}
