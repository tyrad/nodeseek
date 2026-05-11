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
