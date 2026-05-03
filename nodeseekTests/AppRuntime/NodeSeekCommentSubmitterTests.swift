//
//  NodeSeekCommentSubmitterTests.swift
//  nodeseekTests
//

import Foundation
import Testing
@testable import nodeseek

@MainActor
struct NodeSeekCommentSubmitterTests {
    @Test func submitsCommentThroughPageAutomation() async throws {
        let automation = CapturingCommentAutomation(response: .init(ok: true, statusCode: 200, message: nil, reason: "submitted"))
        let submitter = NodeSeekCommentSubmitter(
            baseURL: URL(string: "https://www.nodeseek.com")!,
            automation: automation
        )

        let result = try await submitter.submitComment(
            postID: "706958",
            content: "bdbd",
            referer: URL(string: "https://www.nodeseek.com/post-706958-1")!
        )

        let submission = try #require(automation.submissions.first)
        #expect(result.message == nil)
        #expect(submission.postID == 706958)
        #expect(submission.content == "bdbd")
        #expect(submission.referer.absoluteString == "https://www.nodeseek.com/post-706958-1")
    }

    @Test func surfacesServerMessageFromPageAutomation() async throws {
        let automation = CapturingCommentAutomation(response: .init(ok: false, statusCode: 400, message: "内容不能为空", reason: "server_error"))
        let submitter = NodeSeekCommentSubmitter(
            baseURL: URL(string: "https://www.nodeseek.com")!,
            automation: automation
        )

        do {
            _ = try await submitter.submitComment(
                postID: "706958",
                content: "",
                referer: URL(string: "https://www.nodeseek.com/post-706958-1")!
            )
            Issue.record("空内容错误应抛出")
        } catch let error as NodeSeekCommentSubmitterError {
            #expect(error.errorDescription == "内容不能为空")
        }
    }

    @Test func surfacesChallengeFromPageAutomation() async throws {
        let automation = CapturingCommentAutomation(response: .init(ok: false, statusCode: 403, message: "站点当前返回了拦截页面，请稍后重试。", reason: "challenge"))
        let submitter = NodeSeekCommentSubmitter(
            baseURL: URL(string: "https://www.nodeseek.com")!,
            automation: automation
        )

        do {
            _ = try await submitter.submitComment(
                postID: "706958",
                content: "bdbd",
                referer: URL(string: "https://www.nodeseek.com/post-706958-1")!
            )
            Issue.record("站点挑战错误应抛出")
        } catch let error as NodeSeekCommentSubmitterError {
            #expect(error == .challengeRequired("站点当前返回了拦截页面，请稍后重试。"))
        }
    }

    @Test func favoritePostUsesCollectionJSONAPIWithCurrentFingerprintAndCookies() async throws {
        let protocolType = CollectionURLProtocol.self
        protocolType.reset()
        protocolType.stub(
            data: #"{"message":"ok"}"#.data(using: .utf8)!,
            statusCode: 200,
            for: URL(string: "https://www.nodeseek.com/api/statistics/collection")!
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [protocolType]
        let session = URLSession(configuration: configuration)
        let cookieSynchronizer = CapturingCookieSynchronizer()
        let submitter = NodeSeekPostCollectionSubmitter(
            baseURL: URL(string: "https://www.nodeseek.com")!,
            session: session,
            cookieSynchronizer: cookieSynchronizer
        )

        let response = try await submitter.addFavorite(
            postID: "711860",
            referer: URL(string: "https://www.nodeseek.com/post-711860-1")!
        )

        let request = try #require(protocolType.requests.first)
        let body = try #require(protocolType.requestBodies.first ?? nil)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(response.message == "ok")
        #expect(cookieSynchronizer.syncCount == 1)
        #expect(request.url?.absoluteString == "https://www.nodeseek.com/api/statistics/collection")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == WebRequestFingerprint.userAgent)
        #expect(request.value(forHTTPHeaderField: "Referer") == "https://www.nodeseek.com/post-711860-1")
        #expect(json["postId"] as? Int == 711860)
        #expect(json["action"] as? String == "add")
    }
}

private final class CapturingCommentAutomation: CommentSubmissionAutomating {
    private(set) var submissions: [(postID: Int, content: String, referer: URL)] = []
    private let response: CommentAutomationResponse

    init(response: CommentAutomationResponse) {
        self.response = response
    }

    func submitComment(postID: Int, content: String, referer: URL) async throws -> CommentAutomationResponse {
        submissions.append((postID: postID, content: content, referer: referer))
        return response
    }
}

@MainActor
private final class CapturingCookieSynchronizer: CookieSynchronizing {
    private(set) var syncCount = 0

    func syncWebViewCookiesToURLSession() async {
        syncCount += 1
    }
}

private final class CollectionURLProtocol: URLProtocol, @unchecked Sendable {
    private struct Stub: Sendable {
        let data: Data
        let statusCode: Int
    }

    private static let lock = NSLock()
    private static var stubs: [String: Stub] = [:]
    private static var capturedRequests: [URLRequest] = []
    private static var capturedRequestBodies: [Data?] = []

    static var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return capturedRequests
    }

    static var requestBodies: [Data?] {
        lock.lock()
        defer { lock.unlock() }
        return capturedRequestBodies
    }

    static func reset() {
        lock.lock()
        stubs.removeAll()
        capturedRequests.removeAll()
        capturedRequestBodies.removeAll()
        lock.unlock()
    }

    static func stub(data: Data, statusCode: Int, for url: URL) {
        lock.lock()
        stubs[url.absoluteString] = Stub(data: data, statusCode: statusCode)
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let requestBody = Self.bodyData(from: request)

        Self.lock.lock()
        Self.capturedRequests.append(request)
        Self.capturedRequestBodies.append(requestBody)
        let stub = Self.stubs[url.absoluteString]
        Self.lock.unlock()

        guard let stub else {
            client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
            return
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: stub.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
            } else {
                break
            }
        }
        return data
    }
}
