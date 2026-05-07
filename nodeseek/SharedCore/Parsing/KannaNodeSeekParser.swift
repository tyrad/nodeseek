//
//  KannaNodeSeekParser.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation
import Kanna

enum NodeSeekParserError: Error {
    case notImplemented
    case postDetailNotFound
}

struct KannaNodeSeekParser: NodeSeekParser {
    typealias DebugLogger = @Sendable (String) -> Void

    let baseURL: URL
    private let debugLogger: DebugLogger?

    init(baseURL: URL, debugLogger: DebugLogger? = nil) {
        self.baseURL = baseURL
        self.debugLogger = debugLogger
    }

    func parseAccount(html: String) throws -> AccountResponse {
        let document = try HTML(html: html, encoding: .utf8)
        let notification = parseAccountNotification(document)
        if let account = parseAccountFromUserCard(document)
            ?? parseAccountFromTempScript(document)
            ?? parseAccountFromCapturedConfig(document) {
            return account.withNotification(notification)
        }

        postAccountParserDebug("parser: account user-card/config missing or decode failed")
        return AccountResponse(displayName: "游客", isLoggedIn: false, notification: notification)
    }

    private func parseAccountNotification(_ document: HTMLDocument) -> AccountNotification? {
        guard let link = document.at_xpath(XPathRules.accountNotificationLink),
              let href = link["href"],
              let url = URL(string: href, relativeTo: baseURL)?.absoluteURL else {
            return nil
        }

        let style = link.at_xpath(XPathRules.accountNotificationIcon)?["style"]
            ?? link["style"]
        return AccountNotification(
            url: url,
            iconColorCSS: cssColorValue(from: style)
        )
    }

    private func cssColorValue(from style: String?) -> String? {
        guard let style else { return nil }
        let pattern = #"(?i)(?:^|;)\s*color\s*:\s*([^;]+)"#
        guard let match = style.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        let matched = String(style[match])
        guard let separator = matched.firstIndex(of: ":") else { return nil }
        return String(matched[matched.index(after: separator)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmedNonEmpty
    }

    private func parseAccountFromUserCard(_ document: HTMLDocument) -> AccountResponse? {
        guard let userCard = document.at_xpath(XPathRules.accountUserCard) else {
            return nil
        }

        let usernameNode = userCard.at_xpath(XPathRules.accountUsername)
            ?? userCard.at_xpath(XPathRules.accountProfileLink)
        let displayName = usernameNode?.text?.normalizedNonEmpty
            ?? usernameNode?["title"]?.trimmedNonEmpty
            ?? userCard.at_xpath(XPathRules.accountAvatar)?["alt"]?.trimmedNonEmpty
            ?? "已登录"
        let profileURL = (usernameNode?["href"] ?? userCard.at_xpath(XPathRules.accountProfileLink)?["href"])
            .flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL }
        let avatarURL = userCard.at_xpath(XPathRules.accountAvatar)?["src"]?
            .trimmedNonEmpty
            .flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL }
        let linkStats = userCard.xpath(XPathRules.accountStatLinks)
            .compactMap { $0.text?.normalizedNonEmpty }
        let fallbackStats = userCard.xpath(XPathRules.accountStatSpans)
            .compactMap { $0.text?.normalizedNonEmpty }
        let stats = (linkStats.isEmpty ? fallbackStats : linkStats)
            .reduce(into: [String]()) { result, value in
                guard !result.contains(value) else { return }
                result.append(value)
            }

        return AccountResponse(
            displayName: displayName,
            isLoggedIn: true,
            avatarURL: avatarURL,
            profileURL: profileURL,
            stats: Array(stats.prefix(6))
        )
    }

    private func parseAccountFromTempScript(_ document: HTMLDocument) -> AccountResponse? {
        guard let script = document.at_xpath(XPathRules.accountTempScript) else {
            return nil
        }
        guard
            let payload = script.text?.trimmedNonEmpty,
            let data = Data(base64Encoded: payload, options: [.ignoreUnknownCharacters]),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            postAccountParserDebug("parser: temp-script decode failed")
            return nil
        }

