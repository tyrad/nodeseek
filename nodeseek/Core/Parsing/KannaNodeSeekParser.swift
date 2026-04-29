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
    let baseURL: URL

    func parseAccount(html: String) throws -> AccountResponse {
        let document = try HTML(html: html, encoding: .utf8)
        guard let userCard = document.at_xpath(XPathRules.accountUserCard) else {
            return AccountResponse(displayName: "游客", isLoggedIn: false)
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

    private func parsePostListItem(_ item: XMLElement, titleNode explicitTitleNode: XMLElement? = nil) -> PostSummary? {
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
        let authorName = firstText(in: item, xpaths: [XPathRules.postAuthor, XPathRules.fallbackAuthor]) ?? "未知用户"
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

    private func firstText(in item: XMLElement, xpaths: [String]) -> String? {
        for xpath in xpaths {
            if let value = item.at_xpath(xpath)?.text?.normalizedNonEmpty {
                return value
            }
        }

        return nil
    }

    private func firstAttribute(in item: XMLElement, xpaths: [String], attribute: String) -> String? {
        for xpath in xpaths {
            if let value = item.at_xpath(xpath)?[attribute]?.trimmedNonEmpty {
                return value
            }
        }

        return nil
    }

    func parsePostDetail(html: String, url: URL) throws -> PostDetail {
        let document = try HTML(html: html, encoding: .utf8)

        let title = document.at_xpath(XPathRules.postDetailTitle)?.text?.normalizedNonEmpty
            ?? document.at_xpath("//meta[@property='og:title']")?["content"]?.trimmedNonEmpty
            ?? document.at_xpath("//meta[@name='twitter:title']")?["content"]?.trimmedNonEmpty
            ?? document.at_xpath("//title")?.text?.normalizedNonEmpty

        guard let title else {
            throw NodeSeekParserError.postDetailNotFound
        }

        guard let bodyItem = document.at_xpath(XPathRules.postDetailBodyItem) else {
            throw NodeSeekParserError.postDetailNotFound
        }

        let authorName = firstText(in: bodyItem, xpaths: [XPathRules.contentAuthor]) ?? "未知用户"
        let avatarURL = firstAttribute(
            in: bodyItem,
            xpaths: [XPathRules.postAvatar, XPathRules.fallbackAvatar],
            attribute: "src"
        ).flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL }
        let createdAtText = firstText(in: bodyItem, xpaths: [XPathRules.contentCreatedAt])
        let categoryText = firstText(in: bodyItem, xpaths: [XPathRules.contentCategory])
        let metadataText = [createdAtText, categoryText].compactMap(\.self).joined(separator: " · ").trimmedNonEmpty
        let contentHTML = bodyItem.at_xpath(XPathRules.contentArticle)?.innerHTML?.trimmedNonEmpty ?? ""

        let comments = document.xpath(XPathRules.postDetailComments).compactMap { item -> Comment? in
            parseComment(item)
        }

        return PostDetail(
            id: Self.postID(from: url) ?? title,
            title: title,
            authorName: authorName,
            avatarURL: avatarURL,
            metadataText: metadataText,
            contentHTML: contentHTML,
            comments: comments,
            replyForm: nil
        )
    }

    func parseReplyForm(html: String, pageURL: URL) throws -> ReplyForm {
        throw NodeSeekParserError.notImplemented
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
    
    private static func firstInteger(in text: String) -> Int? {
        guard let range = text.range(of: #"\d+"#, options: .regularExpression) else {
            return nil
        }
        
        return Int(text[range])
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

    private func parseComment(_ item: XMLElement) -> Comment? {
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

        return Comment(
            id: id,
            anchorID: item["id"]?.trimmedNonEmpty,
            authorName: authorName,
            avatarURL: avatarURL,
            floorText: firstText(in: item, xpaths: [XPathRules.contentFloor]),
            createdAtText: firstText(in: item, xpaths: [XPathRules.contentCreatedAt]),
            contentHTML: item.at_xpath(XPathRules.contentArticle)?.innerHTML?.trimmedNonEmpty ?? ""
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
