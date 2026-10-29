//
//  MarkdownListContinuation.swift
//  nodeseek
//

import Foundation

/// 正文里按回车时的列表续行：无序、有序列表和引用自动补标记，空项回车结束列表。
nonisolated enum MarkdownListContinuation {
    private static let patterns: [(regex: NSRegularExpression, kind: Kind)] = [
        (try! NSRegularExpression(pattern: #"^(\s*)(\d+)([.)]) "#), .ordered),
        (try! NSRegularExpression(pattern: #"^(\s*)([-*+]) "#), .unordered),
        (try! NSRegularExpression(pattern: #"^(\s*)(>) ?"#), .quote)
    ]

    private enum Kind {
        case ordered
        case unordered
        case quote
    }

    /// 只处理“光标处插入一个换行”；返回 nil 表示按普通回车处理。
    static func edit(forNewlineAt selection: NSRange, in text: String) -> MarkdownEdit? {
        guard selection.length == 0 else { return nil }
        let source = text as NSString
        let caret = min(max(0, selection.location), source.length)
        guard !MarkdownSnippetInserter.isInsideFencedCode(location: caret, in: source) else { return nil }

        let lineRange = source.lineRange(for: NSRange(location: caret, length: 0))
        let lineStart = lineRange.location
        var lineEnd = NSMaxRange(lineRange)
        if lineEnd > lineStart, source.character(at: lineEnd - 1) == 0x0A { lineEnd -= 1 }
        let line = source.substring(with: NSRange(location: lineStart, length: lineEnd - lineStart))
        let lineNSString = line as NSString

        for (regex, kind) in patterns {
            guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: lineNSString.length)) else { continue }
            let markerEnd = lineStart + match.range.length
            // 光标在标记前面或中间时不续行，按普通回车。
            guard caret >= markerEnd else { return nil }

            let content = lineNSString.substring(from: match.range.length)
            if content.trimmingCharacters(in: .whitespaces).isEmpty {
                // 空项回车：去掉标记，结束列表。
                let updated = source.replacingCharacters(in: NSRange(location: lineStart, length: lineEnd - lineStart), with: "")
                return MarkdownEdit(text: updated, selection: NSRange(location: lineStart, length: 0))
            }

            let indent = lineNSString.substring(with: match.range(at: 1))
            let marker: String
            switch kind {
            case .ordered:
                let number = Int(lineNSString.substring(with: match.range(at: 2))) ?? 0
                marker = "\(indent)\(number + 1)\(lineNSString.substring(with: match.range(at: 3))) "
            case .unordered:
                marker = "\(indent)\(lineNSString.substring(with: match.range(at: 2))) "
            case .quote:
                marker = "\(indent)> "
            }
            let insertion = "\n" + marker
            let updated = source.replacingCharacters(in: NSRange(location: caret, length: 0), with: insertion)
            return MarkdownEdit(text: updated, selection: NSRange(location: caret + (insertion as NSString).length, length: 0))
        }
        return nil
    }
}

/// 链接弹窗：识别光标所在的已有链接，并生成插入或替换后的正文。
nonisolated enum MarkdownLinkEditor {
    struct ExistingLink: Equatable {
        let range: NSRange
        let name: String
        let url: String
    }

    private static let linkPattern = try! NSRegularExpression(pattern: #"(?<!!)\[([^\]\n]*)\]\(([^)\s]*)\)"#)

    /// 选区落在某个 `[名称](地址)` 内时返回它，用来编辑而不是新插入。
    static func existingLink(around selection: NSRange, in text: String) -> ExistingLink? {
        let source = text as NSString
        for match in linkPattern.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            let range = match.range
            guard selection.location >= range.location, NSMaxRange(selection) <= NSMaxRange(range) else { continue }
            return ExistingLink(
                range: range,
                name: source.substring(with: match.range(at: 1)),
                url: source.substring(with: match.range(at: 2))
            )
        }
        return nil
    }

    /// 名称为空时直接用地址当名称，光标放到链接后面。
    static func apply(name: String, url: String, replacing range: NSRange, in text: String) -> MarkdownEdit {
        let source = text as NSString
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let link = "[\(trimmedName.isEmpty ? trimmedURL : trimmedName)](\(trimmedURL))"
        let safeRange = NSRange(location: min(range.location, source.length), length: min(range.length, source.length - min(range.location, source.length)))
        let updated = source.replacingCharacters(in: safeRange, with: link)
        return MarkdownEdit(text: updated, selection: NSRange(location: safeRange.location + (link as NSString).length, length: 0))
    }
}
