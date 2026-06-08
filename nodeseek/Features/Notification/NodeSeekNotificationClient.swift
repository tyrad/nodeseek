//
//  NodeSeekNotificationClient.swift
//  nodeseek
//
//  Created by Codex on 2026/6/8.
//

import Foundation

protocol NodeSeekNotificationClientProtocol {
    func loadUnreadCount() async throws -> NodeSeekNotificationUnreadCount
    func loadAtMe() async throws -> [NodeSeekNotificationRecord]
    func loadReplies() async throws -> [NodeSeekNotificationRecord]
    func loadMessageConversations() async throws -> [NodeSeekMessageConversationRecord]
    func markViewed(ids: [Int], tab: NodeSeekNotificationTab) async throws
    func markAllViewed(tab: NodeSeekNotificationTab) async throws
}

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
        markViewedSubmitter: NodeSeekNotificationMarkViewedSubmitting = WebViewNodeSeekNotificationMarkViewedSubmitter()
    ) {
        self.session = session
        self.baseURL = baseURL
        self.cookiePreparer = cookiePreparer
        self.markViewedSubmitter = markViewedSubmitter
    }

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
        return response.unreadCount
    }

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

    func markViewed(ids: [Int], tab: NodeSeekNotificationTab) async throws {
        let normalizedIDs = ids.filter { $0 > 0 }
        guard normalizedIDs.isEmpty == false else { return }

        let request = try NodeSeekNotificationMarkViewedRequest.single(ids: normalizedIDs, tab: tab)
        try await markViewedSubmitter.submit(request, referer: tab.webURL)
    }

    func markAllViewed(tab: NodeSeekNotificationTab) async throws {
        let request = NodeSeekNotificationMarkViewedRequest.all(tab: tab)
        try await markViewedSubmitter.submit(request, referer: tab.webURL)
    }

    private func makeRequest(
        path: String,
        queryItems: [URLQueryItem]? = nil,
        method: String = "GET",
        body: Data? = nil,
        referer: URL
    ) -> URLRequest {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = path
        components?.queryItems = queryItems
        let url = components?.url ?? baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
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

        if let httpResponse = urlResponse as? HTTPURLResponse,
           (200..<300).contains(httpResponse.statusCode) == false {
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
