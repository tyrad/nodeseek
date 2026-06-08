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
    private let encoder = JSONEncoder()
    private let cookiePreparer: @Sendable () async -> Void

    init(
        session: URLSession = .shared,
        baseURL: URL = NodeSeekSite.baseURL,
        cookiePreparer: @escaping @Sendable () async -> Void = {
            await NodeSeekNotificationClient.prepareDefaultHTTPLoad()
        }
    ) {
        self.session = session
        self.baseURL = baseURL
        self.cookiePreparer = cookiePreparer
    }

    func loadUnreadCount() async throws -> NodeSeekNotificationUnreadCount {
        let request = makeRequest(
            path: "/api/notification/unread-count",
            referer: NodeSeekNotificationTab.atMe.webURL
        )
        let response = try await decode(UnreadCountResponse.self, from: request)
        guard response.success else { throw NodeSeekNotificationClientError.unsuccessfulResponse(nil) }
        return response.unreadCount
    }

    func loadAtMe() async throws -> [NodeSeekNotificationRecord] {
        let request = makeRequest(
            path: "/api/notification/at-me/list",
            referer: NodeSeekNotificationTab.atMe.webURL
        )
        let response = try await decode(NotificationListResponse.self, from: request)
        guard response.success else {
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
            throw NodeSeekNotificationClientError.unsuccessfulResponse(response.message)
        }
        return response.msgArray
    }

    func markViewed(ids: [Int], tab: NodeSeekNotificationTab) async throws {
        let normalizedIDs = ids.filter { $0 > 0 }
        guard normalizedIDs.isEmpty == false else { return }

        let body: Data
        switch tab {
        case .atMe:
            body = try encoder.encode(NotificationMarkBody(atMe: normalizedIDs))
        case .reply:
            body = try encoder.encode(NotificationMarkBody(replys: normalizedIDs))
        case .message:
            body = try encoder.encode(NotificationMarkBody(messages: normalizedIDs))
        }

        let request = makeRequest(
            path: tab.markViewedPath,
            method: "POST",
            body: body,
            referer: tab.webURL
        )
        try await validateActionResponse(from: request)
    }

    func markAllViewed(tab: NodeSeekNotificationTab) async throws {
        let request = makeRequest(
            path: tab.markViewedPath,
            queryItems: [URLQueryItem(name: "all", value: "true")],
            method: "POST",
            referer: tab.webURL
        )
        try await validateActionResponse(from: request)
    }

    private func validateActionResponse(from request: URLRequest) async throws {
        let response = try await decode(ActionResponse.self, from: request)
        guard response.success else {
            throw NodeSeekNotificationClientError.unsuccessfulResponse(response.message)
        }
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
        await cookiePreparer()
        let (data, urlResponse) = try await session.data(for: request)
        if let httpResponse = urlResponse as? HTTPURLResponse,
           (200..<300).contains(httpResponse.statusCode) == false {
            throw NodeSeekNotificationClientError.httpStatus(httpResponse.statusCode)
        }
        return try decoder.decode(Response.self, from: data)
    }

    @MainActor
    private static func prepareDefaultHTTPLoad() async {
        await NodeSeekCookieSession().prepareHTTPLoad()
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
    var markViewedPath: String {
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

private struct NotificationMarkBody: Encodable {
    let atMe: [Int]?
    let replys: [Int]?
    let messages: [Int]?

    init(atMe: [Int]? = nil, replys: [Int]? = nil, messages: [Int]? = nil) {
        self.atMe = atMe
        self.replys = replys
        self.messages = messages
    }
}

private struct ActionResponse: Decodable {
    let success: Bool
    let message: String?
}
