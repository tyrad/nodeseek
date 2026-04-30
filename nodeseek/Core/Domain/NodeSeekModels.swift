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
    let viewCount: Int
    let lastActivityText: String?
    let isPinned: Bool
    let isLocked: Bool
    let avatarURL: URL?

    init(
        id: String,
        title: String,
        url: URL,
        authorName: String,
        nodeName: String?,
        replyCount: Int,
        viewCount: Int = 0,
        lastActivityText: String?,
        isPinned: Bool = false,
        isLocked: Bool = false,
        avatarURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.authorName = authorName
        self.nodeName = nodeName
        self.replyCount = replyCount
        self.viewCount = viewCount
        self.lastActivityText = lastActivityText
        self.isPinned = isPinned
        self.isLocked = isLocked
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
    let isLastPage: Bool

    init(
        id: String,
        title: String,
        authorName: String,
        avatarURL: URL?,
        metadataText: String?,
        contentHTML: String,
        comments: [Comment],
        replyForm: ReplyForm?,
        isLastPage: Bool = true
    ) {
        self.id = id
        self.title = title
        self.authorName = authorName
        self.avatarURL = avatarURL
        self.metadataText = metadataText
        self.contentHTML = contentHTML
        self.comments = comments
        self.replyForm = replyForm
        self.isLastPage = isLastPage
    }
}

struct Comment: Equatable, Sendable {
    let id: String
    let anchorID: String?
    let authorName: String
    let avatarURL: URL?
    let floorText: String?
    let createdAtText: String?
    let createdAtTitleText: String?
    let contentHTML: String

    init(
        id: String,
        anchorID: String? = nil,
        authorName: String,
        avatarURL: URL?,
        floorText: String?,
        createdAtText: String?,
        createdAtTitleText: String? = nil,
        contentHTML: String
    ) {
        self.id = id
        self.anchorID = anchorID
        self.authorName = authorName
        self.avatarURL = avatarURL
        self.floorText = floorText
        self.createdAtText = createdAtText
        self.createdAtTitleText = createdAtTitleText
        self.contentHTML = contentHTML
    }
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

enum AuthorDisplayPolicy {
    static func displayName(from rawName: String) -> String? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != "未知用户" else {
            return nil
        }

        return name
    }

    static func isDisplayable(_ rawName: String) -> Bool {
        displayName(from: rawName) != nil
    }
}
