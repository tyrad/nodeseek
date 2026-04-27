//
//  NodeSeekModels.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation

struct PostSummary: Equatable, Sendable {
    let id: String
    let title: String
    let url: URL
    let authorName: String
    let nodeName: String?
    let replyCount: Int
    let lastActivityText: String?
    let avatarURL: URL?

    init(
        id: String,
        title: String,
        url: URL,
        authorName: String,
        nodeName: String?,
        replyCount: Int,
        lastActivityText: String?,
        avatarURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.authorName = authorName
        self.nodeName = nodeName
        self.replyCount = replyCount
        self.lastActivityText = lastActivityText
        self.avatarURL = avatarURL
    }
}

struct PostDetail: Equatable, Sendable {
    let id: String
    let title: String
    let authorName: String
    let avatarURL: URL?
    let metadataText: String?
    let contentHTML: String
    let comments: [Comment]
    let replyForm: ReplyForm?
}

struct Comment: Equatable, Sendable {
    let id: String
    let authorName: String
    let avatarURL: URL?
    let floorText: String?
    let createdAtText: String?
    let contentHTML: String
}

struct ReplyForm: Equatable, Sendable {
    let actionURL: URL
    let method: String
    let textFieldName: String
    let hiddenFields: [String: String]
}

struct CheckInState: Equatable, Sendable {
    let isCheckedIn: Bool
    let message: String
    let actionURL: URL?
    let hiddenFields: [String: String]
}

struct UserSummary: Equatable, Sendable {
    let displayName: String
    let isLoggedIn: Bool
}
