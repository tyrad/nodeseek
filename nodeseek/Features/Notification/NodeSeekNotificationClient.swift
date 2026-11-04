//
//  NodeSeekNotificationClient.swift
//  nodeseek
//
//  Created by Codex on 2026/6/8.
//

import Foundation

nonisolated protocol NodeSeekNotificationClientProtocol {
    func loadUnreadCount() async throws -> NodeSeekNotificationUnreadCount
    func loadAtMe() async throws -> [NodeSeekNotificationRecord]
    func loadReplies() async throws -> [NodeSeekNotificationRecord]
    func loadMessageConversations() async throws -> [NodeSeekMessageConversationRecord]
    func markViewed(ids: [Int], tab: NodeSeekNotificationTab) async throws
    func markAllViewed(tab: NodeSeekNotificationTab) async throws
}

@MainActor
final class NodeSeekNotificationClient: NodeSeekNotificationClientProtocol {
    private let session: URLSession
    private let baseURL: URL
    private let decoder = JSONDecoder()
    private let cookiePreparer: @Sendable () async -> Void
    private let markViewedSubmitter: NodeSeekNotificationMarkViewedSubmitting

    init(
        session: URLSession = .shared,
        baseURL: URL = NodeSeekSite.baseURL,
        cookiePreparer: @escaping @Sendable () async -> Void = {
            await NodeSeekNotificationClient.prepareDefaultHTTPLoad()
        },
        markViewedSubmitter: NodeSeekNotificationMarkViewedSubmitting? = nil
    ) {
        self.session = session
        self.baseURL = baseURL
        self.cookiePreparer = cookiePreparer
        self.markViewedSubmitter = markViewedSubmitter ?? WebViewNodeSeekNotificationMarkViewedSubmitter()
    }

    @MainActor
    func loadUnreadCount() async throws -> NodeSeekNotificationUnreadCount {
        let request = makeRequest(
            path: "/api/notification/unread-count",
            referer: NodeSeekNotificationTab.atMe.webURL
        )
        let response = try await decode(UnreadCountResponse.self, from: request)
        guard response.success else {
            logBusinessFailure(for: request, message: nil)
            throw NodeSeekNotificationClientError.unsuccessfulResponse(nil)
        }
        let unreadCount = response.unreadCount
        AppLog.info(.service, "通知未读数 \(unreadCount.debugSummary)")
        return unreadCount
    }

    @MainActor
    func loadAtMe() async throws -> [NodeSeekNotificationRecord] {
        let request = makeRequest(
            path: "/api/notification/at-me/list",
            referer: NodeSeekNotificationTab.atMe.webURL
        )
        let response = try await decode(NotificationListResponse.self, from: request)
        guard response.success else {
            logBusinessFailure(for: request, message: response.message)
            throw NodeSeekNotificationClientError.unsuccessfulResponse(response.message)
        }
        return response.data
    }

    @MainActor
    func loadReplies() async throws -> [NodeSeekNotificationRecord] {
        let request = makeRequest(
            path: "/api/notification/reply-to-me/list",
            referer: NodeSeekNotificationTab.reply.webURL
        )
        let response = try await decode(NotificationListResponse.self, from: request)
        guard response.success else {
            logBusinessFailure(for: request, message: response.message)
            throw NodeSeekNotificationClientError.unsuccessfulResponse(response.message)
        }
        return response.data
    }

    @MainActor
    func loadMessageConversations() async throws -> [NodeSeekMessageConversationRecord] {
        let request = makeRequest(
            path: "/api/notification/message/list",
            referer: NodeSeekNotificationTab.message.webURL
        )
        let response = try await decode(MessageListResponse.self, from: request)
        guard response.success else {
            logBusinessFailure(for: request, message: response.message)
            throw NodeSeekNotificationClientError.unsuccessfulResponse(response.message)
        }
        return response.msgArray
    }

    @MainActor
    func markViewed(ids: [Int], tab: NodeSeekNotificationTab) async throws {
        let normalizedIDs = ids.filter { $0 > 0 }
        guard normalizedIDs.isEmpty == false else { return }

        let request = try NodeSeekNotificationMarkViewedRequest.single(ids: normalizedIDs, tab: tab)
        try await submitMarkViewed(request, referer: tab.webURL)
    }

    @MainActor
    func markAllViewed(tab: NodeSeekNotificationTab) async throws {
        let request = NodeSeekNotificationMarkViewedRequest.all(tab: tab)
        try await submitMarkViewed(request, referer: tab.webURL)
    }

