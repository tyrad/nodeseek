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
    let authorBadgeTexts: [String]
    let avatarURL: URL?
    let authorProfileURL: URL?
    let metadataText: String?
    let contentHTML: String
    let signatureHTML: String?
    /// 当前用户是楼主，主楼显示“编辑”。
    let isOwnPost: Bool
    private(set) var likeCount: Int?
    private(set) var isLikeClicked: Bool
    private(set) var chickenLegCount: Int?
    private(set) var isChickenLegClicked: Bool
    private(set) var opposeCount: Int?
    private(set) var isOpposeClicked: Bool
    private(set) var favoriteCount: Int?
    private(set) var isFavoriteCollected: Bool
    private(set) var isFavoriteSubmitting: Bool

    nonisolated init(
        postID: String,
        title: String,
        authorName: String,
        authorBadgeTexts: [String] = [],
        avatarURL: URL?,
        authorProfileURL: URL? = nil,
        metadataText: String?,
        contentHTML: String = "",
        signatureHTML: String? = nil,
        requiredReadingLevel: Int? = nil,
        likeCount: Int? = nil,
        isLikeClicked: Bool = false,
        chickenLegCount: Int? = nil,
        isChickenLegClicked: Bool = false,
        opposeCount: Int? = nil,
        isOpposeClicked: Bool = false,
        favoriteCount: Int? = nil,
        isFavoriteCollected: Bool = false,
        isFavoriteSubmitting: Bool = false,
        isOwnPost: Bool = false
    ) {
        self.isOwnPost = isOwnPost
        self.postID = postID
        self.title = title
        self.requiredReadingLevel = requiredReadingLevel
        self.authorName = authorName
        self.authorBadgeTexts = authorBadgeTexts
        self.avatarURL = avatarURL
        self.authorProfileURL = authorProfileURL
        self.metadataText = metadataText
        self.contentHTML = contentHTML
        self.signatureHTML = signatureHTML
        self.likeCount = likeCount
        self.isLikeClicked = isLikeClicked
        self.chickenLegCount = chickenLegCount
        self.isChickenLegClicked = isChickenLegClicked
        self.opposeCount = opposeCount
        self.isOpposeClicked = isOpposeClicked
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
            authorBadgeTexts: detail.authorBadgeTexts,
            avatarURL: detail.avatarURL,
            authorProfileURL: detail.authorProfileURL,
            metadataText: detail.metadataText,
            contentHTML: detail.contentHTML,
            signatureHTML: detail.signatureHTML,
            requiredReadingLevel: detail.requiredReadingLevel,
            likeCount: detail.likeCount,
            isLikeClicked: detail.isLikeClicked,
            chickenLegCount: detail.chickenLegCount,
            isChickenLegClicked: detail.isChickenLegClicked,
            opposeCount: detail.opposeCount,
            isOpposeClicked: detail.isOpposeClicked,
            favoriteCount: detail.favoriteCount,
            isFavoriteCollected: detail.isFavoriteCollected,
            isFavoriteSubmitting: false,
            isOwnPost: detail.isOwnPost
        )
    }

    func updatingFavoriteSubmitting(_ isSubmitting: Bool) -> PostDetailHeaderContent {
        var updated = self
        updated.isFavoriteSubmitting = isSubmitting
        return updated
    }

    func updatingFavoriteReaction(count: Int?, isCollected: Bool) -> PostDetailHeaderContent {
        var updated = self
        updated.favoriteCount = count
        updated.isFavoriteCollected = isCollected
        return updated
    }

    func updatingLikeReaction(count: Int?, isClicked: Bool) -> PostDetailHeaderContent {
        var updated = self
        updated.likeCount = count
        updated.isLikeClicked = isClicked
        return updated
    }

    func updatingChickenLegReaction(count: Int?, isClicked: Bool) -> PostDetailHeaderContent {
        var updated = self
        updated.chickenLegCount = count
        updated.isChickenLegClicked = isClicked
        return updated
    }

    func updatingOpposeReaction(count: Int?, isClicked: Bool) -> PostDetailHeaderContent {
        var updated = self
        updated.opposeCount = count
        updated.isOpposeClicked = isClicked
        return updated
    }
}
