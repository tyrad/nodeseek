//
//  NodeSeekNotificationRecords.swift
//  nodeseek
//
//  Created by Codex on 2026/6/8.
//

import Foundation

nonisolated enum NodeSeekNotificationTab: Int, CaseIterable, Hashable, Sendable {
    case atMe
    case reply
    case message

    var title: String {
        switch self {
        case .atMe:
            return "@我"
        case .reply:
            return "回复主题"
        case .message:
            return "私信"
        }
    }

    var webURL: URL {
        switch self {
        case .atMe:
            return NodeSeekNotificationURLBuilder.webURL(fragment: "/atMe")
        case .reply:
            return NodeSeekNotificationURLBuilder.webURL(fragment: "/reply")
        case .message:
            return NodeSeekNotificationURLBuilder.webURL(fragment: "/message?mode=list")
        }
    }
}

nonisolated struct NodeSeekNotificationUnreadCount: Equatable, Sendable {
    var message: Int
    var atMe: Int
    var reply: Int
    var all: Int

    static let zero = NodeSeekNotificationUnreadCount(message: 0, atMe: 0, reply: 0, all: 0)

    func count(for tab: NodeSeekNotificationTab) -> Int {
        switch tab {
        case .atMe:
            return atMe
        case .reply:
            return reply
        case .message:
            return message
        }
    }

    mutating func setCount(_ count: Int, for tab: NodeSeekNotificationTab) {
        let normalized = max(0, count)
        switch tab {
        case .atMe:
            atMe = normalized
        case .reply:
            reply = normalized
        case .message:
            message = normalized
        }
        all = atMe + reply + message
    }

    mutating func decrement(for tab: NodeSeekNotificationTab, by amount: Int = 1) {
        setCount(count(for: tab) - max(0, amount), for: tab)
    }
}

nonisolated struct NodeSeekNotificationRecord: Decodable, Equatable, Sendable {
    let id: Int
    var viewed: Int
    let commentID: Int
    let floorID: Int
    let createdAt: Date
    let commenterID: Int
    let title: String
    let postID: Int
    let firstCommentID: Int
    let commenterName: String

    var isViewed: Bool {
        viewed != 0
    }

    var commentPage: Int {
        max(1, (floorID + 9) / 10)
    }

    var anchorID: String {
        "\(floorID)"
    }

    var avatarURL: URL {
        NodeSeekNotificationURLBuilder.avatarURL(memberID: commenterID)
    }

    var profileURL: URL {
        NodeSeekNotificationURLBuilder.profileURL(memberID: commenterID)
    }

    var postSummary: PostSummary {
        UserContentPostSummaryFactory.postSummary(id: postID, title: title)
    }

    mutating func markViewed() {
        viewed = 1
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case viewed
        case commentID = "comment_id"
        case floorID = "floor_id"
        case createdAt = "created_at"
        case commenterID = "commenter_id"
        case title
        case postID = "post_id"
        case firstCommentID = "first_comment_id"
        case commenterName = "commenter_name"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        viewed = try container.decode(Int.self, forKey: .viewed)
        commentID = try container.decode(Int.self, forKey: .commentID)
        floorID = try container.decode(Int.self, forKey: .floorID)
        let createdAtText = try container.decode(String.self, forKey: .createdAt)
        guard let parsedDate = NodeSeekNotificationDateParser.date(from: createdAtText) else {
            throw DecodingError.dataCorruptedError(
                forKey: .createdAt,
                in: container,
                debugDescription: "Invalid notification date: \(createdAtText)"
            )
        }
        createdAt = parsedDate
        commenterID = try container.decode(Int.self, forKey: .commenterID)
        title = try container.decode(String.self, forKey: .title)
        postID = try container.decode(Int.self, forKey: .postID)
        firstCommentID = try container.decode(Int.self, forKey: .firstCommentID)
        commenterName = try container.decode(String.self, forKey: .commenterName)
    }

    init(
        id: Int,
        viewed: Int,
        commentID: Int,
        floorID: Int,
        createdAt: Date,
        commenterID: Int,
        title: String,
        postID: Int,
        firstCommentID: Int,
        commenterName: String
    ) {
        self.id = id
        self.viewed = viewed
        self.commentID = commentID
        self.floorID = floorID
        self.createdAt = createdAt
        self.commenterID = commenterID
        self.title = title
        self.postID = postID
        self.firstCommentID = firstCommentID
        self.commenterName = commenterName
    }
}

