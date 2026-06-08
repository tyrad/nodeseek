//
//  NodeSeekNotificationClientTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/6/8.
//

import Foundation
import Testing
@testable import nodeseek

@Suite(.serialized)
struct NodeSeekNotificationClientTests {
    @Test func loadsAtMeNotificationsFromJSONAPI() async throws {
        let counter = CookiePrepareCounter()
        let client = makeClient(
            responseBody: """
            {
              "success": true,
              "data": [
                {
                  "id": 3056861,
                  "viewed": 0,
                  "comment_id": 10503771,
                  "floor_id": 11,
                  "created_at": "2026-06-06T03:50:41.000Z",
                  "commenter_id": 24060,
                  "title": "奥特曼咋还不重置啊，出了这么大封号乌龙事件",
                  "post_id": 763505,
                  "first_comment_id": 10501640,
                  "commenter_name": "kiya"
                }
              ]
            }
            """,
            counter: counter
        )

        let records = try await client.loadAtMe()

        #expect(counter.count == 1)
        #expect(MockNotificationURLProtocol.lastRequest?.url?.absoluteString == "https://www.nodeseek.com/api/notification/at-me/list")
        #expect(MockNotificationURLProtocol.lastRequest?.value(forHTTPHeaderField: "Referer") == "https://www.nodeseek.com/notification#/atMe")
        #expect(records.count == 1)
        let record = try #require(records.first)
        #expect(record.id == 3056861)
        #expect(record.isViewed == false)
        #expect(record.commentPage == 2)
        #expect(record.anchorID == "11")
        #expect(record.avatarURL.absoluteString == "https://www.nodeseek.com/avatar/24060.png")
        #expect(record.profileURL.absoluteString == "https://www.nodeseek.com/space/24060")
        #expect(record.postSummary.url.absoluteString == "https://www.nodeseek.com/post-763505-1")
    }

    @Test func loadsUnreadCount() async throws {
        let client = makeClient(
            responseBody: """
            {
              "success": true,
              "unreadCount": {
                "message": 2,
                "atMe": 3,
                "reply": 4,
                "all": 9
              }
            }
            """
        )

        let count = try await client.loadUnreadCount()

        #expect(MockNotificationURLProtocol.lastRequest?.url?.absoluteString == "https://www.nodeseek.com/api/notification/unread-count")
        #expect(count.message == 2)
        #expect(count.atMe == 3)
        #expect(count.reply == 4)
        #expect(count.all == 9)
    }

    @Test func marksAtMeNotificationViewedWithNotificationIDBody() async throws {
        let client = makeClient(responseBody: #"{"success":true}"#)

        try await client.markViewed(ids: [3056861], tab: .atMe)

        let request = try #require(MockNotificationURLProtocol.lastRequest)
        #expect(request.url?.absoluteString == "https://www.nodeseek.com/api/notification/at-me/markViewed")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Referer") == "https://www.nodeseek.com/notification#/atMe")
        let body = try #require(requestBodyData(request))
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: [Int]])
        #expect(json["atMe"] == [3056861])
    }

    @Test func marksAllRepliesViewed() async throws {
        let client = makeClient(responseBody: #"{"success":true}"#)

        try await client.markAllViewed(tab: .reply)

        let request = try #require(MockNotificationURLProtocol.lastRequest)
        #expect(request.url?.absoluteString == "https://www.nodeseek.com/api/notification/reply-to-me/markViewed?all=true")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Referer") == "https://www.nodeseek.com/notification#/reply")
    }

    @Test func loadsMessageConversationsAndResolvesParticipant() async throws {
        let client = makeClient(
            responseBody: """
            {
              "success": true,
              "msgArray": [
                {
                  "receiver_id": 31037,
                  "sender_id": 24060,
                  "max_id": 920,
                  "content": "hello",
                  "created_at": "2026-06-05T12:59:10.000Z",
                  "viewed": 0,
                  "sender_name": "kiya",
                  "receiver_name": "mistj"
                }
              ]
            }
            """
        )

        let records = try await client.loadMessageConversations()

        #expect(MockNotificationURLProtocol.lastRequest?.url?.absoluteString == "https://www.nodeseek.com/api/notification/message/list")
        let record = try #require(records.first)
        #expect(record.participantID(currentUserID: 31037) == 24060)
        #expect(record.participantName(currentUserID: 31037) == "kiya")
        #expect(record.conversationWebURL(currentUserID: 31037).absoluteString == "https://www.nodeseek.com/notification#/message?mode=talk&to=24060")
    }
}

private func makeClient(
    responseBody: String,
    counter: CookiePrepareCounter = CookiePrepareCounter()
) -> NodeSeekNotificationClient {
    MockNotificationURLProtocol.responseData = Data(responseBody.utf8)
    MockNotificationURLProtocol.lastRequest = nil
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockNotificationURLProtocol.self]
    let session = URLSession(configuration: configuration)
    return NodeSeekNotificationClient(
        session: session,
        cookiePreparer: {
            counter.increment()
        }
    )
}

private func requestBodyData(_ request: URLRequest) -> Data? {
    if let httpBody = request.httpBody {
        return httpBody
    }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let bufferSize = 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }
    while stream.hasBytesAvailable {
        let readCount = stream.read(buffer, maxLength: bufferSize)
        if readCount <= 0 { break }
        data.append(buffer, count: readCount)
    }
    return data
}

private final class CookiePrepareCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }
}

private final class MockNotificationURLProtocol: URLProtocol, @unchecked Sendable {
    static var responseData = Data()
    static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
