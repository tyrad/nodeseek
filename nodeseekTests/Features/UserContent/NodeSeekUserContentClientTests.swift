//
//  NodeSeekUserContentClientTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/5/11.
//

import Foundation
import Testing
@testable import nodeseek

@Suite(.serialized)
struct NodeSeekUserContentClientTests {
    @Test func accountUIDParsesSpaceProfileURL() throws {
        let account = AccountResponse(
            displayName: "mistj",
            isLoggedIn: true,
            profileURL: URL(string: "https://www.nodeseek.com/space/31037")!
        )

        #expect(account.nodeSeekUID == 31037)
    }

    @Test func loadsCollectionsFromJSONAPI() async throws {
        let client = makeClient(
            responseBody: """
            {
              "success": true,
              "collections": [
                { "title": "如何把ChatGPT Plus订阅转换为API？", "post_id": 711961, "rank": 0 }
              ]
            }
            """
        )

        let records = try await client.loadCollections(page: 2, uid: 31037)

        #expect(MockURLProtocol.lastRequest?.url?.absoluteString == "https://www.nodeseek.com/api/statistics/list-collection?page=2")
        #expect(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Referer") == "https://www.nodeseek.com/space/31037")
        #expect(records == [
            UserCollectionRecord(title: "如何把ChatGPT Plus订阅转换为API？", postID: 711961, rank: 0)
        ])
    }

    @Test func loadsCommentsFromJSONAPI() async throws {
        let client = makeClient(
            responseBody: """
            {
              "success": true,
              "comments": [
                {
                  "post_id": 715245,
                  "title": "已抽个GPT Plus",
                  "rank": 1,
                  "floor_id": 18,
                  "text": "让了让了 "
                }
              ]
            }
            """
        )

        let records = try await client.loadComments(uid: 31037, page: 4)

        #expect(MockURLProtocol.lastRequest?.url?.absoluteString == "https://www.nodeseek.com/api/content/list-comments?uid=31037&page=4")
        #expect(records == [
            UserCommentRecord(postID: 715245, title: "已抽个GPT Plus", rank: 1, floorID: 18, text: "让了让了 ")
        ])
    }

    @Test func loadsDiscussionsFromJSONAPI() async throws {
        let client = makeClient(
            responseBody: """
            {
              "success": true,
              "discussions": [
                { "rank": 0, "title": "【开源】使用codex撸了一个nodeseek的iOS客户端", "post_id": 717963 }
              ]
            }
            """
        )

        let records = try await client.loadDiscussions(uid: 31037, page: 1)

        #expect(MockURLProtocol.lastRequest?.url?.absoluteString == "https://www.nodeseek.com/api/content/list-discussions?uid=31037&page=1")
        #expect(records == [
            UserDiscussionRecord(rank: 0, title: "【开源】使用codex撸了一个nodeseek的iOS客户端", postID: 717963)
        ])
    }
}

private func makeClient(responseBody: String) -> NodeSeekUserContentClient {
    MockURLProtocol.responseData = Data(responseBody.utf8)
    MockURLProtocol.lastRequest = nil
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: configuration)
    return NodeSeekUserContentClient(session: session)
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
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
