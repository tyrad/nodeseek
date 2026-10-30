//
//  UserFollowSubmitter.swift
//  nodeseek
//
//  Created by Claude on 2026/10/30.
//

import Foundation

nonisolated protocol UserFollowSubmitting {
    /// 失败时抛出带接口提示的错误
    func submit(apiPath: String, bodyJSON: String, referer: URL) async throws
}

/// 关注 / 取消关注走隐藏 WebView 里的页面 fetch。
/// App 直接用 URLSession 发 POST 会被站点返回 403，只有浏览器环境里的请求能通过。
@MainActor
struct WebViewUserFollowSubmitter: UserFollowSubmitting {
    private let timeoutInterval: TimeInterval

    init(timeoutInterval: TimeInterval = 20) {
        self.timeoutInterval = timeoutInterval
    }

    func submit(apiPath: String, bodyJSON: String, referer: URL) async throws {
        let startedAt = Date()
        let object = try await withHiddenWebViewPageActionLoader(
            logMessage: "准备通过隐藏 WebView 提交关注变更: path=\(apiPath), referer=\(referer.absoluteString)"
        ) { loader in
            // 通知标记已读的脚本就是通用的「页面内 POST JSON」，这里直接复用
            try await loader.runPageAutomationScript(
                pageURL: referer,
                source: NotificationMarkViewedAutomationScript.source,
                arguments: ["apiPath": apiPath, "bodyJSON": bodyJSON],
                timeoutInterval: timeoutInterval,
                actionName: "关注变更"
            )
        }
        let ok = object["ok"] as? Bool ?? false
        let message = (object["response"] as? [String: Any])?["message"] as? String ?? object["message"] as? String
        let status = (object["statusCode"] as? NSNumber)?.intValue
        AppLog.info(
            .webView,
            "关注变更 WebView 请求结束: path=\(apiPath), ok=\(ok), status=\(status.map(String.init) ?? "nil"), message=\(message ?? "nil"), elapsedMs=\(AppLog.elapsedMilliseconds(since: startedAt))"
        )
        guard ok else {
            // 带上状态码，方便区分是打开页面被拦截还是接口拒绝
            let fallback = status.map { "操作失败（HTTP \($0)），请稍后重试" } ?? "操作失败，请稍后重试"
            throw UserContentClientError.rejected(message ?? fallback)
        }
    }
}
