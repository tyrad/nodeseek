//
//  DTCoreTextHTMLContentRenderer+Diagnostics.swift
//  nodeseek
//
//  Created by Codex on 2026/4/30.
//

import DTCoreText
import Foundation
import Kanna
import UIKit

extension DTCoreTextHTMLContentRenderer {
    func logDiagnostics(_ message: String) {
        guard NodeSeekDebugConfig.enableDetailRenderDiagnostics else { return }
        AppLog.info(.rendering, message)
    }

    func attachmentDiagnostics(in attributedText: NSAttributedString) -> String {
        guard attributedText.length > 0 else { return "[]" }
        var parts: [String] = []
        attributedText.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributedText.length)
        ) { value, _, _ in
            guard let attachment = value as? DTTextAttachment else { return }
            parts.append(
                "url=\(attachment.contentURL?.absoluteString ?? "nil"),original=\(string(from: attachment.originalSize)),display=\(string(from: attachment.displaySize))"
            )
        }
        if parts.count > 6 {
            return "[\(parts.prefix(6).joined(separator: " | ")) | ... total=\(parts.count)]"
        }
        return "[\(parts.joined(separator: " | "))]"
    }

    func string(from size: CGSize) -> String {
        "\(numberString(size.width))x\(numberString(size.height))"
    }

    func numberString(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }

    func hasClass(_ className: String, in node: XMLElement) -> Bool {
        guard let classes = node.className?.split(whereSeparator: { $0.isWhitespace }) else {
            return false
        }
        return classes.contains { $0 == className }
    }

    func fallbackBlocks(from html: String) -> [RenderedContentBlock] {
        let fallback = html
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? [] : [.text(NSAttributedString(string: fallback))]
    }
}
