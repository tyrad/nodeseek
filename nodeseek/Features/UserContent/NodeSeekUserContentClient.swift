//
//  NodeSeekUserContentClient.swift
//  nodeseek
//
//  Created by Codex on 2026/5/11.
//

import Foundation

final class NodeSeekUserContentClient {
    private let session: URLSession
    private let baseURL: URL
    private let decoder = JSONDecoder()

    init(
        session: URLSession = .shared,
        baseURL: URL = NodeSeekSite.baseURL
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    func loadCollections(page: Int, uid: Int) async throws -> [UserCollectionRecord] {
        let request = makeRequest(
            path: "/api/statistics/list-collection",
            queryItems: [
                URLQueryItem(name: "page", value: "\(max(1, page))")
            ],
            refererUID: uid
        )
        let response = try await decode(CollectionResponse.self, from: request)
        guard response.success else { throw UserContentClientError.unsuccessfulResponse }
        return response.collections.map {
            UserCollectionRecord(title: $0.title, postID: $0.postID, rank: $0.rank)
        }
    }

    func loadComments(uid: Int, page: Int) async throws -> [UserCommentRecord] {
        let request = makeRequest(
            path: "/api/content/list-comments",
            queryItems: [
                URLQueryItem(name: "uid", value: "\(uid)"),
                URLQueryItem(name: "page", value: "\(max(1, page))")
            ],
            refererUID: uid
        )
        let response = try await decode(CommentResponse.self, from: request)
        guard response.success else { throw UserContentClientError.unsuccessfulResponse }
        return response.comments.map {
            UserCommentRecord(
                postID: $0.postID,
                title: $0.title,
                rank: $0.rank,
                floorID: $0.floorID,
                text: $0.text
            )
        }
    }

    func loadDiscussions(uid: Int, page: Int) async throws -> [UserDiscussionRecord] {
        let request = makeRequest(
            path: "/api/content/list-discussions",
            queryItems: [
                URLQueryItem(name: "uid", value: "\(uid)"),
                URLQueryItem(name: "page", value: "\(max(1, page))")
            ],
            refererUID: uid
        )
        let response = try await decode(DiscussionResponse.self, from: request)
        guard response.success else { throw UserContentClientError.unsuccessfulResponse }
        return response.discussions.map {
            UserDiscussionRecord(rank: $0.rank, title: $0.title, postID: $0.postID)
        }
    }

    func loadStardust(uid: Int, beforeID: Int? = nil) async throws -> UserStardustPage {
        var query = [URLQueryItem(name: "count", value: "10"), URLQueryItem(name: "member_id", value: "\(uid)")]
        if let beforeID { query.append(URLQueryItem(name: "before_id", value: "\(beforeID)")) }
        let response = try await decode(
            StardustResponse.self,
            from: makeRequest(path: "/api/stardust/list", queryItems: query, refererUID: uid)
        )
        guard response.success, let records = response.records, let hasMore = response.hasMore else {
            throw UserContentClientError.unsuccessfulResponse
        }
        return UserStardustPage(records: records, hasMore: hasMore, cursor: response.cursor)
    }

    func loadProfile(uid: Int) async throws -> UserProfileRecord {
        let request = makeRequest(
            path: "/api/account/getInfo/\(uid)",
            queryItems: [
                URLQueryItem(name: "readme", value: "1")
            ],
            refererUID: uid
        )
        let response = try await decode(ProfileResponse.self, from: request)
        guard response.success, let detail = response.detail else { throw UserContentClientError.unsuccessfulResponse }
        return UserProfileRecord(
            uid: detail.memberID,
            name: detail.memberName,
            rank: detail.rank ?? 0,
            coin: detail.coin ?? 0,
            stardust: detail.stardust ?? 0,
            bio: detail.bio ?? "",
            readme: detail.readme ?? "",
            createdAt: detail.createdAt.flatMap(Self.parseDate),
            postCount: detail.postCount ?? 0,
            commentCount: detail.commentCount ?? 0,
            follows: detail.follows ?? 0,
            fans: detail.fans ?? 0,
            collectionCount: detail.collectionCount,
            roleNames: (detail.roles ?? []).compactMap(\.displayText).filter { !$0.isEmpty }
        )
    }

    /// 今日进度只对当前登录用户有效，两个接口与网页进度页一致
    func loadTodayProgress(uid: Int) async throws -> UserTodayProgressRecord {
        async let progressResponse = decode(
            TodayProgressResponse.self,
            from: makeRequest(path: "/api/progress/today", queryItems: [], refererUID: uid)
        )
        async let attendanceResponse = decode(
            AttendanceBoardResponse.self,
            from: makeRequest(
                path: "/api/attendance/board",
                queryItems: [URLQueryItem(name: "page", value: "1")],
                refererUID: uid
            )
        )
        let progress = try await progressResponse
        guard progress.success else { throw UserContentClientError.unsuccessfulResponse }
        let attendance = try await attendanceResponse
        return UserTodayProgressRecord(
            postBonusCount: progress.postBonusCount,
            maxPostBonusCount: progress.maxPostBonusCount,
            commentBonusCount: progress.commentBonusCount,
            maxCommentBonusCount: progress.maxCommentBonusCount,
            freeLikeUsed: progress.freeLikeUsed,
            maxFreeLike: progress.maxFreeLike,
            checkInGain: attendance.record?.gain
        )
    }

    private static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    private func makeRequest(path: String, queryItems: [URLQueryItem], refererUID: Int) -> URLRequest {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = path
        components?.queryItems = queryItems
        let url = components?.url ?? baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        let referer = baseURL
            .appendingPathComponent("space")
            .appendingPathComponent("\(refererUID)")
        WebRequestFingerprint.applyJSONHeaders(to: &request, referer: referer)
        return request
    }

    private func decode<Response: Decodable>(_ type: Response.Type, from request: URLRequest) async throws -> Response {
        let (data, urlResponse) = try await session.data(for: request)
        if let httpResponse = urlResponse as? HTTPURLResponse,
           (200..<300).contains(httpResponse.statusCode) == false {
            throw UserContentClientError.httpStatus(httpResponse.statusCode)
        }
        return try decoder.decode(Response.self, from: data)
    }
}

enum UserContentClientError: LocalizedError {
    case httpStatus(Int)
    case unsuccessfulResponse

