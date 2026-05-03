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

struct PostDetailSubmitReplyResponse: Equatable {
    let message: String?
}

struct PostDetailHeaderContent: Equatable {
    let postID: String
    let title: String
    let requiredReadingLevel: Int?
    let authorName: String
    let avatarURL: URL?
    let authorProfileURL: URL?
    let metadataText: String?
    let contentHTML: String
    let likeCount: Int?
    let chickenLegCount: Int?
    let opposeCount: Int?
    let favoriteCount: Int?
    let isFavoriteCollected: Bool
    let isFavoriteSubmitting: Bool

    nonisolated init(
        postID: String,
        title: String,
        authorName: String,
        avatarURL: URL?,
        authorProfileURL: URL? = nil,
        metadataText: String?,
        contentHTML: String = "",
        requiredReadingLevel: Int? = nil,
        likeCount: Int? = nil,
        chickenLegCount: Int? = nil,
        opposeCount: Int? = nil,
        favoriteCount: Int? = nil,
        isFavoriteCollected: Bool = false,
        isFavoriteSubmitting: Bool = false
    ) {
        self.postID = postID
        self.title = title
        self.requiredReadingLevel = requiredReadingLevel
        self.authorName = authorName
        self.avatarURL = avatarURL
        self.authorProfileURL = authorProfileURL
        self.metadataText = metadataText
        self.contentHTML = contentHTML
        self.likeCount = likeCount
        self.chickenLegCount = chickenLegCount
        self.opposeCount = opposeCount
        self.favoriteCount = favoriteCount
        self.isFavoriteCollected = isFavoriteCollected
        self.isFavoriteSubmitting = isFavoriteSubmitting
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
            authorProfileURL: nil,
            metadataText: metadata.isEmpty ? nil : metadata,
            requiredReadingLevel: nil
        )
    }

    nonisolated init(detail: PostDetail) {
        self.init(
            postID: detail.id,
            title: detail.title,
            authorName: detail.authorName,
            avatarURL: detail.avatarURL,
            authorProfileURL: detail.authorProfileURL,
            metadataText: detail.metadataText,
            contentHTML: detail.contentHTML,
            requiredReadingLevel: detail.requiredReadingLevel,
            likeCount: detail.likeCount,
            chickenLegCount: detail.chickenLegCount,
            opposeCount: detail.opposeCount,
            favoriteCount: detail.favoriteCount,
            isFavoriteCollected: detail.isFavoriteCollected,
            isFavoriteSubmitting: false
        )
    }

    func updatingFavoriteSubmitting(_ isSubmitting: Bool) -> PostDetailHeaderContent {
        PostDetailHeaderContent(
            postID: postID,
            title: title,
            authorName: authorName,
            avatarURL: avatarURL,
            authorProfileURL: authorProfileURL,
            metadataText: metadataText,
            contentHTML: contentHTML,
            requiredReadingLevel: requiredReadingLevel,
            likeCount: likeCount,
            chickenLegCount: chickenLegCount,
            opposeCount: opposeCount,
            favoriteCount: favoriteCount,
            isFavoriteCollected: isFavoriteCollected,
            isFavoriteSubmitting: isSubmitting
        )
    }

    func updatingFavoriteReaction(count: Int?, isCollected: Bool) -> PostDetailHeaderContent {
        PostDetailHeaderContent(
            postID: postID,
            title: title,
            authorName: authorName,
            avatarURL: avatarURL,
            authorProfileURL: authorProfileURL,
            metadataText: metadataText,
            contentHTML: contentHTML,
            requiredReadingLevel: requiredReadingLevel,
            likeCount: likeCount,
            chickenLegCount: chickenLegCount,
            opposeCount: opposeCount,
            favoriteCount: count,
            isFavoriteCollected: isCollected,
            isFavoriteSubmitting: isFavoriteSubmitting
        )
    }
}