        return parseAccountFromConfiguration(root: root, source: "temp-script")
    }

    private func parseAccountFromCapturedConfig(_ document: HTMLDocument) -> AccountResponse? {
        guard let script = document.at_xpath(XPathRules.accountCapturedConfig) else {
            return nil
        }
        guard
            let payload = script.text?.trimmedNonEmpty,
            let data = payload.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            postAccountParserDebug("parser: captured-config decode failed")
            return nil
        }

        return parseAccountFromConfiguration(root: root, source: "captured-config")
    }

    private func parseAccountFromConfiguration(root: [String: Any], source: String) -> AccountResponse? {
        let user = tempScriptUserDictionary(from: root)
        guard
            let memberID = intValue(in: user, keys: ["member_id", "memberID", "uid", "id"]),
            let displayName = stringValue(in: user, keys: ["member_name", "memberName", "name", "username"])
        else {
            postAccountParserDebug("parser: \(source) user keys=\(user.keys.sorted().joined(separator: ","))")
            return nil
        }

        postAccountParserDebug("parser: \(source) user id=\(memberID) name=\(displayName)")
        let avatarPath = stringValue(in: user, keys: ["avatar"]) ?? "/avatar/\(memberID).png"
        let profilePath = stringValue(in: user, keys: ["profile"]) ?? "/space/\(memberID)"
        let avatarURL = URL(string: avatarPath, relativeTo: baseURL)?.absoluteURL
        let profileURL = URL(string: profilePath, relativeTo: baseURL)?.absoluteURL
        let stats = [
            intValue(in: user, keys: ["rank"]).map { "等级 Lv \($0)" },
            intValue(in: user, keys: ["coin"]).map { "鸡腿 \($0)" },
            intValue(in: user, keys: ["stardust"]).map { "星辰 \($0)" }
        ].compactMap(\.self)

        return AccountResponse(
            displayName: displayName,
            isLoggedIn: true,
            avatarURL: avatarURL,
            profileURL: profileURL,
            stats: stats
        )
    }

    private func postAccountParserDebug(_ message: String) {
        debugLogger?(message)
    }

    private func tempScriptUserDictionary(from root: [String: Any]) -> [String: Any] {
        for key in ["user", "currentUser", "current_user", "member"] {
            if let dictionary = root[key] as? [String: Any] {
                return dictionary
            }
        }
        return root
    }

    private func intValue(in dictionary: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            switch dictionary[key] {
            case let value as Int:
                return value
            case let value as Double:
                return Int(value)
            case let value as String:
                if let intValue = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    return intValue
                }
            default:
                continue
            }
        }
        return nil
    }

    private func stringValue(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String, let trimmedValue = value.trimmedNonEmpty {
                return trimmedValue
            }
        }
        return nil
    }

    func parsePostList(html: String) throws -> [PostSummary] {
        let document = try HTML(html: html, encoding: .utf8)

        var seenIDs = Set<String>()
        var posts: [PostSummary] = []

        for item in document.xpath(XPathRules.postListItems) {
            guard let post = parsePostListItem(item) else {
                continue
            }

            append(post, to: &posts, seenIDs: &seenIDs)
        }

        for titleNode in document.xpath(XPathRules.fallbackPostLinks) {
            let container = titleNode.at_xpath(XPathRules.fallbackPostContainer) ?? titleNode
            guard let post = parsePostListItem(container, titleNode: titleNode) else {
                continue
            }

            append(post, to: &posts, seenIDs: &seenIDs)
        }

        return posts
    }

    private func append(_ post: PostSummary, to posts: inout [PostSummary], seenIDs: inout Set<String>) {
        guard seenIDs.insert(post.id).inserted else {
            return
        }

        posts.append(post)
    }

    private func parsePostListItem(_ item: Kanna.XMLElement, titleNode explicitTitleNode: Kanna.XMLElement? = nil) -> PostSummary? {
        guard
            let titleNode = explicitTitleNode ?? item.at_xpath(XPathRules.postTitle),
            let title = titleNode.text?.normalizedNonEmpty
        else {
            return nil
        }

        let href = titleNode["href"] ?? titleNode.at_xpath(".//a")?["href"]
        let url = href.flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL } ?? baseURL
        let id = Self.postID(from: url) ?? title
        let avatarURL = firstAttribute(
            in: item,
            xpaths: [XPathRules.postAvatar, XPathRules.fallbackAvatar],
            attribute: "src"
        ).flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL }
        let authorName = firstText(in: item, xpaths: [XPathRules.postAuthor, XPathRules.fallbackAuthor]) ?? ""
        let nodeName = firstText(in: item, xpaths: [XPathRules.postNode, XPathRules.fallbackNode])
        let viewNode = item.at_xpath(XPathRules.viewCount)
        let viewText = viewNode?["title"] ?? viewNode?.text ?? ""
        let viewCount = Self.firstInteger(in: viewText) ?? 0
        let replyText = item.at_xpath(XPathRules.replyCount)?.text ?? item.text ?? ""
        let replyCount = Self.replyCount(in: replyText) ?? 0
        let lastActivityText = firstText(in: item, xpaths: [XPathRules.lastActive, XPathRules.fallbackLastActive])
        let isPinned = item.at_xpath(XPathRules.postPinned) != nil
        let isLocked = item.at_xpath(XPathRules.postLocked) != nil

        return PostSummary(
            id: id,
            title: title,
            url: url,
            authorName: authorName,
            nodeName: nodeName,
            replyCount: replyCount,
            viewCount: viewCount,
            lastActivityText: lastActivityText,
            isPinned: isPinned,
            isLocked: isLocked,
            avatarURL: avatarURL
        )
    }

    private func firstText(in item: Kanna.XMLElement, xpaths: [String]) -> String? {
        for xpath in xpaths {
            if let value = item.at_xpath(xpath)?.text?.normalizedNonEmpty {
                return value
            }
        }

        return nil
    }

    private func firstAttribute(in item: Kanna.XMLElement, xpaths: [String], attribute: String) -> String? {
        for xpath in xpaths {
            if let value = item.at_xpath(xpath)?[attribute]?.trimmedNonEmpty {
                return value
            }
        }

        return nil
    }

    func parsePostDetail(html: String, url: URL) throws -> PostDetail {
        let document = try HTML(html: html, encoding: .utf8)
        let restrictedNotice = postDetailRestrictedNotice(in: document)
        let reactionConfiguration = parsePostReactionConfiguration(in: document)

        let parsedTitle = document.at_xpath(XPathRules.postDetailTitleLink)?.text?.normalizedNonEmpty
            ?? document.at_xpath(XPathRules.postDetailTitleFallback)?.text?.normalizedNonEmpty
            ?? document.at_xpath("//meta[@property='og:title']")?["content"]?.trimmedNonEmpty
            ?? document.at_xpath("//meta[@name='twitter:title']")?["content"]?.trimmedNonEmpty
            ?? document.at_xpath("//title")?.text?.normalizedNonEmpty
        let title = Self.isGenericPostDetailTitle(parsedTitle)
            ? restrictedNotice.map { _ in "受限帖子" }
            : parsedTitle

        guard let title else {
            throw NodeSeekParserError.postDetailNotFound
        }

        let bodyItem = document.at_xpath(XPathRules.postDetailBodyItem)
        let authorName = bodyItem.flatMap { firstText(in: $0, xpaths: [XPathRules.contentAuthor]) } ?? ""
        let avatarURL = bodyItem.flatMap {
            firstAttribute(
                in: $0,
                xpaths: [XPathRules.postAvatar, XPathRules.fallbackAvatar],
                attribute: "src"
            )
        }.flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL }
        let authorProfileURL = bodyItem.flatMap { parseUserProfileURL(in: $0) }
        let createdAtText = bodyItem.flatMap { firstText(in: $0, xpaths: [XPathRules.contentCreatedAt]) }
        let categoryText = bodyItem.flatMap { firstText(in: $0, xpaths: [XPathRules.contentCategory]) }
        let metadataText = [createdAtText, categoryText].compactMap(\.self).joined(separator: " · ").trimmedNonEmpty
        let contentHTML = postDetailContentHTML(bodyItem: bodyItem, document: document)
        let requiredReadingLevel = document
            .at_xpath(XPathRules.postDetailRequiredReadingLevel)?
            .text?
            .normalizedNonEmpty
            .flatMap(Self.firstInteger(in:))
            ?? restrictedNotice.flatMap(Self.firstInteger(in:))

        let comments = document.xpath(XPathRules.postDetailComments).compactMap { item -> Comment? in
            parseComment(item, reactionConfiguration: reactionConfiguration)
        }
        let page = Self.postPage(from: url) ?? 1
        let pagination = parsePostDetailPagination(in: document, pageURL: url)
        let bodyReactionConfiguration = bodyItem.flatMap {
            reactionConfiguration?.commentConfiguration(for: $0)
        }
        let bodyLikeCount = bodyItem.flatMap { parseReactionCount(in: $0, kind: .like) }
            ?? bodyReactionConfiguration?.likeCount
        let bodyChickenLegCount = bodyItem.flatMap { parseReactionCount(in: $0, kind: .chickenLeg) }
            ?? bodyReactionConfiguration?.chickenLegCount
        let bodyOpposeCount = bodyItem.flatMap { parseReactionCount(in: $0, kind: .oppose) }
            ?? bodyReactionConfiguration?.opposeCount
        let bodyFavoriteCount = bodyItem.flatMap { parseReactionCount(in: $0, kind: .favorite) }
            ?? reactionConfiguration?.collectionCount
        let isFavoriteCollected = bodyItem.map {
            hasRenderedReactionMenu(in: $0)
                ? parseReactionClicked(in: $0, kind: .favorite)
                : reactionConfiguration?.collected ?? false
        } ?? reactionConfiguration?.collected ?? false

        return PostDetail(
            id: Self.postID(from: url) ?? title,
            title: title,
            requiredReadingLevel: requiredReadingLevel,
            authorName: authorName,
            avatarURL: avatarURL,
            authorProfileURL: authorProfileURL,
            metadataText: metadataText,
            contentHTML: contentHTML,
            likeCount: bodyLikeCount,
            isLikeClicked: bodyItem.map { parseReactionClicked(in: $0, kind: .like) } ?? false,
            chickenLegCount: bodyChickenLegCount,
            isChickenLegClicked: bodyItem.map { parseReactionClicked(in: $0, kind: .chickenLeg) } ?? false,
            opposeCount: bodyOpposeCount,
            isOpposeClicked: bodyItem.map { parseReactionClicked(in: $0, kind: .oppose) } ?? false,
            favoriteCount: bodyFavoriteCount,
            isFavoriteCollected: isFavoriteCollected,
            comments: comments,
            page: page,
            pagination: pagination,
            isLastPage: document.at_xpath(XPathRules.postDetailNextPage) == nil
        )
    }

    private func postDetailContentHTML(bodyItem: Kanna.XMLElement?, document: HTMLDocument) -> String {
        if let contentHTML = bodyItem?.at_xpath(XPathRules.contentArticle)?.innerHTML?.trimmedNonEmpty {
            return contentHTML
        }

        if let notice = postDetailRestrictedNotice(in: document) {
            return notice
        }

        return ""
    }

    private func postDetailRestrictedNotice(in document: HTMLDocument) -> String? {
        document.at_xpath(XPathRules.postDetailRestrictedNotice)?.text?.normalizedNonEmpty
    }

    func parseCheckInState(html: String, pageURL: URL) throws -> CheckInState {
        throw NodeSeekParserError.notImplemented
    }
    
    private static func postID(from url: URL) -> String? {
        let path = url.path
        guard let range = path.range(of: #"post[-/](\d+)"#, options: .regularExpression) else {
            return nil
        }
        
        return String(path[range])
            .components(separatedBy: CharacterSet.decimalDigits.inverted)
            .joined()
            .trimmedNonEmpty
    }

    private static func postPage(from url: URL) -> Int? {
        let path = url.path
        guard let range = path.range(of: #"post[-/]\d+-(\d+)"#, options: .regularExpression) else {
            return nil
        }

        return String(path[range])
            .components(separatedBy: CharacterSet.decimalDigits.inverted)
            .compactMap(Int.init)
            .last
    }

    private static func postPage(from href: String?, relativeTo baseURL: URL) -> Int? {
        guard let href,
              let url = URL(string: href, relativeTo: baseURL)?.absoluteURL else {
            return nil
        }
        return postPage(from: url)
    }
    
    nonisolated private static func firstInteger(in text: String) -> Int? {
        guard let range = text.range(of: #"\d+"#, options: .regularExpression) else {
            return nil
        }
        
        return Int(text[range])
    }

    private static func isGenericPostDetailTitle(_ title: String?) -> Bool {
        guard let title else { return false }
        return title == "NodeSeek"
    }

    private static func replyCount(in text: String) -> Int? {
        if let range = text.range(of: #"\d+\s*(回复|条回复|评论)"#, options: .regularExpression) {
            return firstInteger(in: String(text[range]))
        }

        if let range = text.range(of: #"(回复|评论)\s*\d+"#, options: .regularExpression) {
            return firstInteger(in: String(text[range]))
        }

        if let range = text.range(of: #"\d+\s*comments?"#, options: .regularExpression) {
            return firstInteger(in: String(text[range]))
        }

        if let range = text.range(of: #"comments?\s*\d+"#, options: .regularExpression) {
            return firstInteger(in: String(text[range]))
        }

        return firstInteger(in: text)
    }

    private func parsePostDetailPagination(in document: HTMLDocument, pageURL: URL) -> PostDetailPagination? {
        guard let pager = document.at_xpath(XPathRules.postDetailPagination) else {
            return nil
        }

        let currentPageFromURL = Self.postPage(from: pageURL) ?? 1
        var seenPages: Set<Int> = []
        var items: [PostDetailPageItem] = []

        for item in pager.xpath(XPathRules.pagerPositionItems) {
            let page = Self.firstInteger(in: item.text ?? "")
                ?? Self.postPage(from: item["href"], relativeTo: baseURL)
            guard let page, page > 0, seenPages.insert(page).inserted else {
                continue
            }

            let url = item["href"]
                .flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL }
            let className = item["class"] ?? ""
            let isCurrent = className.contains("pager-cur") || page == currentPageFromURL && url == nil
            items.append(PostDetailPageItem(page: page, url: url, isCurrent: isCurrent))
        }

        let currentPage = items.first(where: \.isCurrent)?.page ?? currentPageFromURL
        let previousPage = Self.postPage(from: pager.at_xpath(XPathRules.pagerPrevious)?["href"], relativeTo: baseURL)
        let nextPage = Self.postPage(from: pager.at_xpath(XPathRules.pagerNext)?["href"], relativeTo: baseURL)
        let pagination = PostDetailPagination(
            currentPage: currentPage,
            items: items,
            previousPage: previousPage,
            nextPage: nextPage
        )
        return pagination.hasMultiplePages ? pagination : nil
    }

    private func parseComment(
        _ item: Kanna.XMLElement,
        reactionConfiguration: PostReactionConfiguration?
    ) -> Comment? {
        guard let authorName = firstText(in: item, xpaths: [XPathRules.contentAuthor]) else {
            return nil
        }

        let id = item["data-comment-id"]?.trimmedNonEmpty
            ?? item["id"]?.trimmedNonEmpty
            ?? UUID().uuidString
        let avatarURL = firstAttribute(
            in: item,
            xpaths: [XPathRules.postAvatar, XPathRules.fallbackAvatar],
            attribute: "src"
        ).flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL }
        let authorProfileURL = parseUserProfileURL(in: item)
        let commentReactionConfiguration = reactionConfiguration?.commentConfiguration(for: item)
        let likeCount = parseReactionCount(in: item, kind: .like)
            ?? commentReactionConfiguration?.likeCount
        let chickenLegCount = parseReactionCount(in: item, kind: .chickenLeg)
            ?? commentReactionConfiguration?.chickenLegCount
        let opposeCount = parseReactionCount(in: item, kind: .oppose)
            ?? commentReactionConfiguration?.opposeCount

        return Comment(
            id: id,
            anchorID: item["id"]?.trimmedNonEmpty,
            authorName: authorName,
            isPoster: item.at_xpath(XPathRules.contentPosterBadge) != nil,
            avatarURL: avatarURL,
            authorProfileURL: authorProfileURL,
            authorBadgeTexts: parseAuthorBadgeTexts(in: item),
            floorText: firstText(in: item, xpaths: [XPathRules.contentFloor]),
            createdAtText: firstText(in: item, xpaths: [XPathRules.contentCreatedAt]),
            createdAtTitleText: firstAttribute(
                in: item,
                xpaths: [XPathRules.contentCreatedAt],
                attribute: "title"
            ),
            contentHTML: item.at_xpath(XPathRules.contentArticle)?.innerHTML?.trimmedNonEmpty ?? "",
            isHot: item.at_xpath(XPathRules.contentHotBadge) != nil,
            likeCount: likeCount,
            isLikeClicked: parseReactionClicked(in: item, kind: .like),
            chickenLegCount: chickenLegCount,
            isChickenLegClicked: parseReactionClicked(in: item, kind: .chickenLeg),
            opposeCount: opposeCount,
            isOpposeClicked: parseReactionClicked(in: item, kind: .oppose)
        )
    }

    private func parseAuthorBadgeTexts(in item: Kanna.XMLElement) -> [String] {
        var seen = Set<String>()
        return item.xpath(XPathRules.contentAuthorBadges).compactMap { node in
            guard node.at_xpath("ancestor::*[contains(concat(' ', normalize-space(@class), ' '), ' hot-badge ')]") == nil else {
                return nil
            }
            let value = node.text?.normalizedNonEmpty
            guard let value, value != "楼主", seen.insert(value).inserted else {
                return nil
            }
            return value
        }
    }

    fileprivate enum ReactionKind {
        case like
        case chickenLeg
        case oppose
        case favorite

        var rootAttributes: [String] {
            switch self {
            case .like:
                return ["data-like-count", "data-likes", "data-upvote-count", "data-up-count"]
            case .chickenLeg:
                return ["data-chicken-leg-count", "data-chicken-count", "data-stardust-count", "data-coin-count"]
            case .oppose:
                return ["data-oppose-count", "data-dislike-count", "data-downvote-count", "data-down-count"]
            case .favorite:
                return ["data-favorite-count", "data-favorites", "data-bookmark-count", "data-star-count"]
            }
        }

        var countAttributes: [String] {
            switch self {
            case .like:
                return ["data-like-count", "data-likes", "data-upvote-count", "data-up-count", "data-count", "aria-label", "title"]
            case .chickenLeg:
                return ["data-chicken-leg-count", "data-chicken-count", "data-stardust-count", "data-coin-count", "data-count", "aria-label", "title"]
            case .oppose:
                return ["data-oppose-count", "data-dislike-count", "data-downvote-count", "data-down-count", "data-count", "aria-label", "title"]
            case .favorite:
                return ["data-favorite-count", "data-favorites", "data-bookmark-count", "data-star-count", "data-count", "aria-label", "title"]
            }
        }

        var markers: [String] {
            switch self {
            case .like:
                return ["like", "upvote", "thumbsup", "thumb-up", "vote-up", "点赞", "赞同"]
            case .chickenLeg:
                return ["chicken", "chicken-leg", "stardust", "coin", "drumstick", "鸡腿", "加鸡腿"]
            case .oppose:
                return ["oppose", "dislike", "downvote", "thumbsdown", "thumb-down", "vote-down", "点踩", "反对"]
            case .favorite:
                return ["favorite", "favourite", "bookmark", "star", "collect", "收藏"]
            }
        }
    }

    private func parseReactionCount(in item: Kanna.XMLElement, kind: ReactionKind) -> Int? {
        if let count = parseRenderedReactionMenuCount(in: item, kind: kind) {
            return count
        }

        if let count = firstInteger(inAttributesOf: item, attributes: kind.rootAttributes) {
            return count
        }

        for node in item.xpath(".//*") where node.matchesReaction(kind) {
            if let count = firstInteger(inAttributesOf: node, attributes: kind.countAttributes) {
                return count
            }

            if let countText = node
                .at_xpath(".//*[contains(concat(' ', normalize-space(@class), ' '), ' count ') or contains(@class, 'num') or contains(@class, 'badge')]")?
                .text,
               let count = Self.firstInteger(in: countText) {
                return count
            }

            if let text = node.text, let count = Self.firstInteger(in: text) {
                return count
            }

            if let siblingText = node.at_xpath("./following-sibling::*[1]")?.text,
               let count = Self.firstInteger(in: siblingText) {
                return count
            }
        }

        return nil
    }

    private func parseRenderedReactionMenuCount(in item: Kanna.XMLElement, kind: ReactionKind) -> Int? {
        for node in item.xpath(".//*[contains(concat(' ', normalize-space(@class), ' '), ' comment-menu ')]//*[contains(concat(' ', normalize-space(@class), ' '), ' menu-item ')]") where node.matchesReaction(kind) {
            if let countText = node.at_xpath(".//span[normalize-space()][1]")?.text,
               let count = Self.firstInteger(in: countText) {
                return count
            }

            if let text = node.text, let count = Self.firstInteger(in: text) {
                return count
            }
        }

        return nil
    }

    private func parseReactionClicked(in item: Kanna.XMLElement, kind: ReactionKind) -> Bool {
        item.xpath(".//*").contains { node in
            node.matchesReaction(kind) && node.hasClass("clicked")
        }
    }

    private func hasRenderedReactionMenu(in item: Kanna.XMLElement) -> Bool {
        item.at_xpath(".//*[contains(concat(' ', normalize-space(@class), ' '), ' comment-menu ')]") != nil
    }

    private struct PostReactionConfiguration {
        let collectionCount: Int?
        let collected: Bool?
        let commentsByID: [String: CommentReactionConfiguration]
        let commentsByFloor: [Int: CommentReactionConfiguration]

        func commentConfiguration(for item: Kanna.XMLElement) -> CommentReactionConfiguration? {
            if let commentID = item["data-comment-id"]?.trimmedNonEmpty,
               let configuration = commentsByID[commentID] {
                return configuration
            }

            if let floorText = item["id"]?.trimmedNonEmpty,
               let floorIndex = Int(floorText),
               let configuration = commentsByFloor[floorIndex] {
                return configuration
            }

            return nil
        }
    }

    private struct CommentReactionConfiguration {
        let commentID: String?
        let floorIndex: Int?
        let likeCount: Int?
        let chickenLegCount: Int?
        let opposeCount: Int?
    }

    private func parsePostReactionConfiguration(in document: HTMLDocument) -> PostReactionConfiguration? {
        configRoots(in: document)
            .lazy
            .compactMap(parsePostReactionConfiguration(from:))
            .first
    }

    private func configRoots(in document: HTMLDocument) -> [[String: Any]] {
        var roots: [[String: Any]] = []

        if let script = document.at_xpath(XPathRules.accountCapturedConfig),
           let payload = script.text?.trimmedNonEmpty,
           let data = payload.data(using: .utf8),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            roots.append(root)
        }

        if let script = document.at_xpath(XPathRules.accountTempScript),
           let payload = script.text?.trimmedNonEmpty,
           let data = Data(base64Encoded: payload, options: [.ignoreUnknownCharacters]),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            roots.append(root)
        }

        return roots
    }

    private func parsePostReactionConfiguration(from root: [String: Any]) -> PostReactionConfiguration? {
        guard let postData = root["postData"] as? [String: Any] else {
            return nil
        }

        let comments = (postData["comments"] as? [[String: Any]] ?? [])
            .map(parseCommentReactionConfiguration(from:))
        var commentsByID: [String: CommentReactionConfiguration] = [:]
        var commentsByFloor: [Int: CommentReactionConfiguration] = [:]

        for comment in comments {
            if let commentID = comment.commentID {
                commentsByID[commentID] = comment
            }
            if let floorIndex = comment.floorIndex {
                commentsByFloor[floorIndex] = comment
            }
        }

        let collectionCount = intValue(in: postData, keys: ["collectionCount"])
        let collected = boolValue(in: postData, keys: ["collected"])
        guard collectionCount != nil
            || collected != nil
            || comments.isEmpty == false else {
            return nil
        }

        return PostReactionConfiguration(
            collectionCount: collectionCount,
            collected: collected,
            commentsByID: commentsByID,
            commentsByFloor: commentsByFloor
        )
    }

    private func parseCommentReactionConfiguration(from comment: [String: Any]) -> CommentReactionConfiguration {
        CommentReactionConfiguration(
            commentID: stringValue(in: comment, keys: ["commentId", "commentID", "id"])
                ?? intValue(in: comment, keys: ["commentId", "commentID", "id"]).map(String.init),
            floorIndex: intValue(in: comment, keys: ["floorIndex", "floor"]),
            likeCount: intValue(in: comment, keys: ["upvoteCount"]),
            chickenLegCount: intValue(in: comment, keys: ["likeCount"]),
            opposeCount: intValue(in: comment, keys: ["dislikeCount"])
        )
    }

    private func boolValue(in dictionary: [String: Any], keys: [String]) -> Bool? {
        for key in keys {
            switch dictionary[key] {
            case let value as Bool:
                return value
            case let value as Int:
                return value != 0
            case let value as Double:
                return value != 0
            case let value as String:
                let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if ["true", "1", "yes"].contains(normalized) {
                    return true
                }
                if ["false", "0", "no"].contains(normalized) {
                    return false
                }
            default:
                continue
            }
        }
        return nil
    }

    private func firstInteger(inAttributesOf node: Kanna.XMLElement, attributes: [String]) -> Int? {
        for attribute in attributes {
            guard let value = node[attribute]?.trimmedNonEmpty else { continue }
            if let integer = Self.firstInteger(in: value) {
                return integer
            }
        }

        return nil
    }

    private func parseUserProfileURL(in item: Kanna.XMLElement) -> URL? {
        for xpath in [XPathRules.contentAuthorProfileLink, XPathRules.contentAvatarProfileLink] {
            guard let href = item.at_xpath(xpath)?["href"]?.trimmedNonEmpty else { continue }
            guard let url = normalizeUserProfileURL(href) else { continue }
            return url
        }

        return nil
    }

    private func normalizeUserProfileURL(_ href: String) -> URL? {
        guard let url = URL(string: href, relativeTo: baseURL)?.absoluteURL else { return nil }
        guard url.path.hasPrefix("/space/") else { return nil }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return url }
        components.fragment = "/general"
        return components.url
    }

    private func isLastPostPage(in document: HTMLDocument, currentURL: URL) -> Bool {
        guard let currentPostID = Self.postID(from: currentURL) else { return true }
        let currentPage = currentPostPage(from: currentURL)
        let nextLinks = document.xpath("//a[@rel='next' and contains(@href, '/post-')]")

        return nextLinks.contains { link in
            guard let href = link["href"],
                  let url = URL(string: href, relativeTo: baseURL)?.absoluteURL,
                  Self.postID(from: url) == currentPostID else {
                return false
            }

            return currentPostPage(from: url) > currentPage
        } == false
    }

    private func currentPostPage(from url: URL) -> Int {
        let path = url.path
        guard let range = path.range(of: #"post[-/]\d+[-/](\d+)"#, options: .regularExpression) else {
            return 1
        }

        return Int(String(path[range]).components(separatedBy: CharacterSet.decimalDigits.inverted).last ?? "") ?? 1
    }
}

private extension AccountResponse {
    func withNotification(_ notification: AccountNotification?) -> AccountResponse {
        AccountResponse(
            displayName: displayName,
            isLoggedIn: isLoggedIn,
            avatarURL: avatarURL,
            profileURL: profileURL,
            stats: stats,
            notification: notification
        )
    }
}

private extension String {
    
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var normalizedNonEmpty: String? {
        let value = components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return value.isEmpty ? nil : value
    }
}

private extension Kanna.XMLElement {
    func matchesReaction(_ kind: KannaNodeSeekParser.ReactionKind) -> Bool {
        let haystack = [
            self["class"],
            self["id"],
            self["name"],
            self["role"],
            self["aria-label"],
            self["title"],
            self["data-action"],
            self["data-type"],
            self["data-testid"]
        ]
            .compactMap { $0?.trimmedNonEmpty }
            .joined(separator: " ")
            .lowercased()

        guard haystack.isEmpty == false else { return false }
        return kind.markers.contains { haystack.contains($0.lowercased()) }
    }

    func hasClass(_ className: String) -> Bool {
        guard let value = self["class"] else { return false }
        return value
            .split(whereSeparator: { $0.isWhitespace })
            .contains { $0 == className }
    }
}
