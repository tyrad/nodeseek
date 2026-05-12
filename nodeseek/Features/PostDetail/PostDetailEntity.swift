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
    let signatureHTML: String?
    let likeCount: Int?
    let isLikeClicked: Bool
    let chickenLegCount: Int?
    let isChickenLegClicked: Bool
    let opposeCount: Int?
    let isOpposeClicked: Bool
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
            signatureHTML: signatureHTML,
            requiredReadingLevel: requiredReadingLevel,
            likeCount: likeCount,
            isLikeClicked: isLikeClicked,
            chickenLegCount: chickenLegCount,
            isChickenLegClicked: isChickenLegClicked,
            opposeCount: opposeCount,
            isOpposeClicked: isOpposeClicked,
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
            signatureHTML: signatureHTML,
            requiredReadingLevel: requiredReadingLevel,
            likeCount: likeCount,
            isLikeClicked: isLikeClicked,
            chickenLegCount: chickenLegCount,
            isChickenLegClicked: isChickenLegClicked,
            opposeCount: opposeCount,
            isOpposeClicked: isOpposeClicked,
            favoriteCount: count,
            isFavoriteCollected: isCollected,
            isFavoriteSubmitting: isFavoriteSubmitting
        )
    }

    func updatingLikeReaction(count: Int?, isClicked: Bool) -> PostDetailHeaderContent {
        PostDetailHeaderContent(
            postID: postID,
            title: title,
            authorName: authorName,
            avatarURL: avatarURL,
            authorProfileURL: authorProfileURL,
            metadataText: metadataText,
            contentHTML: contentHTML,
            signatureHTML: signatureHTML,
            requiredReadingLevel: requiredReadingLevel,
            likeCount: count,
            isLikeClicked: isClicked,
            chickenLegCount: chickenLegCount,
            isChickenLegClicked: isChickenLegClicked,
            opposeCount: opposeCount,
            isOpposeClicked: isOpposeClicked,
            favoriteCount: favoriteCount,
            isFavoriteCollected: isFavoriteCollected,
            isFavoriteSubmitting: isFavoriteSubmitting
        )
    }

    func updatingChickenLegReaction(count: Int?, isClicked: Bool) -> PostDetailHeaderContent {
        PostDetailHeaderContent(
            postID: postID,
            title: title,
            authorName: authorName,
            avatarURL: avatarURL,
            authorProfileURL: authorProfileURL,
            metadataText: metadataText,
            contentHTML: contentHTML,
            signatureHTML: signatureHTML,
            requiredReadingLevel: requiredReadingLevel,
            likeCount: likeCount,
            isLikeClicked: isLikeClicked,
            chickenLegCount: count,
            isChickenLegClicked: isClicked,
            opposeCount: opposeCount,
            isOpposeClicked: isOpposeClicked,
            favoriteCount: favoriteCount,
            isFavoriteCollected: isFavoriteCollected,
            isFavoriteSubmitting: isFavoriteSubmitting
        )
    }

    func updatingOpposeReaction(count: Int?, isClicked: Bool) -> PostDetailHeaderContent {
        PostDetailHeaderContent(
            postID: postID,
            title: title,
            authorName: authorName,
            avatarURL: avatarURL,
            authorProfileURL: authorProfileURL,
            metadataText: metadataText,
            contentHTML: contentHTML,
            signatureHTML: signatureHTML,
            requiredReadingLevel: requiredReadingLevel,
            likeCount: likeCount,
            isLikeClicked: isLikeClicked,
            chickenLegCount: chickenLegCount,
            isChickenLegClicked: isChickenLegClicked,
            opposeCount: count,
            isOpposeClicked: isClicked,
            favoriteCount: favoriteCount,
            isFavoriteCollected: isFavoriteCollected,
            isFavoriteSubmitting: isFavoriteSubmitting
        )
    }
}
