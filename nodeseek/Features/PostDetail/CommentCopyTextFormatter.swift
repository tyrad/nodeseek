//
//  CommentCopyTextFormatter.swift
//  nodeseek
//
//  Created by Codex on 2026/5/24.
//

import Foundation
import DTCoreText

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

    static func plainText(from blocks: [RenderedContentBlock], includingStickerCodes: Bool = false) -> String {
        normalizedText(blocks.compactMap { text(from: $0, includingStickerCodes: includingStickerCodes) }.joined(separator: "\n"))
    }

    private static func text(from block: RenderedContentBlock, includingStickerCodes: Bool) -> String? {
        switch block {
        case .stardust(let receipt): return receipt.sourceURL.absoluteString
        case .vote(let id):
            return "nsapp://vote?id=\(id)"
        case .text(let attributedText):
            guard includingStickerCodes else { return attributedText.string }
            let text = NSMutableString(string: attributedText.string)
            attributedText.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributedText.length), options: .reverse) { value, range, _ in
                guard let url = (value as? DTTextAttachment)?.contentURL,
                      let token = NodeSeekStickerLibrary.token(for: url) else { return }
                text.replaceCharacters(in: range, with: ":\(token):")
            }
            return text as String
        case .table(let table):
            let rows = table.rows.map { row in
                row.cells.map(\.text).joined(separator: "\t")
            }
            return rows.joined(separator: "\n")
        case .codeBlock(let codeBlock):
            return codeBlock.text
        case .terminal(let terminal):
            return DTCoreTextHTMLContentRenderer().stripANSICodes(from: terminal.ansi)
        case .tabs(let tabs):
            return tabs.sections.map { $0.title + "\n" + plainText(from: $0.blocks, includingStickerCodes: includingStickerCodes) }.joined(separator: "\n")
        case .quote(let quoteBlock):
            return plainText(from: quoteBlock.children, includingStickerCodes: includingStickerCodes)
        case .iframeLink(let iframe):
            return iframe.openURL.absoluteString
        case .image(let image):
            if includingStickerCodes, let token = NodeSeekStickerLibrary.token(for: image.url) { return ":\(token):" }
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
