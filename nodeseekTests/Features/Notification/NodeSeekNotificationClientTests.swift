//
//  NodeSeekNotificationClientTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/6/8.
//

import Foundation
import Testing
@testable import nodeseek

@MainActor
@Suite(.serialized)
struct NodeSeekNotificationClientTests {
    @Test func errorLogSummaryExtractsOnlySafeErrorFields() {
        let data = Data(#"{"code":403,"message":"Invalid origin","data":{"content":"private notification"},"token":"private-token"}"#.utf8)
        #expect(NotificationErrorLogSummary.describe(data) == "jsonObject=true, code=403, message=Invalid origin")
        let sensitive = Data(#"{"message":"token=abc123 user@example.com https://example.com/?secret=abc\nDenied"}"#.utf8)
        let summary = NotificationErrorLogSummary.describe(sensitive)
        #expect(!summary.contains("abc123"))
        #expect(!summary.contains("user@example.com"))
        #expect(!summary.contains("https://"))
        #expect(!summary.contains("\n"))
        #expect(summary.contains("Denied"))
        #expect(NotificationErrorLogSummary.describe(Data("<html>private</html>".utf8)) == "jsonObject=false")
    }

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

    @Test func writesNotificationAPIRequestLogs() async throws {
        try await withTemporaryFileLogging {
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

            _ = try await client.loadUnreadCount()
            AppLog.flushFileLogsForTesting()

            let content = try AppLog.fileLogContent()
            #expect(content.contains("[info] [Service] ["))
            #expect(content.contains("通知接口请求开始 method=GET, url=https://www.nodeseek.com/api/notification/unread-count"))
            #expect(content.contains("通知接口响应成功 method=GET, url=https://www.nodeseek.com/api/notification/unread-count"))
            #expect(content.contains("通知未读数 message=2, atMe=3, reply=4, all=9"))
            #expect(content.contains("status=200"))
            #expect(content.contains("responseType=UnreadCountResponse"))
        }
    }

    @Test func marksViewedDirectlyThroughWebView() async throws {
        let submitter = SpyNotificationMarkViewedSubmitter()
        let client = makeClient(responseBody: "invalid", markViewedSubmitter: submitter)
        try await client.markViewed(ids: [0, 3056861], tab: .atMe)
        let submissions = await submitter.submissions()
        #expect(submissions.count == 1)
        let submission = try #require(submissions.first)
        #expect(submission.request.apiPath == "/api/notification/at-me/markViewed")
        #expect(submission.referer.absoluteString == "https://www.nodeseek.com/notification#/atMe")
        let body = try #require(submission.request.bodyJSON)
        let json = try #require(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: [Int]])
        #expect(json["atMe"] == [3056861])
        #expect(MockNotificationURLProtocol.lastRequest == nil)
    }

    @Test func marksAllDirectlyThroughWebView() async throws {
        let submitter = SpyNotificationMarkViewedSubmitter()
        let client = makeClient(responseBody: "invalid", markViewedSubmitter: submitter)
        try await client.markAllViewed(tab: .reply)
        let submissions = await submitter.submissions()
        #expect(submissions.count == 1)
        #expect(submissions.first?.request.apiPath == "/api/notification/reply-to-me/markViewed?all=true")
        #expect(submissions.first?.request.bodyJSON == nil)
        #expect(MockNotificationURLProtocol.lastRequest == nil)
    }

    @Test func skipsInvalidIDs() async throws {
        let submitter = SpyNotificationMarkViewedSubmitter()
        let client = makeClient(responseBody: "invalid", markViewedSubmitter: submitter)
        try await client.markViewed(ids: [0, -1], tab: .atMe)
        #expect(await submitter.submissions().isEmpty)
        #expect(MockNotificationURLProtocol.lastRequest == nil)
    }

    @Test func translatesPageTimeoutToRetryMessage() async throws {
        let client = makeClient(responseBody: "invalid", markViewedSubmitter: TimeoutNotificationSubmitter())
        await #expect(throws: NodeSeekNotificationClientError.unsuccessfulResponse("请求超时，请重试")) {
            try await client.markAllViewed(tab: .atMe)
        }
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

@MainActor
private func makeClient(
    responseBody: String,
    counter: CookiePrepareCounter = CookiePrepareCounter(),
    markViewedSubmitter: NodeSeekNotificationMarkViewedSubmitting = SpyNotificationMarkViewedSubmitter()
) -> NodeSeekNotificationClient {
    MockNotificationURLProtocol.responseData = Data(responseBody.utf8)
    MockNotificationURLProtocol.lastRequest = nil
    MockNotificationURLProtocol.lastRequestBody = nil
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockNotificationURLProtocol.self]
    let session = URLSession(configuration: configuration)
    return NodeSeekNotificationClient(
        session: session,
        cookiePreparer: {
            counter.increment()
        },
        markViewedSubmitter: markViewedSubmitter
    )
}

private func withTemporaryFileLogging(_ body: () async throws -> Void) async throws {
    try await FileLoggingTestGate.shared.withExclusiveAccess {
        let previousFileLoggingEnabled = NodeSeekDebugConfig.enableFileLogging
        let previousAvatarLoggingEnabled = NodeSeekDebugConfig.enableAvatarImageLogs
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
            NodeSeekDebugConfig.enableFileLogging = previousFileLoggingEnabled
            NodeSeekDebugConfig.enableAvatarImageLogs = previousAvatarLoggingEnabled
            AppLog.setFileLogDirectoryForTesting(nil)
        }

        AppLog.setFileLogDirectoryForTesting(directory)
        NodeSeekDebugConfig.enableFileLogging = true
        try await body()
    }
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

private actor SpyNotificationMarkViewedSubmitter {
    struct Submission {
        let request: NodeSeekNotificationMarkViewedRequest
        let referer: URL
    }

    private var values: [Submission] = []

    func submit(_ request: NodeSeekNotificationMarkViewedRequest, referer: URL) async throws {
        values.append(Submission(request: request, referer: referer))
    }

    func submissions() -> [Submission] {
        values
    }
}

// 避免编译器将协议的 nonisolated 隔离推断到 actor 声明。
extension SpyNotificationMarkViewedSubmitter: NodeSeekNotificationMarkViewedSubmitting {}

private final class MockNotificationURLProtocol: URLProtocol, @unchecked Sendable {
    static var responseData = Data()
    static var lastRequest: URLRequest?
    static var lastRequestBody: Data?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lastRequest = request
        Self.lastRequestBody = request.httpBody ?? Self.readHTTPBodyStream(from: request)
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

    private static func readHTTPBodyStream(from request: URLRequest) -> Data? {
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data.isEmpty ? nil : data
    }
}

private struct TimeoutNotificationSubmitter: NodeSeekNotificationMarkViewedSubmitting {
    func submit(_ request: NodeSeekNotificationMarkViewedRequest, referer: URL) async throws {
        throw HiddenWebViewHTMLClientError.timeout
    }
}