    private func submitMarkViewed(
        _ request: NodeSeekNotificationMarkViewedRequest,
        referer: URL
    ) async throws {
        let operationID = UUID().uuidString
        let startedAt = Date()
        AppLog.info(.service, "通知已读操作开始 id=\(operationID), path=\(request.apiPath)")
        defer {
            AppLog.info(.service, "通知已读操作结束 id=\(operationID), elapsedMs=\(AppLog.elapsedMilliseconds(since: startedAt))")
        }
        do {
            try await markViewedSubmitter.submit(request, referer: referer)
            AppLog.info(.service, "通知已读 WebView 成功 id=\(operationID)")
        } catch {
            let failure = error as NSError
            AppLog.error(.service, "通知已读 WebView 失败 id=\(operationID), domain=\(failure.domain), code=\(failure.code), error=\(error.localizedDescription)")
            if case HiddenWebViewHTMLClientError.timeout = error {
                throw NodeSeekNotificationClientError.unsuccessfulResponse("请求超时，请重试")
            }
            if let failure = error as? URLError, failure.code == .timedOut {
                throw NodeSeekNotificationClientError.unsuccessfulResponse("请求超时，请重试")
            }
            if let failure = error as? NodeSeekNotificationClientError { throw failure }
            throw NodeSeekNotificationClientError.unsuccessfulResponse("标记已读失败，请稍后重试")
        }
    }

    private func makeRequest(
        path: String,
        queryItems: [URLQueryItem]? = nil,
        referer: URL
    ) -> URLRequest {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = path
        components?.queryItems = queryItems
        let url = components?.url ?? baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        WebRequestFingerprint.applyJSONHeaders(to: &request, referer: referer)
        return request
    }

    private func decode<Response: Decodable>(_ type: Response.Type, from request: URLRequest) async throws -> Response {
        let startedAt = Date()
        let method = request.notificationLogMethod
        let target = request.notificationLogURL
        AppLog.info(.service, "通知接口请求开始 method=\(method), url=\(target)")

        await cookiePreparer()
        let data: Data
        let urlResponse: URLResponse
        do {
            (data, urlResponse) = try await session.data(for: request)
        } catch {
            AppLog.error(
                .service,
                "通知接口请求失败 method=\(method), url=\(target), error=\(error.localizedDescription), elapsedMs=\(AppLog.elapsedMilliseconds(since: startedAt))"
            )
            throw error
        }

        if let response = urlResponse as? HTTPURLResponse {
            AppLog.info(.service, "通知接口响应元信息 path=\(request.url?.path ?? "nil"), status=\(response.statusCode), contentType=\(response.mimeType ?? "nil"), bytes=\(data.count), redirected=\(response.url != request.url)")
        }
        if let httpResponse = urlResponse as? HTTPURLResponse,
           (200..<300).contains(httpResponse.statusCode) == false {
            AppLog.warning(.service, "通知接口错误详情 path=\(request.url?.path ?? "nil"), \(NotificationErrorLogSummary.describe(data))")
            AppLog.warning(
                .service,
                "通知接口响应异常 method=\(method), url=\(target), status=\(httpResponse.statusCode), bytes=\(data.count), elapsedMs=\(AppLog.elapsedMilliseconds(since: startedAt))"
            )
            throw NodeSeekNotificationClientError.httpStatus(httpResponse.statusCode)
        }

        do {
            let decoded = try decoder.decode(Response.self, from: data)
            let status = httpStatusDescription(from: urlResponse)
            AppLog.info(
                .service,
                "通知接口响应成功 method=\(method), url=\(target), status=\(status), bytes=\(data.count), responseType=\(Response.self), elapsedMs=\(AppLog.elapsedMilliseconds(since: startedAt))"
            )
            return decoded
        } catch {
            let status = httpStatusDescription(from: urlResponse)
            AppLog.error(
                .service,
                "通知接口解析失败 method=\(method), url=\(target), status=\(status), bytes=\(data.count), responseType=\(Response.self), error=\(error.localizedDescription), elapsedMs=\(AppLog.elapsedMilliseconds(since: startedAt))"
            )
            throw error
        }
    }

    private func logBusinessFailure(for request: URLRequest, message: String?) {
        AppLog.warning(
            .service,
            "通知接口业务失败 method=\(request.notificationLogMethod), url=\(request.notificationLogURL), message=\(message ?? "nil")"
        )
    }

    private func httpStatusDescription(from response: URLResponse) -> String {
        guard let httpResponse = response as? HTTPURLResponse else { return "nil" }
        return String(httpResponse.statusCode)
    }

    @MainActor
    private static func prepareDefaultHTTPLoad() async {
        await NodeSeekCookieSession().prepareHTTPLoad()
    }
}

