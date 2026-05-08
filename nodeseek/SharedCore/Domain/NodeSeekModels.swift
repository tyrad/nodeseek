//
//  NodeSeekModels.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation

nonisolated struct AccountNotification: Equatable, Sendable {
    let url: URL
    let iconColorCSS: String?
}

nonisolated struct AccountResponse: Equatable, Sendable {
    let displayName: String
    let isLoggedIn: Bool
    let avatarURL: URL?
    let profileURL: URL?
    let stats: [String]
    let notification: AccountNotification?

    init(
        displayName: String,
        isLoggedIn: Bool,
        avatarURL: URL? = nil,
        profileURL: URL? = nil,
        stats: [String] = [],
        notification: AccountNotification? = nil
    ) {
        self.displayName = displayName
        self.isLoggedIn = isLoggedIn
        self.avatarURL = avatarURL
        self.profileURL = profileURL
        self.stats = stats
        self.notification = notification
    }
}

nonisolated struct PostSummary: Equatable, Sendable {
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

nonisolated struct PostDetailPageItem: Equatable, Sendable {
    let page: Int
    let url: URL?
    let isCurrent: Bool
}

nonisolated struct PostDetailPagination: Equatable, Sendable {
    let currentPage: Int
    let items: [PostDetailPageItem]
    let previousPage: Int?
    let nextPage: Int?

    var hasMultiplePages: Bool {
        items.count > 1 || previousPage != nil || nextPage != nil
    }
}

nonisolated struct PostDetail: Equatable, Sendable {
    let id: String
    let title: String
    let requiredReadingLevel: Int?
    let authorName: String
    let avatarURL: URL?
    let authorProfileURL: URL?
    let metadataText: String?
    let contentHTML: String
    let likeCount: Int?
    let isLikeClicked: Bool
    let chickenLegCount: Int?
    let isChickenLegClicked: Bool
    let opposeCount: Int?
    let isOpposeClicked: Bool
    let favoriteCount: Int?
    let isFavoriteCollected: Bool
    let isRestricted: Bool
    let comments: [Comment]
    let page: Int
    let pagination: PostDetailPagination?
    let isLastPage: Bool

    init(
        id: String,
        title: String,
        requiredReadingLevel: Int? = nil,
        authorName: String,
        avatarURL: URL?,
        authorProfileURL: URL? = nil,
        metadataText: String?,
        contentHTML: String,
        likeCount: Int? = nil,
        isLikeClicked: Bool = false,
        chickenLegCount: Int? = nil,
        isChickenLegClicked: Bool = false,
        opposeCount: Int? = nil,
        isOpposeClicked: Bool = false,
        favoriteCount: Int? = nil,
        isFavoriteCollected: Bool = false,
        isRestricted: Bool = false,
        comments: [Comment],
        page: Int = 1,
        pagination: PostDetailPagination? = nil,
        isLastPage: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.requiredReadingLevel = requiredReadingLevel
        self.authorName = authorName
        self.avatarURL = avatarURL
        self.authorProfileURL = authorProfileURL
        self.metadataText = metadataText
        self.contentHTML = contentHTML
        self.likeCount = likeCount
        self.isLikeClicked = isLikeClicked
        self.chickenLegCount = chickenLegCount
        self.isChickenLegClicked = isChickenLegClicked
        self.opposeCount = opposeCount
        self.isOpposeClicked = isOpposeClicked
        self.favoriteCount = favoriteCount
        self.isFavoriteCollected = isFavoriteCollected
        self.isRestricted = isRestricted
        self.comments = comments
        self.page = max(1, page)
        self.pagination = pagination
        self.isLastPage = isLastPage ?? (pagination?.nextPage == nil)
    }

    func updatingFavoriteState(count: Int?, isCollected: Bool) -> PostDetail {
        PostDetail(
            id: id,
            title: title,
            requiredReadingLevel: requiredReadingLevel,
            authorName: authorName,
            avatarURL: avatarURL,
            authorProfileURL: authorProfileURL,
            metadataText: metadataText,
            contentHTML: contentHTML,
            likeCount: likeCount,
            isLikeClicked: isLikeClicked,
            chickenLegCount: chickenLegCount,
            isChickenLegClicked: isChickenLegClicked,
            opposeCount: opposeCount,
            isOpposeClicked: isOpposeClicked,
            favoriteCount: count,
            isFavoriteCollected: isCollected,
            isRestricted: isRestricted,
            comments: comments,
            page: page,
            pagination: pagination,
            isLastPage: isLastPage
        )
    }

    func updatingPostLikeState(count: Int?, isClicked: Bool) -> PostDetail {
        PostDetail(
            id: id,
            title: title,
            requiredReadingLevel: requiredReadingLevel,
            authorName: authorName,
            avatarURL: avatarURL,
            authorProfileURL: authorProfileURL,
            metadataText: metadataText,
            contentHTML: contentHTML,
            likeCount: count,
            isLikeClicked: isClicked,
            chickenLegCount: chickenLegCount,
            isChickenLegClicked: isChickenLegClicked,
            opposeCount: opposeCount,
            isOpposeClicked: isOpposeClicked,
            favoriteCount: favoriteCount,
            isFavoriteCollected: isFavoriteCollected,
            isRestricted: isRestricted,
            comments: comments,
            page: page,
            pagination: pagination,
            isLastPage: isLastPage
        )
    }

    func updatingCommentLikeState(commentID: String, count: Int?, isClicked: Bool) -> PostDetail {
        let nextComments = comments.map { comment in
            comment.id == commentID
                ? comment.updatingLikeReaction(count: count, isClicked: isClicked)
                : comment
        }

        return PostDetail(
            id: id,
            title: title,
            requiredReadingLevel: requiredReadingLevel,
            authorName: authorName,
            avatarURL: avatarURL,
            authorProfileURL: authorProfileURL,
            metadataText: metadataText,
            contentHTML: contentHTML,
            likeCount: likeCount,
            isLikeClicked: isLikeClicked,
            chickenLegCount: chickenLegCount,
            isChickenLegClicked: isChickenLegClicked,
            opposeCount: opposeCount,
            isOpposeClicked: isOpposeClicked,
            favoriteCount: favoriteCount,
            isFavoriteCollected: isFavoriteCollected,
            isRestricted: isRestricted,
            comments: nextComments,
            page: page,
            pagination: pagination,
            isLastPage: isLastPage
        )
    }

    func updatingPostChickenLegState(count: Int?, isClicked: Bool) -> PostDetail {
        PostDetail(
            id: id,
            title: title,
            requiredReadingLevel: requiredReadingLevel,
            authorName: authorName,
            avatarURL: avatarURL,
            authorProfileURL: authorProfileURL,
            metadataText: metadataText,
            contentHTML: contentHTML,
            likeCount: likeCount,
            isLikeClicked: isLikeClicked,
            chickenLegCount: count,
            isChickenLegClicked: isClicked,
            opposeCount: opposeCount,
            isOpposeClicked: isOpposeClicked,
            favoriteCount: favoriteCount,
            isFavoriteCollected: isFavoriteCollected,
            isRestricted: isRestricted,
            comments: comments,
            page: page,
            pagination: pagination,
            isLastPage: isLastPage
        )
    }

    func updatingCommentChickenLegState(commentID: String, count: Int?, isClicked: Bool) -> PostDetail {
        let nextComments = comments.map { comment in
            comment.id == commentID
                ? comment.updatingChickenLegReaction(count: count, isClicked: isClicked)
                : comment
        }

        return PostDetail(
            id: id,
            title: title,
            requiredReadingLevel: requiredReadingLevel,
            authorName: authorName,
            avatarURL: avatarURL,
            authorProfileURL: authorProfileURL,
            metadataText: metadataText,
            contentHTML: contentHTML,
            likeCount: likeCount,
            isLikeClicked: isLikeClicked,
            chickenLegCount: chickenLegCount,
            isChickenLegClicked: isChickenLegClicked,
            opposeCount: opposeCount,
            isOpposeClicked: isOpposeClicked,
            favoriteCount: favoriteCount,
            isFavoriteCollected: isFavoriteCollected,
            isRestricted: isRestricted,
            comments: nextComments,
            page: page,
            pagination: pagination,
            isLastPage: isLastPage
        )
    }

    func updatingPostOpposeState(count: Int?, isClicked: Bool) -> PostDetail {
        PostDetail(
            id: id,
            title: title,
            requiredReadingLevel: requiredReadingLevel,
            authorName: authorName,
            avatarURL: avatarURL,
            authorProfileURL: authorProfileURL,
            metadataText: metadataText,
            contentHTML: contentHTML,
            likeCount: likeCount,
            isLikeClicked: isLikeClicked,
            chickenLegCount: chickenLegCount,
            isChickenLegClicked: isChickenLegClicked,
            opposeCount: count,
            isOpposeClicked: isClicked,
            favoriteCount: favoriteCount,
            isFavoriteCollected: isFavoriteCollected,
            isRestricted: isRestricted,
            comments: comments,
            page: page,
            pagination: pagination,
            isLastPage: isLastPage
        )
    }

    func updatingCommentOpposeState(commentID: String, count: Int?, isClicked: Bool) -> PostDetail {
        let nextComments = comments.map { comment in
            comment.id == commentID
                ? comment.updatingOpposeReaction(count: count, isClicked: isClicked)
                : comment
        }

        return PostDetail(
            id: id,
            title: title,
            requiredReadingLevel: requiredReadingLevel,
            authorName: authorName,
            avatarURL: avatarURL,
            authorProfileURL: authorProfileURL,
            metadataText: metadataText,
            contentHTML: contentHTML,
            likeCount: likeCount,
            isLikeClicked: isLikeClicked,
            chickenLegCount: chickenLegCount,
            isChickenLegClicked: isChickenLegClicked,
            opposeCount: opposeCount,
            isOpposeClicked: isOpposeClicked,
            favoriteCount: favoriteCount,
            isFavoriteCollected: isFavoriteCollected,
            isRestricted: isRestricted,
            comments: nextComments,
            page: page,
            pagination: pagination,
            isLastPage: isLastPage
        )
    }
}

nonisolated struct Comment: Equatable, Sendable {
    let id: String
    let anchorID: String?
    let authorName: String
    let isPoster: Bool
    let avatarURL: URL?
    let authorProfileURL: URL?
    let authorBadgeTexts: [String]
    let floorText: String?
    let createdAtText: String?
    let createdAtTitleText: String?
    let contentHTML: String
    let isHot: Bool
    let likeCount: Int?
    let isLikeClicked: Bool
    let chickenLegCount: Int?
    let isChickenLegClicked: Bool
    let opposeCount: Int?
    let isOpposeClicked: Bool

    init(
        id: String,
        anchorID: String? = nil,
        authorName: String,
        isPoster: Bool = false,
        avatarURL: URL?,
        authorProfileURL: URL? = nil,
        authorBadgeTexts: [String] = [],
        floorText: String?,
        createdAtText: String?,
        createdAtTitleText: String? = nil,
        contentHTML: String,
        isHot: Bool = false,
        likeCount: Int? = nil,
        isLikeClicked: Bool = false,
        chickenLegCount: Int? = nil,
        isChickenLegClicked: Bool = false,
        opposeCount: Int? = nil,
        isOpposeClicked: Bool = false
    ) {
        self.id = id
        self.anchorID = anchorID
        self.authorName = authorName
        self.isPoster = isPoster
        self.avatarURL = avatarURL
        self.authorProfileURL = authorProfileURL
        self.authorBadgeTexts = authorBadgeTexts
        self.floorText = floorText
        self.createdAtText = createdAtText
        self.createdAtTitleText = createdAtTitleText
        self.contentHTML = contentHTML
        self.isHot = isHot
        self.likeCount = likeCount
        self.isLikeClicked = isLikeClicked
        self.chickenLegCount = chickenLegCount
        self.isChickenLegClicked = isChickenLegClicked
        self.opposeCount = opposeCount
        self.isOpposeClicked = isOpposeClicked
    }

    func updatingLikeReaction(count: Int?, isClicked: Bool) -> Comment {
        Comment(
            id: id,
            anchorID: anchorID,
            authorName: authorName,
            isPoster: isPoster,
            avatarURL: avatarURL,
            authorProfileURL: authorProfileURL,
            authorBadgeTexts: authorBadgeTexts,
            floorText: floorText,
            createdAtText: createdAtText,
            createdAtTitleText: createdAtTitleText,
            contentHTML: contentHTML,
            isHot: isHot,
            likeCount: count,
            isLikeClicked: isClicked,
            chickenLegCount: chickenLegCount,
            isChickenLegClicked: isChickenLegClicked,
            opposeCount: opposeCount,
            isOpposeClicked: isOpposeClicked
        )
    }

    func updatingChickenLegReaction(count: Int?, isClicked: Bool) -> Comment {
        Comment(
            id: id,
            anchorID: anchorID,
            authorName: authorName,
            isPoster: isPoster,
            avatarURL: avatarURL,
            authorProfileURL: authorProfileURL,
            authorBadgeTexts: authorBadgeTexts,
            floorText: floorText,
            createdAtText: createdAtText,
            createdAtTitleText: createdAtTitleText,
            contentHTML: contentHTML,
            isHot: isHot,
            likeCount: likeCount,
            isLikeClicked: isLikeClicked,
            chickenLegCount: count,
            isChickenLegClicked: isClicked,
            opposeCount: opposeCount,
            isOpposeClicked: isOpposeClicked
        )
    }

    func updatingOpposeReaction(count: Int?, isClicked: Bool) -> Comment {
        Comment(
            id: id,
            anchorID: anchorID,
            authorName: authorName,
            isPoster: isPoster,
            avatarURL: avatarURL,
            authorProfileURL: authorProfileURL,
            authorBadgeTexts: authorBadgeTexts,
            floorText: floorText,
            createdAtText: createdAtText,
            createdAtTitleText: createdAtTitleText,
            contentHTML: contentHTML,
            isHot: isHot,
            likeCount: likeCount,
            isLikeClicked: isLikeClicked,
            chickenLegCount: chickenLegCount,
            isChickenLegClicked: isChickenLegClicked,
            opposeCount: count,
            isOpposeClicked: isClicked
        )
    }
}

nonisolated struct CheckInState: Equatable, Sendable {
    let isCheckedIn: Bool
    let message: String
    let actionURL: URL?
    let hiddenFields: [String: String]
}

nonisolated struct UserSummary: Equatable, Sendable {
    let displayName: String
    let isLoggedIn: Bool
}

nonisolated enum AuthorDisplayPolicy {
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
