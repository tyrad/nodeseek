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
    let requiredReadingLevel: Int?
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
        requiredReadingLevel: Int? = nil,
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
        self.requiredReadingLevel = requiredReadingLevel
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
    // 仅交易、拼车帖提供楼主 ID；阅读权限等级不能用于风险判断。
    let lowLevelWarningAuthorID: Int?
    /// 当前登录用户就是楼主，可以编辑主楼。
    let isOwnPost: Bool
    let authorName: String
    let authorBadgeTexts: [String]
    let avatarURL: URL?
    let authorProfileURL: URL?
    let metadataText: String?
    let contentHTML: String
    let signatureHTML: String?
    private(set) var likeCount: Int?
    private(set) var isLikeClicked: Bool
    private(set) var chickenLegCount: Int?
    private(set) var isChickenLegClicked: Bool
    private(set) var opposeCount: Int?
    private(set) var isOpposeClicked: Bool
    private(set) var favoriteCount: Int?
    private(set) var isFavoriteCollected: Bool
    let isRestricted: Bool
    private(set) var comments: [Comment]
    private(set) var page: Int
    private(set) var pagination: PostDetailPagination?
    private(set) var isLastPage: Bool

    init(
        id: String,
        title: String,
        requiredReadingLevel: Int? = nil,
        lowLevelWarningAuthorID: Int? = nil,
        isOwnPost: Bool = false,
        authorName: String,
        authorBadgeTexts: [String] = [],
        avatarURL: URL?,
        authorProfileURL: URL? = nil,
        metadataText: String?,
        contentHTML: String,
        signatureHTML: String? = nil,
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
        self.lowLevelWarningAuthorID = lowLevelWarningAuthorID
        self.isOwnPost = isOwnPost
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
        self.isRestricted = isRestricted
        self.comments = comments
        self.page = max(1, page)
        self.pagination = pagination
        self.isLastPage = isLastPage ?? (pagination?.nextPage == nil)
    }

    func updatingFavoriteState(count: Int?, isCollected: Bool) -> PostDetail {
        var updated = self
        updated.favoriteCount = count
        updated.isFavoriteCollected = isCollected
        return updated
    }

    func updatingPostLikeState(count: Int?, isClicked: Bool) -> PostDetail {
        var updated = self
        updated.likeCount = count
        updated.isLikeClicked = isClicked
        return updated
    }

    func updatingCommentLikeState(commentID: String, count: Int?, isClicked: Bool) -> PostDetail {
        var updated = self
        updated.comments = comments.map { comment in
            comment.id == commentID
                ? comment.updatingLikeReaction(count: count, isClicked: isClicked)
                : comment
        }
        return updated
    }

    func updatingPostChickenLegState(count: Int?, isClicked: Bool) -> PostDetail {
        var updated = self
        updated.chickenLegCount = count
        updated.isChickenLegClicked = isClicked
        return updated
    }

    func updatingCommentChickenLegState(commentID: String, count: Int?, isClicked: Bool) -> PostDetail {
        var updated = self
        updated.comments = comments.map { comment in
            comment.id == commentID
                ? comment.updatingChickenLegReaction(count: count, isClicked: isClicked)
                : comment
        }
        return updated
    }

    func updatingPostOpposeState(count: Int?, isClicked: Bool) -> PostDetail {
        var updated = self
        updated.opposeCount = count
        updated.isOpposeClicked = isClicked
        return updated
    }

    func updatingCommentOpposeState(commentID: String, count: Int?, isClicked: Bool) -> PostDetail {
        var updated = self
        updated.comments = comments.map { comment in
            comment.id == commentID
                ? comment.updatingOpposeReaction(count: count, isClicked: isClicked)
                : comment
        }
        return updated
    }

    func replacingComments(
        _ nextComments: [Comment],
        page: Int,
        pagination: PostDetailPagination?
    ) -> PostDetail {
        var updated = self
        updated.comments = nextComments
        updated.page = max(1, page)
        updated.pagination = pagination
        updated.isLastPage = pagination?.nextPage == nil
        return updated
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
    let signatureHTML: String?
    let isHot: Bool
    let likeCount: Int?
    let isLikeClicked: Bool
    let chickenLegCount: Int?
    let isChickenLegClicked: Bool
    let opposeCount: Int?
    let isOpposeClicked: Bool
    /// 当前登录用户发的评论，可以编辑。
    let isOwnComment: Bool

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
        signatureHTML: String? = nil,
        isHot: Bool = false,
        likeCount: Int? = nil,
        isLikeClicked: Bool = false,
        chickenLegCount: Int? = nil,
        isChickenLegClicked: Bool = false,
        opposeCount: Int? = nil,
        isOpposeClicked: Bool = false,
        isOwnComment: Bool = false
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
        self.signatureHTML = signatureHTML
        self.isHot = isHot
        self.likeCount = likeCount
        self.isLikeClicked = isLikeClicked
        self.chickenLegCount = chickenLegCount
        self.isChickenLegClicked = isChickenLegClicked
        self.opposeCount = opposeCount
        self.isOpposeClicked = isOpposeClicked
        self.isOwnComment = isOwnComment
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
            signatureHTML: signatureHTML,
            isHot: isHot,
            likeCount: count,
            isLikeClicked: isClicked,
            chickenLegCount: chickenLegCount,
            isChickenLegClicked: isChickenLegClicked,
            opposeCount: opposeCount,
            isOpposeClicked: isOpposeClicked,
            isOwnComment: isOwnComment
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
            signatureHTML: signatureHTML,
            isHot: isHot,
            likeCount: likeCount,
            isLikeClicked: isLikeClicked,
            chickenLegCount: count,
            isChickenLegClicked: isClicked,
            opposeCount: opposeCount,
            isOpposeClicked: isOpposeClicked,
            isOwnComment: isOwnComment
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
            signatureHTML: signatureHTML,
            isHot: isHot,
            likeCount: likeCount,
            isLikeClicked: isLikeClicked,
            chickenLegCount: chickenLegCount,
            isChickenLegClicked: isChickenLegClicked,
            opposeCount: count,
            isOpposeClicked: isClicked,
            isOwnComment: isOwnComment
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
