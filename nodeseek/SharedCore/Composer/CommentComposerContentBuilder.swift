//
//  CommentComposerContentBuilder.swift
//  nodeseek
//

import Foundation
import Kanna

struct CommentComposerMode: Equatable {
    let replies: [Comment]
    let quotes: [Comment]

    static let plain = CommentComposerMode()

    static func reply(_ comments: [Comment]) -> CommentComposerMode {
        CommentComposerMode(replies: comments, quotes: [])
    }

    static func quote(_ comments: [Comment]) -> CommentComposerMode {
        CommentComposerMode(replies: [], quotes: comments)
    }

    static func combined(replies: [Comment], quotes: [Comment]) -> CommentComposerMode {
        CommentComposerMode(replies: replies, quotes: quotes)
    }

    init(replies: [Comment] = [], quotes: [Comment] = []) {
        self.replies = replies
        self.quotes = quotes
    }

    func appendingReplies(_ comments: [Comment]) -> CommentComposerMode {
        CommentComposerMode(
            replies: Self.appendingUnique(existing: replies, incoming: comments),
            quotes: quotes
        )
    }

    func appendingQuotes(_ comments: [Comment]) -> CommentComposerMode {
        CommentComposerMode(
            replies: replies,
            quotes: Self.appendingUnique(existing: quotes, incoming: comments)
        )
    }

    func removingTarget(at displayIndex: Int) -> CommentComposerMode {
        if replies.indices.contains(displayIndex) {
            var nextReplies = replies
            nextReplies.remove(at: displayIndex)
            return CommentComposerMode(replies: nextReplies, quotes: quotes)
        }

        let quoteIndex = displayIndex - replies.count
        guard quotes.indices.contains(quoteIndex) else { return self }
        var nextQuotes = quotes
        nextQuotes.remove(at: quoteIndex)
        return CommentComposerMode(replies: replies, quotes: nextQuotes)
    }

    private static func appendingUnique(existing: [Comment], incoming: [Comment]) -> [Comment] {
        var seenIDs = Set(existing.map(\.id))
        var comments = existing
        for comment in incoming where seenIDs.insert(comment.id).inserted {
            comments.append(comment)
        }
        return comments
    }
}

enum CommentComposerContentBuilder {
    static func content(text: String, mode: CommentComposerMode, postURL: URL) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let quoteText = quoteBlocks(for: mode.quotes, postURL: postURL)
        let replyText = replyText(for: mode.replies, text: trimmedText, postURL: postURL)
        return [quoteText, replyText]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    static func replyPrefix(for comment: Comment, postURL: URL) -> String {
        "@\(comment.authorName) [\(floorText(for: comment))](\(anchorURL(for: comment, postURL: postURL).absoluteString))"
    }

    private static func replyText(for comments: [Comment], text: String, postURL: URL) -> String {
        let prefixes = comments.map { replyPrefix(for: $0, postURL: postURL) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return [prefixes, text]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func quoteBlocks(for comments: [Comment], postURL: URL) -> String {
        comments.map { quoteText(for: $0, postURL: postURL) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private static func quoteText(for comment: Comment, postURL: URL) -> String {
        var lines = ["> \(replyPrefix(for: comment, postURL: postURL)) 发布于\(comment.createdAtTitleText ?? comment.createdAtText ?? "")"]
        if let firstParagraph = firstQuotedParagraph(from: comment.contentHTML), !firstParagraph.isEmpty {
            lines.append("> \(firstParagraph)")
        }
        return lines.joined(separator: "\n")
    }

    private static func floorText(for comment: Comment) -> String {
        if let floorText = comment.floorText?.trimmingCharacters(in: .whitespacesAndNewlines), !floorText.isEmpty {
            return floorText
        }
        if let anchorID = comment.anchorID?.trimmingCharacters(in: .whitespacesAndNewlines), !anchorID.isEmpty {
            return "#\(anchorID)"
        }
        return "#\(comment.id)"
    }

    private static func anchorURL(for comment: Comment, postURL: URL) -> URL {
        var components = URLComponents(url: postURL, resolvingAgainstBaseURL: true)
        components?.fragment = comment.anchorID ?? comment.floorText?.replacingOccurrences(of: "#", with: "")
        return components?.url ?? postURL
    }

    private static func firstQuotedParagraph(from html: String) -> String? {
        let normalizedHTML = html.replacingOccurrences(
            of: #"<br\s*/?>"#,
            with: " ",
            options: .regularExpression
        )
        guard let document = try? HTML(html: normalizedHTML, encoding: .utf8) else {
            return html.normalizedQuoteText
        }

        let paragraphText = document.xpath("//p")
            .compactMap { $0.text?.normalizedQuoteText }
            .first { !$0.isEmpty }

        return paragraphText ?? document.text?.normalizedQuoteText
    }
}

private extension String {
    var normalizedQuoteText: String {
        components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
