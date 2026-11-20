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

    /// 与网页「引用」一致：标题行带发布（和编辑）时间，正文取原始 Markdown 逐行加 "> "。
    private static func quoteText(for comment: Comment, postURL: URL) -> String {
        var header = "> \(replyPrefix(for: comment, postURL: postURL)) 发布于\(comment.createdAtTitleText ?? comment.createdAtText ?? "")"
        if let editedAt = comment.editedAtTitleText, !editedAt.isEmpty {
            header += "，编辑于\(editedAt)"
        }
        let bodyLines = comment.markdown.map { $0.components(separatedBy: "\n") }
            ?? fallbackQuotedLines(from: comment.contentHTML)
        return ([header] + bodyLines.map { "> \($0)" }).joined(separator: "\n")
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
        let floor = comment.anchorID ?? comment.floorText?.replacingOccurrences(of: "#", with: "")
        var components = URLComponents(url: postURL, resolvingAgainstBaseURL: true)
        if let floorNumber = floor.flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }),
           let path = components?.path {
            // 链接指向楼层所在页，而不是当前浏览的页，和网页一致
            components?.path = path.replacingOccurrences(
                of: #"^(/post-\d+)-\d+$"#,
                with: "$1-\(commentPage(forFloor: floorNumber))",
                options: .regularExpression
            )
        }
        components?.fragment = floor
        return components?.url ?? postURL
    }

    /// 网页规则：0 楼在第 1 页，其余每 10 楼一页。
    static func commentPage(forFloor floor: Int) -> Int {
        floor <= 0 ? 1 : (floor - 1) / 10 + 1
    }

    /// 页面配置里没有 Markdown（例如热评来自其他页）时退回解析 HTML，按段落和换行保留行结构。
    private static func fallbackQuotedLines(from html: String) -> [String] {
        let normalizedHTML = html.replacingOccurrences(
            of: #"<br\s*/?>"#,
            with: "\n",
            options: .regularExpression
        )
        guard let document = try? HTML(html: normalizedHTML, encoding: .utf8) else {
            return html.quoteLines
        }
        let paragraphLines = document.xpath("//p").flatMap { $0.text?.quoteLines ?? [] }
        return paragraphLines.isEmpty ? (document.text?.quoteLines ?? []) : paragraphLines
    }
}

private extension String {
    /// 按换行拆行，行内多余空白压成一个空格，去掉空行。
    var quoteLines: [String] {
        components(separatedBy: .newlines)
            .map { line in
                line.components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
            .filter { !$0.isEmpty }
    }
}
