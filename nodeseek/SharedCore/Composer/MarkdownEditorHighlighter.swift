//
//  MarkdownEditorHighlighter.swift
//  nodeseek
//

import Foundation

nonisolated enum MarkdownEditorStyle: Equatable, Sendable {
    /// `#`、`-`、`**`、`` ` `` 这类语法符号，界面上变淡。
    case marker
    /// 标题行的文字，只加粗、不改字号。
    case heading
    case bold
    case italic
    case strikethrough
    case inlineCode
    case codeBlock
    case quote
    case link
    /// 整条 `![](url)`，界面上变淡。
    case image
}

nonisolated struct MarkdownEditorHighlight: Equatable, Sendable {
    /// UTF-16 区间，直接用于 `NSTextStorage`。
    let range: NSRange
    let style: MarkdownEditorStyle
}

/// 发帖编辑器的轻量 Markdown 高亮：逐行扫描常用语法，只产出样式区间，不改文字。
/// 半截语法（比如只打了一个 `**`）不会被识别，避免输入过程中样式来回跳。
nonisolated enum MarkdownEditorHighlighter {
    static func highlights(in text: String) -> [MarkdownEditorHighlight] {
        let source = text as NSString
        var result: [MarkdownEditorHighlight] = []
        var insideFence = false
        var location = 0

        while location < source.length {
            var lineEnd = 0
            var contentsEnd = 0
            source.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            let lineRange = NSRange(location: location, length: contentsEnd - location)
            let line = source.substring(with: lineRange)

            if line.hasPrefix("```") {
                result.append(.init(range: lineRange, style: .marker))
                insideFence.toggle()
            } else if insideFence {
                if lineRange.length > 0 {
                    result.append(.init(range: lineRange, style: .codeBlock))
                }
            } else {
                result += lineHighlights(line, offset: location)
            }
            location = lineEnd
        }
        return result
    }

    // MARK: - 块级

    private static let headingPattern = try! NSRegularExpression(pattern: #"^(#{1,6} )(.*)$"#)
    private static let quotePattern = try! NSRegularExpression(pattern: #"^(> ?)(.*)$"#)
    private static let listPattern = try! NSRegularExpression(pattern: #"^(\s*(?:[-*+]|\d+\.) )"#)
    private static let rulePattern = try! NSRegularExpression(pattern: #"^\s*(?:-{3,}|\*{3,}|_{3,})\s*$"#)
    private static let tablePipePattern = try! NSRegularExpression(pattern: #"\|"#)

    private static func lineHighlights(_ line: String, offset: Int) -> [MarkdownEditorHighlight] {
        let length = (line as NSString).length
        let full = NSRange(location: 0, length: length)
        var result: [MarkdownEditorHighlight] = []
        var contentStart = 0

        if rulePattern.firstMatch(in: line, range: full) != nil {
            return [.init(range: NSRange(location: offset, length: length), style: .marker)]
        }
        if let match = headingPattern.firstMatch(in: line, range: full) {
            result.append(.init(range: shifted(match.range(at: 1), by: offset), style: .marker))
            if match.range(at: 2).length > 0 {
                result.append(.init(range: shifted(match.range(at: 2), by: offset), style: .heading))
            }
            contentStart = match.range(at: 2).location
        } else if let match = quotePattern.firstMatch(in: line, range: full) {
            result.append(.init(range: shifted(match.range(at: 1), by: offset), style: .marker))
            if match.range(at: 2).length > 0 {
                result.append(.init(range: shifted(match.range(at: 2), by: offset), style: .quote))
            }
            contentStart = match.range(at: 2).location
        } else if let match = listPattern.firstMatch(in: line, range: full) {
            result.append(.init(range: shifted(match.range(at: 1), by: offset), style: .marker))
            contentStart = match.range(at: 1).length
        } else if line.trimmingCharacters(in: .whitespaces).hasPrefix("|") {
            for match in tablePipePattern.matches(in: line, range: full) {
                result.append(.init(range: shifted(match.range, by: offset), style: .marker))
            }
        }

        let contentRange = NSRange(location: contentStart, length: length - contentStart)
        result += inlineHighlights(line, in: contentRange, offset: offset)
        return result
    }

    // MARK: - 行内

    private static let inlineCodePattern = try! NSRegularExpression(pattern: #"(`)([^`]+)(`)"#)
    private static let imagePattern = try! NSRegularExpression(pattern: #"!\[[^\]]*\]\([^)\s]*\)"#)
    private static let linkPattern = try! NSRegularExpression(pattern: #"(\[)([^\]]+)(\]\([^)\s]+\))"#)
    private static let boldPattern = try! NSRegularExpression(pattern: #"(\*\*)(?=\S)(.+?)(?<=\S)(\*\*)"#)
    private static let strikePattern = try! NSRegularExpression(pattern: #"(~~)(?=\S)(.+?)(?<=\S)(~~)"#)
    private static let italicPattern = try! NSRegularExpression(pattern: #"(?<![*\w])(\*)(?=[^\s*])([^*]+?)(?<=[^\s*])(\*)(?![*\w])"#)

    private static func inlineHighlights(_ line: String, in range: NSRange, offset: Int) -> [MarkdownEditorHighlight] {
        var result: [MarkdownEditorHighlight] = []
        // 行内代码和图片里的内容不再参与其他语法。
        var taken: [NSRange] = []

        for match in inlineCodePattern.matches(in: line, range: range) {
            result.append(.init(range: shifted(match.range(at: 1), by: offset), style: .marker))
            result.append(.init(range: shifted(match.range(at: 2), by: offset), style: .inlineCode))
            result.append(.init(range: shifted(match.range(at: 3), by: offset), style: .marker))
            taken.append(match.range)
        }
        for match in imagePattern.matches(in: line, range: range) where !overlaps(match.range, taken) {
            result.append(.init(range: shifted(match.range, by: offset), style: .image))
            taken.append(match.range)
        }
        for match in linkPattern.matches(in: line, range: range) where !overlaps(match.range, taken) {
            result.append(.init(range: shifted(match.range(at: 1), by: offset), style: .marker))
            result.append(.init(range: shifted(match.range(at: 2), by: offset), style: .link))
            result.append(.init(range: shifted(match.range(at: 3), by: offset), style: .marker))
        }
        for (pattern, style) in [(boldPattern, MarkdownEditorStyle.bold), (strikePattern, .strikethrough), (italicPattern, .italic)] {
            for match in pattern.matches(in: line, range: range) where !overlaps(match.range, taken) {
                result.append(.init(range: shifted(match.range(at: 1), by: offset), style: .marker))
                result.append(.init(range: shifted(match.range(at: 2), by: offset), style: style))
                result.append(.init(range: shifted(match.range(at: 3), by: offset), style: .marker))
            }
        }
        return result
    }

    private static func overlaps(_ range: NSRange, _ ranges: [NSRange]) -> Bool {
        ranges.contains { NSIntersectionRange($0, range).length > 0 }
    }

    private static func shifted(_ range: NSRange, by offset: Int) -> NSRange {
        NSRange(location: range.location + offset, length: range.length)
    }
}
