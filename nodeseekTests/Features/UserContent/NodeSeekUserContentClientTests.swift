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

    @Test func loadsOtherUserProfileFromJSONAPI() async throws {
        let client = makeClient(
            responseBody: """
            {"success":true,"detail":{"member_id":1,"member_name":"Lloyd","isAdmin":1,"rank":6,
             "coin":8282,"stardust":21,"bio":"本论坛的创建者","created_at":"2022-11-23T17:11:12.000Z",
             "nPost":26,"nComment":90,"follows":0,"fans":77,"readme":"一时兴起写了这个社区",
             "created_at_str":"1436days ago",
             "roles":[{"id":1,"name":"creater","display_text":"服主"},{"id":2,"name":"admin","display_text":"管理"}],
             "followed":false}}
            """
        )

        let profile = try await client.loadProfile(uid: 1)

        #expect(MockURLProtocol.lastRequest?.url?.absoluteString == "https://www.nodeseek.com/api/account/getInfo/1?readme=1")
        #expect(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Referer") == "https://www.nodeseek.com/space/1")
        #expect(profile.name == "Lloyd")
        #expect(profile.rank == 6)
        #expect(profile.coin == 8282)
        #expect(profile.stardust == 21)
        #expect(profile.postCount == 26)
        #expect(profile.commentCount == 90)
        #expect(profile.fans == 77)
        #expect(profile.collectionCount == nil)
        #expect(profile.roleNames == ["服主", "管理"])
        #expect(profile.readme == "一时兴起写了这个社区")
        #expect(profile.createdAt == ISO8601DateFormatter().date(from: "2022-11-23T17:11:12Z"))
    }

    @Test func loadsSelfProfileWithCollectionCountAndNoRoles() async throws {
        let client = makeClient(
            responseBody: """
            {"success":true,"detail":{"member_id":31037,"member_name":"缭雾","isAdmin":0,"rank":4,
             "coin":1758,"stardust":11,"bio":"","created_at":"2025-04-27T14:29:22.000Z",
             "nPost":19,"nComment":550,"follows":0,"fans":3,"collectionCount":58,
             "readme":"这个人很懒，什么都没写。","roles":[],"followed":false}}
            """
        )

        let profile = try await client.loadProfile(uid: 31037)

        #expect(profile.collectionCount == 58)
        #expect(profile.roleNames.isEmpty)
        #expect(profile.bio.isEmpty)
        #expect(profile.follows == 0)
    }

    @Test func profileFailureThrows() async throws {
        let client = makeClient(responseBody: #"{"success":false,"message":"用户不存在"}"#)

        await #expect(throws: UserContentClientError.self) {
            _ = try await client.loadProfile(uid: 999999999)
        }
    }

    @Test func loadsTodayProgressWithCheckIn() async throws {
        defer { MockURLProtocol.responsesByPath = [:] }
        MockURLProtocol.responsesByPath = [
            "/api/progress/today": #"{"success":true,"postBonusCount":1,"maxPostBonusCount":4,"commentBonusCount":3,"maxCommentBonusCount":20,"maxFreeLike":3,"freeLikeUsed":2}"#,
            "/api/attendance/board": #"{"list":[],"record":{"id":1,"member_id":31037,"day_id":1484,"gain":6}}"#
        ]
        let client = makeClient(responseBody: "{}")

        let progress = try await client.loadTodayProgress(uid: 31037)

        #expect(progress == UserTodayProgressRecord(
            postBonusCount: 1,
            maxPostBonusCount: 4,
            commentBonusCount: 3,
            maxCommentBonusCount: 20,
            freeLikeUsed: 2,
            maxFreeLike: 3,
            checkInGain: 6
        ))
        #expect(progress.postCoin == 5)
        #expect(progress.maxPostCoin == 20)
    }

    @Test func todayProgressWithoutCheckInHasNilGain() async throws {
        defer { MockURLProtocol.responsesByPath = [:] }
        MockURLProtocol.responsesByPath = [
            "/api/progress/today": #"{"success":true,"postBonusCount":0,"maxPostBonusCount":4,"commentBonusCount":0,"maxCommentBonusCount":20,"maxFreeLike":3,"freeLikeUsed":0}"#,
            "/api/attendance/board": #"{"list":[],"record":null}"#
        ]
        let client = makeClient(responseBody: "{}")

        let progress = try await client.loadTodayProgress(uid: 31037)

        #expect(progress.checkInGain == nil)
    }

    @Test func joinedDaysRoundsUpPartialDay() {
        let createdAt = ISO8601DateFormatter().date(from: "2025-04-27T14:29:22Z")!
        let now = ISO8601DateFormatter().date(from: "2026-10-30T02:00:00Z")!
        let profile = makeProfile(rank: 4, coin: 1758, createdAt: createdAt)

        #expect(profile.joinedDays(now: now) == 551)
    }

    @Test func levelProgressMatchesWebThresholds() {
        let progress = UserLevelProgress(rank: 4, coin: 1758)

        #expect(progress.lowerBound == 1600)
        #expect(progress.upperBound == 2500)
        #expect(progress.remaining == 742)
        #expect(abs(progress.fraction - 158.0 / 900.0) < 0.0001)
        #expect(progress.isMaxRank == false)
    }

    @Test func levelSixIsMaxRank() {
        let progress = UserLevelProgress(rank: 6, coin: 8282)

        #expect(progress.isMaxRank)
        #expect(progress.fraction == 1)
    }

    @Test func profileRouterResolvesSpaceURLs() {
        #expect(UserProfileRouter.nativeUID(for: URL(string: "https://www.nodeseek.com/space/31037#/general")!) == 31037)
        #expect(UserProfileRouter.nativeUID(for: URL(string: "/space/1")!) == 1)
        #expect(UserProfileRouter.nativeUID(for: URL(string: "https://www.nodeseek.com/board")!) == nil)
        #expect(UserProfileRouter.nativeUID(for: URL(string: "https://example.com/space/1")!) == nil)
        #expect(UserProfileRouter.nativeUID(for: URL(string: "https://www.nodeseek.com/space/abc")!) == nil)
    }
}

private func makeProfile(rank: Int, coin: Int, createdAt: Date?) -> UserProfileRecord {
    UserProfileRecord(
        uid: 31037,
        name: "缭雾",
        rank: rank,
        coin: coin,
        stardust: 0,
        bio: "",
        readme: "",
        createdAt: createdAt,
        postCount: 0,
        commentCount: 0,
        follows: 0,
        fans: 0,
        collectionCount: nil,
        roleNames: []
    )
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
    /// 一次调用多个接口时按路径返回；为空时统一用 responseData
    static var responsesByPath: [String: String] = [:]
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
        let body = request.url.flatMap { Self.responsesByPath[$0.path] }.map { Data($0.utf8) } ?? Self.responseData
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
