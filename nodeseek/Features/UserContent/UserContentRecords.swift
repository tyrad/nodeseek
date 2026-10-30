//
//  UserContentRecords.swift
//  nodeseek
//
//  Created by Codex on 2026/5/11.
//

import Foundation

nonisolated struct UserDiscussionRecord: Equatable, Sendable {
    let rank: Int
    let title: String
    let postID: Int
}

nonisolated struct UserCommentRecord: Equatable, Sendable {
    let postID: Int
    let title: String
    let rank: Int
    let floorID: Int
    let text: String

    var commentPage: Int {
        max(1, (floorID + 9) / 10)
    }

    var anchorID: String {
        "\(floorID)"
    }
}

nonisolated struct UserCollectionRecord: Equatable, Sendable {
    let title: String
    let postID: Int
    let rank: Int
}

extension AccountResponse {
    nonisolated var nodeSeekUID: Int? {
        guard let profileURL else { return nil }
        return NodeSeekUserIDResolver.uid(from: profileURL)
    }
}

enum NodeSeekUserIDResolver {
    nonisolated static func uid(from url: URL) -> Int? {
        let components = url.pathComponents
        guard let spaceIndex = components.firstIndex(of: "space") else { return nil }
        let idIndex = components.index(after: spaceIndex)
        guard idIndex < components.endIndex else { return nil }
        return Int(components[idIndex])
    }
}

enum UserContentPostSummaryFactory {
    nonisolated static func postSummary(id: Int, title: String) -> PostSummary {
        let stringID = "\(id)"
        return PostSummary(
            id: stringID,
            title: title,
            url: NodeSeekSite.postURL(id: stringID, page: 1),
            authorName: "",
            nodeName: nil,
            replyCount: 0,
            lastActivityText: nil
        )
    }
}

nonisolated struct UserProfileRecord: Equatable, Sendable {
    let uid: Int
    let name: String
    let rank: Int
    let coin: Int
    let stardust: Int
    let bio: String
    let readme: String
    let createdAt: Date?
    let postCount: Int
    let commentCount: Int
    let follows: Int
    let fans: Int
    /// 只有看自己时接口才返回
    let collectionCount: Int?
    let roleNames: [String]

    var avatarURL: URL {
        NodeSeekNotificationURLBuilder.avatarURL(memberID: uid)
    }

    var profileURL: URL {
        NodeSeekSite.baseURL
            .appendingPathComponent("space")
            .appendingPathComponent("\(uid)")
    }

    /// 与网页一致：不足一天按一天算
    func joinedDays(now: Date = Date()) -> Int? {
        guard let createdAt else { return nil }
        let days = now.timeIntervalSince(createdAt) / 86_400
        return max(1, Int(days.rounded(.up)))
    }

    var levelProgress: UserLevelProgress {
        UserLevelProgress(rank: rank, coin: coin)
    }
}

nonisolated struct UserLevelProgress: Equatable, Sendable {
    /// 网页进度页只算到 Lv5 → Lv6，Lv6 视为满级
    static let maxRank = 6

    let rank: Int
    let coin: Int

    var isMaxRank: Bool {
        rank >= Self.maxRank
    }

    var nextRank: Int {
        rank + 1
    }

    var lowerBound: Int {
        Self.threshold(for: rank)
    }

    var upperBound: Int {
        Self.threshold(for: nextRank)
    }

    var remaining: Int {
        max(0, upperBound - coin)
    }

    var fraction: Double {
        guard !isMaxRank else { return 1 }
        let span = upperBound - lowerBound
        guard span > 0 else { return 0 }
        return min(1, max(0, Double(coin - lowerBound) / Double(span)))
    }

    static func threshold(for rank: Int) -> Int {
        rank * rank * 100
    }
}

nonisolated struct UserTodayProgressRecord: Equatable, Sendable {
    /// 每篇帖子奖励的鸡腿数，网页进度页按此换算
    static let postBonusCoin = 5
    /// 未签到时网页显示的上限
    static let uncheckedMaxGain = 20

    let postBonusCount: Int
    let maxPostBonusCount: Int
    let commentBonusCount: Int
    let maxCommentBonusCount: Int
    let freeLikeUsed: Int
    let maxFreeLike: Int
    /// 今日签到获得的鸡腿；nil 表示还没签到
    let checkInGain: Int?

    var postCoin: Int { postBonusCount * Self.postBonusCoin }
    var maxPostCoin: Int { maxPostBonusCount * Self.postBonusCoin }
}
