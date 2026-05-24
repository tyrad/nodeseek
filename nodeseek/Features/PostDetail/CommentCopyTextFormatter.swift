//
//  CommentCopyTextFormatter.swift
//  nodeseek
//
//  Created by Codex on 2026/5/24.
//

import Foundation

enum CommentCopyTextFormatter {
    static func plainText(for comment: Comment, baseURL: URL) -> String {
        let blocks = DTCoreTextHTMLContentRenderer().render(
            fragment: comment.contentHTML,
            baseURL: baseURL
        )
        return plainText(from: blocks)
    }

    static func plainText(for content: PostDetailHeaderContent, baseURL: URL) -> String {
        let blocks = DTCoreTextHTMLContentRenderer().render(
            fragment: content.contentHTML,
            baseURL: baseURL
        )
        return plainText(from: blocks)
    }

    static func plainText(from blocks: [RenderedContentBlock]) -> String {
        normalizedText(blocks.compactMap(text).joined(separator: "\n"))
    }

    private static func text(from block: RenderedContentBlock) -> String? {
        switch block {
        case .text(let attributedText):
            return attributedText.string
        case .table(let table):
            let rows = table.rows.map { row in
                row.cells.map(\.text).joined(separator: "\t")
            }
            return rows.joined(separator: "\n")
        case .codeBlock(let codeBlock):
            return codeBlock.text
        case .quote(let quoteBlock):
            return plainText(from: quoteBlock.children)
        case .iframeLink(let iframe):
            return iframe.openURL.absoluteString
        case .image(let image):
            return image.altText
        case .imagePlaceholder, .unsupported:
            return nil
        }
    }

    private static func normalizedText(_ text: String) -> String {
        let text = text
            .replacingOccurrences(of: "\u{fffc}", with: "")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let lines = text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        var result: [String] = []
        var previousWasEmpty = false
        for line in lines {
            if line.isEmpty {
                guard previousWasEmpty == false, result.isEmpty == false else { continue }
                previousWasEmpty = true
                result.append(line)
            } else {
                previousWasEmpty = false
                result.append(line)
            }
        }

        return result
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