enum NotificationErrorLogSummary {
    static func describe(_ data: Data) -> String {
        // 仅提取错误字段，避免把通知正文、嵌套对象或 HTML 写入日志。
        guard data.count <= 65_536,
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return "jsonObject=false"
        }
        let fields = ["code", "errorCode", "message", "msg", "error"].compactMap { key -> String? in
            guard let value = object[key] else { return nil }
            let text: String
            if let string = value as? String {
                text = string
            } else if let number = value as? NSNumber {
                text = number.stringValue
            } else {
                return nil
            }
            return "\(key)=\(redact(text))"
        }
        return "jsonObject=true, " + (fields.isEmpty ? "errorFields=none" : fields.joined(separator: ", "))
    }

    private static func redact(_ text: String) -> String {
        var result = text
        let patterns = [
            #"(?i)(bearer\s+)[^\s,;]+"#,
            #"(?i)(cookie|authorization|password|token|secret|session|api[_-]?key)\s*[:=]\s*[^\s,;]+"#,
            #"https?://[^\s]+"#,
            #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#,
            #"[A-Za-z0-9_+/=-]{24,}"#
        ]
        for pattern in patterns {
            result = result.replacingOccurrences(of: pattern, with: "[redacted]", options: .regularExpression)
        }
        result = result.components(separatedBy: .controlCharacters).joined(separator: " ")
        return String(result.prefix(240))
    }
}

private extension URLRequest {
    var notificationLogMethod: String {
        httpMethod ?? "GET"
    }

    var notificationLogURL: String {
        url?.absoluteString ?? "nil"
    }
}

enum NodeSeekNotificationClientError: LocalizedError, Equatable {
    case httpStatus(Int)
    case unsuccessfulResponse(String?)

    var errorDescription: String? {
        switch self {
        case .httpStatus(let status):
            return "请求失败：HTTP \(status)"
        case .unsuccessfulResponse(let message):
            return message ?? "接口返回失败"
        }
    }
}

private extension NodeSeekNotificationTab {
    nonisolated var markViewedPath: String {
        switch self {
        case .atMe:
            return "/api/notification/at-me/markViewed"
        case .reply:
            return "/api/notification/reply-to-me/markViewed"
        case .message:
            return "/api/notification/message/markViewed"
        }
    }
}

private struct NotificationListResponse: Decodable {
    let success: Bool
    let data: [NodeSeekNotificationRecord]
    let message: String?

    private enum CodingKeys: String, CodingKey {
        case success
        case data
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
        data = try container.decodeIfPresent([NodeSeekNotificationRecord].self, forKey: .data) ?? []
        message = try container.decodeIfPresent(String.self, forKey: .message)
    }
}

private struct MessageListResponse: Decodable {
    let success: Bool
    let msgArray: [NodeSeekMessageConversationRecord]
    let message: String?

    private enum CodingKeys: String, CodingKey {
        case success
        case msgArray
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
        msgArray = try container.decodeIfPresent([NodeSeekMessageConversationRecord].self, forKey: .msgArray) ?? []
        message = try container.decodeIfPresent(String.self, forKey: .message)
    }
}

private struct UnreadCountResponse: Decodable {
    let success: Bool
    let unreadCount: NodeSeekNotificationUnreadCount
}

extension NodeSeekNotificationUnreadCount: Decodable {
    private enum CodingKeys: String, CodingKey {
        case message
        case atMe
        case reply
        case all
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decodeIfPresent(Int.self, forKey: .message) ?? 0
        atMe = try container.decodeIfPresent(Int.self, forKey: .atMe) ?? 0
        reply = try container.decodeIfPresent(Int.self, forKey: .reply) ?? 0
        all = try container.decodeIfPresent(Int.self, forKey: .all) ?? message + atMe + reply
    }
}

nonisolated struct NodeSeekNotificationMarkViewedRequest: Equatable {
    let apiPath: String
    let bodyJSON: String?

    static func single(
        ids: [Int],
        tab: NodeSeekNotificationTab,
        encoder: JSONEncoder = JSONEncoder()
    ) throws -> NodeSeekNotificationMarkViewedRequest {
        let body: NotificationMarkBody
        switch tab {
        case .atMe:
            body = NotificationMarkBody(atMe: ids)
        case .reply:
            body = NotificationMarkBody(replys: ids)
        case .message:
            body = NotificationMarkBody(messages: ids)
        }
        let data = try encoder.encode(body)
        return NodeSeekNotificationMarkViewedRequest(
            apiPath: tab.markViewedPath,
            bodyJSON: String(data: data, encoding: .utf8)
        )
    }

    static func all(tab: NodeSeekNotificationTab) -> NodeSeekNotificationMarkViewedRequest {
        NodeSeekNotificationMarkViewedRequest(
            apiPath: "\(tab.markViewedPath)?all=true",
            bodyJSON: nil
        )
    }
}

nonisolated private struct NotificationMarkBody: Encodable {
    let atMe: [Int]?
    let replys: [Int]?
    let messages: [Int]?

    init(atMe: [Int]? = nil, replys: [Int]? = nil, messages: [Int]? = nil) {
        self.atMe = atMe
        self.replys = replys
        self.messages = messages
    }
}