nonisolated struct NodeSeekMessageConversationRecord: Decodable, Equatable, Sendable {
    let receiverID: Int
    let senderID: Int
    let maxID: Int
    let content: String
    let createdAt: Date
    var viewed: Int
    let senderName: String
    let receiverName: String

    var isViewed: Bool {
        viewed != 0
    }

    func participantID(currentUserID: Int?) -> Int {
        guard let currentUserID else { return senderID }
        return senderID == currentUserID ? receiverID : senderID
    }

    func participantName(currentUserID: Int?) -> String {
        guard let currentUserID else { return senderName }
        return senderID == currentUserID ? receiverName : senderName
    }

    func participantAvatarURL(currentUserID: Int?) -> URL {
        NodeSeekNotificationURLBuilder.avatarURL(memberID: participantID(currentUserID: currentUserID))
    }

    func participantProfileURL(currentUserID: Int?) -> URL {
        NodeSeekNotificationURLBuilder.profileURL(memberID: participantID(currentUserID: currentUserID))
    }

    func conversationWebURL(currentUserID: Int?) -> URL {
        NodeSeekNotificationURLBuilder.webURL(
            fragment: "/message?mode=talk&to=\(participantID(currentUserID: currentUserID))"
        )
    }

    mutating func markViewed() {
        viewed = 1
    }

    private enum CodingKeys: String, CodingKey {
        case receiverID = "receiver_id"
        case senderID = "sender_id"
        case maxID = "max_id"
        case content
        case createdAt = "created_at"
        case viewed
        case senderName = "sender_name"
        case receiverName = "receiver_name"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        receiverID = try container.decode(Int.self, forKey: .receiverID)
        senderID = try container.decode(Int.self, forKey: .senderID)
        maxID = try container.decode(Int.self, forKey: .maxID)
        content = try container.decode(String.self, forKey: .content)
        let createdAtText = try container.decode(String.self, forKey: .createdAt)
        guard let parsedDate = NodeSeekNotificationDateParser.date(from: createdAtText) else {
            throw DecodingError.dataCorruptedError(
                forKey: .createdAt,
                in: container,
                debugDescription: "Invalid message date: \(createdAtText)"
            )
        }
        createdAt = parsedDate
        viewed = try container.decode(Int.self, forKey: .viewed)
        senderName = try container.decode(String.self, forKey: .senderName)
        receiverName = try container.decode(String.self, forKey: .receiverName)
    }

    init(
        receiverID: Int,
        senderID: Int,
        maxID: Int,
        content: String,
        createdAt: Date,
        viewed: Int,
        senderName: String,
        receiverName: String
    ) {
        self.receiverID = receiverID
        self.senderID = senderID
        self.maxID = maxID
        self.content = content
        self.createdAt = createdAt
        self.viewed = viewed
        self.senderName = senderName
        self.receiverName = receiverName
    }
}

enum NodeSeekNotificationURLBuilder {
    nonisolated static func webURL(fragment: String) -> URL {
        var components = URLComponents(url: NodeSeekSite.baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/notification"
        components?.fragment = fragment
        return components?.url ?? NodeSeekSite.baseURL.appendingPathComponent("notification")
    }

    nonisolated static func avatarURL(memberID: Int) -> URL {
        NodeSeekSite.baseURL
            .appendingPathComponent("avatar")
            .appendingPathComponent("\(memberID).png")
    }

    nonisolated static func profileURL(memberID: Int) -> URL {
        NodeSeekSite.baseURL
            .appendingPathComponent("space")
            .appendingPathComponent("\(memberID)")
    }
}

enum NodeSeekNotificationDateParser {
    nonisolated static func date(from value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    nonisolated static func displayText(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy/M/d HH:mm:ss"
        return formatter.string(from: date)
    }
}