    var errorDescription: String? {
        switch self {
        case .httpStatus(let status):
            return "请求失败：HTTP \(status)"
        case .unsuccessfulResponse:
            return "接口返回失败"
        }
    }
}

private struct CollectionResponse: Decodable {
    let success: Bool
    let collections: [CollectionItem]
}

private struct CollectionItem: Decodable {
    let title: String
    let postID: Int
    let rank: Int

    private enum CodingKeys: String, CodingKey {
        case title
        case postID = "post_id"
        case rank
    }
}

private struct CommentResponse: Decodable {
    let success: Bool
    let comments: [CommentItem]
}

private struct CommentItem: Decodable {
    let postID: Int
    let title: String
    let rank: Int
    let floorID: Int
    let text: String

    private enum CodingKeys: String, CodingKey {
        case postID = "post_id"
        case title
        case rank
        case floorID = "floor_id"
        case text
    }
}

private struct DiscussionResponse: Decodable {
    let success: Bool
    let discussions: [DiscussionItem]
}

private struct DiscussionItem: Decodable {
    let rank: Int
    let title: String
    let postID: Int

    private enum CodingKeys: String, CodingKey {
        case rank
        case title
        case postID = "post_id"
    }
}

private struct ProfileResponse: Decodable {
    let success: Bool
    let detail: ProfileDetail?
}

private struct ProfileDetail: Decodable {
    let memberID: Int
    let memberName: String
    let rank: Int?
    let coin: Int?
    let stardust: Int?
    let bio: String?
    let readme: String?
    let createdAt: String?
    let postCount: Int?
    let commentCount: Int?
    let follows: Int?
    let fans: Int?
    let collectionCount: Int?
    let roles: [ProfileRole]?

    private enum CodingKeys: String, CodingKey {
        case memberID = "member_id"
        case memberName = "member_name"
        case rank
        case coin
        case stardust
        case bio
        case readme
        case createdAt = "created_at"
        case postCount = "nPost"
        case commentCount = "nComment"
        case follows
        case fans
        case collectionCount
        case roles
    }
}

private struct ProfileRole: Decodable {
    let displayText: String?

    private enum CodingKeys: String, CodingKey {
        case displayText = "display_text"
    }
}

private struct TodayProgressResponse: Decodable {
    let success: Bool
    let postBonusCount: Int
    let maxPostBonusCount: Int
    let commentBonusCount: Int
    let maxCommentBonusCount: Int
    let freeLikeUsed: Int
    let maxFreeLike: Int
}

private struct AttendanceBoardResponse: Decodable {
    let record: AttendanceRecord?
}

private struct AttendanceRecord: Decodable {
    let gain: Int
}

private struct StardustResponse: Decodable {
    let success: Bool
    let records: [UserStardustRecord]?
    let hasMore: Bool?
    let cursor: Int?

    enum CodingKeys: String, CodingKey {
        case success, records, cursor
        case hasMore = "exist_more"
    }
}
