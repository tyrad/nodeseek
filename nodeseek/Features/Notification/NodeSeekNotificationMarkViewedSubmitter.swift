//
//  NodeSeekNotificationMarkViewedSubmitter.swift
//  nodeseek
//
//  Created by Codex on 2026/6/8.
//

import Foundation

protocol NodeSeekNotificationMarkViewedSubmitting {
    func submit(_ request: NodeSeekNotificationMarkViewedRequest, referer: URL) async throws
}

struct WebViewNodeSeekNotificationMarkViewedSubmitter: NodeSeekNotificationMarkViewedSubmitting {
    private let timeoutInterval: TimeInterval

    init(timeoutInterval: TimeInterval = 20) {
        self.timeoutInterval = timeoutInterval
    }

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
            throw NodeSeekNotificationClientError.unsuccessfulResponse(result.message ?? result.reason)
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
