//
//  CommentComposerContentBuilder.swift
//  nodeseek
//

import Foundation
import Kanna

enum CommentComposerMode: Equatable {
    case plain
    case reply(Comment)
    case quote(Comment)
}

enum CommentComposerContentBuilder {
    static func content(text: String, mode: CommentComposerMode, postURL: URL) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .plain:
            return trimmedText
        case .reply(let comment):
            return [replyPrefix(for: comment, postURL: postURL), trimmedText]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        case .quote(let comment):
            let quote = quoteText(for: comment, postURL: postURL)
            guard !trimmedText.isEmpty else { return quote }
            return "\(quote)\n\n\(trimmedText)"
        }
    }

    static func replyPrefix(for comment: Comment, postURL: URL) -> String {
        "@\(comment.authorName) [\(floorText(for: comment))](\(anchorURL(for: comment, postURL: postURL).absoluteString))"
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
