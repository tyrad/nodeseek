//
//  HotList.swift
//  nodeseek
//

import Foundation

/// 热榜类型。数据来自第三方热榜插件的公开 JSON，不是 NodeSeek 官方接口。
nonisolated enum HotListKind: String, CaseIterable, Codable, Sendable {
    case realtime
    case daily
    case weekly

    var defaultURL: URL {
        switch self {
        case .realtime: return URL(string: "https://api.bimg.eu.org/hot.json")!
        case .daily: return URL(string: "https://api.bimg.eu.org/daily.json")!
        case .weekly: return URL(string: "https://api.bimg.eu.org/weekly.json")!
        }
    }

    /// 与服务端 Cache-Control max-age 一致，有效期内不重复请求。
    var cacheLifetime: TimeInterval {
        switch self {
        case .realtime: return 60
        case .daily: return 300
        case .weekly: return 600
        }
    }
}

nonisolated struct HotListEntry: Equatable, Sendable {
    let postID: Int
    let title: String
    let authorName: String
    let authorID: Int?
    let postedAt: Date?
    let viewCount: Int
    let commentCount: Int
    let categorySlug: String?
    let score: Double

    var postURL: URL {
        URL(string: "/post-\(postID)-1", relativeTo: NodeSeekSite.baseURL)!.absoluteURL
    }

    var avatarURL: URL? {
        authorID.flatMap { URL(string: "/avatar/\($0).png", relativeTo: NodeSeekSite.baseURL)?.absoluteURL }
    }

    var authorProfileURL: URL? {
        authorID.flatMap { URL(string: "/space/\($0)", relativeTo: NodeSeekSite.baseURL)?.absoluteURL }
    }

    var categoryTitle: String? {
        categorySlug.flatMap { DiscussionCategory(rawValue: $0)?.title }
    }

    var postSummary: PostSummary {
        PostSummary(
            id: String(postID),
            title: title,
            url: postURL,
            authorName: authorName,
            nodeName: categoryTitle,
            replyCount: commentCount,
            viewCount: viewCount,
            lastActivityText: nil,
            avatarURL: avatarURL,
            authorProfileURL: authorProfileURL
        )
    }
}

nonisolated struct HotListResponse: Equatable, Sendable {
    let updatedAt: Date?
    let entries: [HotListEntry]
}

nonisolated enum HotListDecodingError: Error, Equatable {
    case invalidFormat
}

nonisolated enum HotListDecoder {
    /// 容错解码：单条缺少帖子 ID 或标题时跳过，可选字段缺失给默认值；顶层没有 posts 数组视为格式错误。
    static func decode(_ data: Data) throws -> HotListResponse {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let posts = root["posts"] as? [Any]
        else {
            throw HotListDecodingError.invalidFormat
        }

        let entries = posts.compactMap { item -> HotListEntry? in
            guard let item = item as? [String: Any], let post = item["post"] as? [String: Any] else { return nil }
            guard let postID = int(post["id"]), postID > 0 else { return nil }
            guard let title = (post["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
                return nil
            }
            return HotListEntry(
                postID: postID,
                title: title,
                authorName: (post["author"] as? String) ?? "",
                authorID: int(post["author_id"]),
                postedAt: double(post["post_timestamp"]).map { Date(timeIntervalSince1970: $0) },
                viewCount: int(post["views"]) ?? 0,
                commentCount: int(post["comments"]) ?? 0,
                categorySlug: post["category"] as? String,
                score: double(item["score"]) ?? 0
            )
        }

        return HotListResponse(
            updatedAt: double(root["updated_at"]).map { Date(timeIntervalSince1970: $0) },
            entries: entries
        )
    }

    private static func int(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber: return number.intValue
        case let string as String: return Int(string)
        default: return nil
        }
    }

    private static func double(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: return number.doubleValue
        case let string as String: return Double(string)
        default: return nil
        }
    }
}
