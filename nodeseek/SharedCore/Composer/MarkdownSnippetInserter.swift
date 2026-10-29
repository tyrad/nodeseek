//
//  MarkdownSnippetInserter.swift
//  nodeseek
//

import Foundation

/// 发帖工具条和 Aa 面板里的格式动作。
nonisolated enum MarkdownSnippet: Equatable, Sendable {
    case bold
    case italic
    case strikethrough
    case inlineCode
    case link
    case paragraph
    case heading
    case unorderedList
    case orderedList
    case quote
    case codeBlock
    case table
    case horizontalRule
    case image(url: String)
    /// 上传中的图片占位，传完由页面替换成真实地址。
    case uploadingImage(id: String)
}

/// 段落类型，Aa 面板据此高亮当前选中项。
nonisolated enum MarkdownBlockStyle: Equatable, Sendable {
    case paragraph
    case heading
    case codeBlock
    case quote
}

nonisolated struct MarkdownEdit: Equatable, Sendable {
    let text: String
    /// UTF-16 区间，可直接赋给 `UITextView.selectedRange`。
    let selection: NSRange
}

/// 只在文本上插入或去掉 Markdown 语法，不做富文本转换；位置统一用 UTF-16，和 UIKit 选区一致。
nonisolated enum MarkdownSnippetInserter {
    static let headingPrefix = "## "

    static func apply(_ snippet: MarkdownSnippet, to text: String, selection: NSRange) -> MarkdownEdit {
        let source = text as NSString
        let selection = clamped(selection, length: source.length)
        switch snippet {
        case .bold:
            return toggleWrap(marker: "**", in: source, selection: selection)
        case .italic:
            return toggleWrap(marker: "*", in: source, selection: selection)
        case .strikethrough:
            return toggleWrap(marker: "~~", in: source, selection: selection)
        case .inlineCode:
            return toggleWrap(marker: "`", in: source, selection: selection)
        case .link:
            return insertLink(in: source, selection: selection)
        case .paragraph:
            return setLinePrefix(nil, in: source, selection: selection)
        case .heading:
            return toggleLinePrefix(headingPrefix, in: source, selection: selection)
        case .unorderedList:
            return toggleLinePrefix("- ", in: source, selection: selection)
        case .orderedList:
            return toggleLinePrefix("1. ", in: source, selection: selection)
        case .quote:
            return toggleLinePrefix("> ", in: source, selection: selection)
        case .codeBlock:
            return insertCodeBlock(in: source, selection: selection)
        case .table:
            let template = "| 列 1 | 列 2 |\n| --- | --- |\n|  |  |"
            // 光标落在第三行第一个单元格里。
            return insertOnOwnLine(template, caretOffset: (template as NSString).length - 5, in: source, selection: selection)
        case .horizontalRule:
            return insertOnOwnLine("---", caretOffset: 3, in: source, selection: selection)
        case .image(let url):
            let snippet = "![图片](\(url))"
            return insertOnOwnLine(snippet, caretOffset: (snippet as NSString).length, in: source, selection: selection)
        case .uploadingImage(let id):
            let snippet = MarkdownImagePlaceholder.text(id: id)
            return insertOnOwnLine(snippet, caretOffset: (snippet as NSString).length, in: source, selection: selection)
        }
    }

    static func blockStyle(at location: Int, in text: String) -> MarkdownBlockStyle {
        let source = text as NSString
        let location = min(max(0, location), source.length)
        if isInsideFencedCode(location: location, in: source) {
            return .codeBlock
        }
        let line = source.substring(with: source.lineRange(for: NSRange(location: location, length: 0)))
        if line.hasPrefix("#") && line.drop(while: { $0 == "#" }).first == " " {
            return .heading
        }
        if line.hasPrefix(">") {
            return .quote
        }
        return .paragraph
    }

    // MARK: - 行内包裹

    private static func toggleWrap(marker: String, in source: NSString, selection: NSRange) -> MarkdownEdit {
        let markerLength = (marker as NSString).length
        let before = NSRange(location: selection.location - markerLength, length: markerLength)
        let after = NSRange(location: NSMaxRange(selection), length: markerLength)
        if before.location >= 0,
           NSMaxRange(after) <= source.length,
           source.substring(with: before) == marker,
           source.substring(with: after) == marker,
           !isBoldOnlyAsterisks(marker: marker, in: source, selection: selection) {
            // 选区两侧已经有同样的标记：再点一次就去掉。
            let inner = source.substring(with: selection)
            let text = source.replacingCharacters(in: NSRange(location: before.location, length: NSMaxRange(after) - before.location), with: inner)
            return MarkdownEdit(text: text, selection: NSRange(location: before.location, length: selection.length))
        }

        let inner = source.substring(with: selection)
        let text = source.replacingCharacters(in: selection, with: marker + inner + marker)
        return MarkdownEdit(text: text, selection: NSRange(location: selection.location + markerLength, length: selection.length))
    }

    /// `**x**` 两侧的单个星号属于粗体，点斜体应该加成 `***x***` 而不是拆掉粗体。
    /// 星号连续个数为奇数时才算已有斜体。
    private static func isBoldOnlyAsterisks(marker: String, in source: NSString, selection: NSRange) -> Bool {
        guard marker == "*" else { return false }
        let asterisk = ("*" as NSString).character(at: 0)
        var leading = 0
        while selection.location - leading - 1 >= 0, source.character(at: selection.location - leading - 1) == asterisk {
            leading += 1
        }
        var trailing = 0
        while NSMaxRange(selection) + trailing < source.length, source.character(at: NSMaxRange(selection) + trailing) == asterisk {
            trailing += 1
        }
        return leading % 2 == 0 || trailing % 2 == 0
    }

    private static func insertLink(in source: NSString, selection: NSRange) -> MarkdownEdit {
        let label = source.substring(with: selection)
        let snippet = "[\(label)]()"
        let text = source.replacingCharacters(in: selection, with: snippet)
        // 有文字时光标进括号等着粘贴地址；没有文字时先填链接文字。
        let caret = label.isEmpty
            ? selection.location + 1
            : selection.location + (snippet as NSString).length - 1
        return MarkdownEdit(text: text, selection: NSRange(location: caret, length: 0))
    }

    // MARK: - 行首前缀

    private static let blockPrefixPattern = try! NSRegularExpression(pattern: #"^(#{1,6} |> ?|[-*+] |\d+\. )"#)

    private static func toggleLinePrefix(_ prefix: String, in source: NSString, selection: NSRange) -> MarkdownEdit {
        let lines = lineRanges(covering: selection, in: source)
        let allHavePrefix = lines.allSatisfy { source.substring(with: $0).hasPrefix(prefix) }
        return setLinePrefix(allHavePrefix ? nil : prefix, in: source, selection: selection)
    }

    /// 把选区涉及的每一行换成指定前缀（nil 表示去掉块级前缀，变回正文）。
    private static func setLinePrefix(_ prefix: String?, in source: NSString, selection: NSRange) -> MarkdownEdit {
        let lines = lineRanges(covering: selection, in: source)
        let result = NSMutableString(string: source)
        var selectionStart = selection.location
        var selectionEnd = NSMaxRange(selection)
        var shift = 0

        for line in lines {
            let lineStart = line.location + shift
            let lineText = result.substring(with: NSRange(location: lineStart, length: line.length))
            let existing = blockPrefixPattern.firstMatch(
                in: lineText,
                range: NSRange(location: 0, length: (lineText as NSString).length)
            )?.range.length ?? 0
            let replacement = prefix ?? ""
            let replacementLength = (replacement as NSString).length
            result.replaceCharacters(in: NSRange(location: lineStart, length: existing), with: replacement)

            let delta = replacementLength - existing
            let originalLineStart = line.location
            if selection.location >= originalLineStart + existing {
                selectionStart += delta
            } else if selection.location > originalLineStart {
                selectionStart = lineStart + replacementLength
            }
            if NSMaxRange(selection) >= originalLineStart + existing {
                selectionEnd += delta
            } else if NSMaxRange(selection) > originalLineStart {
                selectionEnd = lineStart + replacementLength
            }
            shift += delta
        }

        let start = max(0, selectionStart)
        return MarkdownEdit(
            text: result as String,
            selection: NSRange(location: start, length: max(0, selectionEnd - start))
        )
    }

    /// 选区覆盖到的每一行（不含换行符）；空选区也至少返回光标所在行。
    private static func lineRanges(covering selection: NSRange, in source: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        var location = source.lineRange(for: NSRange(location: selection.location, length: 0)).location
        let end = NSMaxRange(selection)
        repeat {
            var lineEnd = 0
            var contentsEnd = 0
            source.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            ranges.append(NSRange(location: location, length: contentsEnd - location))
            if lineEnd == location { break }
            location = lineEnd
        } while location < end && location < source.length
        return ranges
    }

    // MARK: - 独占一行的片段

    private static func insertCodeBlock(in source: NSString, selection: NSRange) -> MarkdownEdit {
        // 光标已在代码块里时面板会高亮“代码块”，再点一次是取消代码块，而不是再套一层。
        if selection.length == 0, isInsideFencedCode(location: selection.location, in: source) {
            return removeEnclosingFence(around: selection.location, in: source)
        }
        let body = source.substring(with: selection)
        let snippet = "```\n\(body)\n```"
        return insertOnOwnLine(snippet, caretOffset: 4 + (body as NSString).length, in: source, selection: selection)
    }

    /// 去掉光标所在代码块的开头和结尾两行 ``` 标记，代码内容保留。
    private static func removeEnclosingFence(around location: Int, in source: NSString) -> MarkdownEdit {
        let lineAtCaret = source.lineRange(for: NSRange(location: location, length: 0))
        // 光标停在开头那行 ``` 的末尾时，这一行本身就是开头。
        var opening: NSRange? = source.substring(with: lineAtCaret).hasPrefix("```") ? lineAtCaret : nil
        var lineStart = lineAtCaret.location
        while opening == nil, lineStart > 0 {
            let line = source.lineRange(for: NSRange(location: lineStart - 1, length: 0))
            if source.substring(with: line).hasPrefix("```") {
                opening = line
                break
            }
            lineStart = line.location
        }
        guard let opening else { return MarkdownEdit(text: source as String, selection: NSRange(location: location, length: 0)) }

        var closing: NSRange?
        var next = opening == lineAtCaret ? NSMaxRange(lineAtCaret) : lineAtCaret.location
        while next < source.length {
            let line = source.lineRange(for: NSRange(location: next, length: 0))
            if source.substring(with: line).hasPrefix("```") {
                closing = line
                break
            }
            next = NSMaxRange(line)
        }

        let result = NSMutableString(string: source)
        if let closing {
            result.deleteCharacters(in: closing)
        }
        result.deleteCharacters(in: opening)
        return MarkdownEdit(text: result as String, selection: NSRange(location: location - opening.length, length: 0))
    }

    /// 替换选区，并保证片段前后都是换行，不和同一行的文字挤在一起。
    private static func insertOnOwnLine(_ snippet: String, caretOffset: Int, in source: NSString, selection: NSRange) -> MarkdownEdit {
        let needsLeadingBreak = selection.location > 0
            && source.character(at: selection.location - 1) != newline
        let end = NSMaxRange(selection)
        let needsTrailingBreak = end < source.length && source.character(at: end) != newline
        let leading = needsLeadingBreak ? "\n" : ""
        let trailing = needsTrailingBreak ? "\n" : ""
        let text = source.replacingCharacters(in: selection, with: leading + snippet + trailing)
        let caret = selection.location + (leading as NSString).length + caretOffset
        return MarkdownEdit(text: text, selection: NSRange(location: caret, length: 0))
    }

    // MARK: - 工具

    private static let newline = ("\n" as NSString).character(at: 0)

    static func isInsideFencedCode(location: Int, in source: NSString) -> Bool {
        let prefix = source.substring(to: location)
        let fences = prefix.components(separatedBy: "\n").filter { $0.hasPrefix("```") }.count
        return fences % 2 == 1
    }

    private static func clamped(_ range: NSRange, length: Int) -> NSRange {
        let location = min(max(0, range.location), length)
        let end = min(max(location, NSMaxRange(range)), length)
        return NSRange(location: location, length: end - location)
    }
}
