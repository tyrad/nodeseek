//
//  NodeSeekNotificationMarkViewedSubmitter.swift
//  nodeseek
//
//  Created by Codex on 2026/6/8.
//

import Foundation

nonisolated protocol NodeSeekNotificationMarkViewedSubmitting {
    func submit(_ request: NodeSeekNotificationMarkViewedRequest, referer: URL) async throws
}

@MainActor
struct WebViewNodeSeekNotificationMarkViewedSubmitter: NodeSeekNotificationMarkViewedSubmitting {
    private let timeoutInterval: TimeInterval

    init(timeoutInterval: TimeInterval = 20) {
        self.timeoutInterval = timeoutInterval
    }

    @MainActor
    func submit(_ request: NodeSeekNotificationMarkViewedRequest, referer: URL) async throws {
        let startedAt = Date()
        AppLog.info(.webView, "通知标记已读 WebView 请求开始: path=\(request.apiPath), hasBody=\(request.bodyJSON != nil), referer=\(referer.absoluteString)")
        let object = try await withHiddenWebViewPageActionLoader(
            logMessage: "准备通过隐藏 WebView 标记通知已读: path=\(request.apiPath), referer=\(referer.absoluteString)"
        ) { loader in
            try await loader.runPageAutomationScript(
                pageURL: referer,
                source: NotificationMarkViewedAutomationScript.source,
                arguments: [
                    "apiPath": request.apiPath,
                    "bodyJSON": request.bodyJSON ?? ""
                ],
                timeoutInterval: timeoutInterval,
                actionName: "通知标记已读"
            )
        }

        let result = NodeSeekNotificationMarkViewedAutomationResponse(object: object)
        AppLog.info(
            .webView,
            "通知标记已读 WebView 请求结束: path=\(request.apiPath), ok=\(result.ok), status=\(result.statusCode.map(String.init) ?? "nil"), reason=\(result.reason), message=\(result.message ?? "nil"), bodyLength=\(result.body?.count ?? 0), elapsedMs=\(AppLog.elapsedMilliseconds(since: startedAt))"
        )
        guard result.ok else {
            let message: String
            switch result.reason {
            case "submit_timeout": message = "请求超时，请重试"
            case "challenge": message = "需要网页验证，请打开通知网页后重试"
            case "network_error": message = "网络连接失败，请稍后重试"
            default: message = "标记已读失败，请稍后重试"
            }
            throw NodeSeekNotificationClientError.unsuccessfulResponse(message)
        }
    }
}

private struct NodeSeekNotificationMarkViewedAutomationResponse {
    let ok: Bool
    let statusCode: Int?
    let reason: String
    let message: String?
    let body: String?

    init(object: [String: Any]) {
        ok = object["ok"] as? Bool ?? false
        statusCode = (object["statusCode"] as? NSNumber)?.intValue ?? object["statusCode"] as? Int
        reason = object["reason"] as? String ?? "unknown"
        body = object["body"] as? String
        let responseObject = object["response"] as? [String: Any]
        message = responseObject?["message"] as? String ?? object["message"] as? String
    }
}
