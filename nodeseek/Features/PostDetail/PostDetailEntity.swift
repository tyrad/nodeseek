//
//  PostDetailEntity.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation

struct PostDetailRequest {
    let postID: String
    let page: Int
}

struct PostDetailResponse {
    let detail: PostDetail
}

struct PostDetailHeaderContent: Equatable {
    let postID: String
    let title: String
    let authorName: String
    let avatarURL: URL?
    let metadataText: String?
    let contentHTML: String

    nonisolated init(
        postID: String,
        title: String,
        authorName: String,
        avatarURL: URL?,
        metadataText: String?,
        contentHTML: String = ""
    ) {
        self.postID = postID
        self.title = title
        self.authorName = authorName
        self.avatarURL = avatarURL
        self.metadataText = metadataText
        self.contentHTML = contentHTML
    }

    nonisolated init(post: PostSummary) {
        let metadata = [
            post.nodeName,
            post.lastActivityText,
            post.replyCount > 0 ? "回复 \(post.replyCount)" : nil
        ].compactMap(\.self).joined(separator: " · ")

        self.init(
            postID: post.id,
            title: post.title,
            authorName: post.authorName,
            avatarURL: post.avatarURL,
            metadataText: metadata.isEmpty ? nil : metadata
        )
    }

    nonisolated init(detail: PostDetail) {
        self.init(
            postID: detail.id,
            title: detail.title,
            authorName: detail.authorName,
            avatarURL: detail.avatarURL,
            metadataText: detail.metadataText,
            contentHTML: detail.contentHTML
        )
    }
}
