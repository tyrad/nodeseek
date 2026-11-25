import Foundation
import Markdown

/// 从原始 Markdown 提取同帖直接回复关系、裁剪重复父引用，以及生成纯 Markdown 文档（不做 HTML 兜底）。
nonisolated enum CommentReplyRelationParser {
    private struct ParsedLeadingReply {
        let targetFloor: Int?
        let mentionRange: Range<String.Index>
    }

    /// 提取评论的正整数或零楼层号；不把数据库评论 ID 当作楼层号。
    static func floorNumber(for comment: Comment) -> Int? {
        if let anchor = parseFloorDigits(comment.anchorID) {
            return anchor
        }
        return parseFloorDigits(comment.floorText)
    }

    /// 解析评论的直接目标楼层列表（按出现顺序去重，仅包含同帖且早于当前楼的有效目标）。
    static func extractTargets(
        from markdown: String?,
        postID: String,
        currentFloor: Int,
        baseURL: URL = NodeSeekSite.baseURL
    ) -> [Int] {
        guard let markdown, !markdown.isEmpty, currentFloor > 0 else { return [] }
        let normalized = normalizeLineEndings(markdown)
        let document = Document(parsing: normalized, options: [.disableSmartOpts])
        let children = Array(document.children)

        var targets: [Int] = []
        var seen = Set<Int>()
        func appendTarget(_ floor: Int?) {
            guard let floor, seen.insert(floor).inserted else { return }
            targets.append(floor)
        }

        var index = 0
        while index < children.count, let quote = children[index] as? BlockQuote {
            appendTarget(targetFromQuoteBlock(quote, postID: postID, currentFloor: currentFloor, baseURL: baseURL))
            index += 1
        }

        if index < children.count, let paragraph = children[index] as? Paragraph {
            let lineTable = LineOffsetTable(normalized)
            for item in leadingReplyPrefixes(
                in: paragraph,
                source: normalized,
                lineTable: lineTable,
                postID: postID,
                currentFloor: currentFloor,
                baseURL: baseURL
            ) {
                appendTarget(item.targetFloor)
            }
        }

        return targets
    }

    /// 子楼挂在直接父楼下展示时，剥离指向该父楼的前导引用块和回复前缀；若剥离后正文为空则保留原文。
    static func displayMarkdown(
        from markdown: String,
        parentFloor: Int?,
        postID: String,
        currentFloor: Int,
        baseURL: URL = NodeSeekSite.baseURL
    ) -> String {
        guard let parentFloor, currentFloor > 0 else { return markdown }
        let normalized = normalizeLineEndings(markdown)
        let document = Document(parsing: normalized, options: [.disableSmartOpts])
        let children = Array(document.children)
        let lineTable = LineOffsetTable(normalized)

        var rangesToRemove: [Range<String.Index>] = []
        var index = 0
        while index < children.count, let quote = children[index] as? BlockQuote {
            if targetFromQuoteBlock(quote, postID: postID, currentFloor: currentFloor, baseURL: baseURL) == parentFloor,
               let sourceRange = quote.range,
               let range = lineTable.stringRange(for: sourceRange) {
                rangesToRemove.append(expandingTrailingNewlines(range, in: normalized))
            }
            index += 1
        }

        if index < children.count, let paragraph = children[index] as? Paragraph {
            let prefixes = leadingReplyPrefixes(
                in: paragraph,
                source: normalized,
                lineTable: lineTable,
                postID: postID,
                currentFloor: currentFloor,
                baseURL: baseURL
            )
            for item in prefixes where item.targetFloor == parentFloor {
                rangesToRemove.append(expandingTrailingSeparators(item.mentionRange, in: normalized))
            }
        }

        guard !rangesToRemove.isEmpty else { return markdown }
        let merged = mergeRanges(rangesToRemove)
        var stripped = normalized
        for range in merged.reversed() {
            stripped.removeSubrange(range)
        }
        let cleaned = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? markdown : cleaned
    }

    /// 纯 Markdown 文档构造：不走 HTML 兜底，遇到暂不支持的块退化为纯文本段落。
    static func pureMarkdownDocument(
        from markdown: String,
        baseURL: URL = NodeSeekSite.baseURL,
        mediaURLs: [URL: URL] = [:]
    ) -> DetailDocument {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return DetailDocument(blocks: [])
        }
        let source = DetailFloorSource(html: "", visibleMarkdown: markdown)
        switch DetailMarkdownParser(baseURL: baseURL, mediaURLs: mediaURLs).render(source) {
        case .native(let document):
            return document
        case .webpage:
            return DetailDocument(blocks: [.paragraph([.text(trimmed, [], nil)])])
        }
    }

    // MARK: - 内部解析

    private static func targetFromQuoteBlock(
        _ quote: BlockQuote,
        postID: String,
        currentFloor: Int,
        baseURL: URL
    ) -> Int? {
        // 只检查最外层引用块的第一行标准引用头，不递归嵌套引用。
        guard let firstParagraph = quote.children.first(where: { _ in true }) as? Paragraph else {
            return nil
        }
        let firstLineNodes = prefixUpToFirstLineBreak(Array(firstParagraph.children))
        guard !firstLineNodes.isEmpty else { return nil }

        guard let linkIndex = firstLineNodes.firstIndex(where: { $0 is Markdown.Link }),
              let link = firstLineNodes[linkIndex] as? Markdown.Link else {
            return nil
        }

        let beforeLinkText = plainMentionText(from: Array(firstLineNodes[..<linkIndex]))
        guard let beforeLinkText, isSingleLeadingMention(beforeLinkText) else {
            return nil
        }

        // 标准引用头在链接后带「发布于…」或为空白结尾，避免把普通引用文本误判为引用头。
        let afterLinkNodes = Array(firstLineNodes[(linkIndex + 1)...])
        guard let afterText = plainInlineText(from: afterLinkNodes) else { return nil }
        let trimmedAfter = afterText.trimmingCharacters(in: .whitespaces)
        guard trimmedAfter.isEmpty || trimmedAfter.hasPrefix("发布于") else {
            return nil
        }

        return validatedTargetFloor(
            link: link,
            postID: postID,
            currentFloor: currentFloor,
            baseURL: baseURL
        )
    }

    private static func leadingReplyPrefixes(
        in paragraph: Paragraph,
        source: String,
        lineTable: LineOffsetTable,
        postID: String,
        currentFloor: Int,
        baseURL: URL
    ) -> [ParsedLeadingReply] {
        let inlines = Array(paragraph.children)
        var results: [ParsedLeadingReply] = []
        var cursor = 0

        while cursor < inlines.count {
            // 跳过前缀之间的空白文本和换行节点。
            while cursor < inlines.count {
                if inlines[cursor] is SoftBreak || inlines[cursor] is LineBreak {
                    cursor += 1
                    continue
                }
                if let text = inlines[cursor] as? Markdown.Text,
                   text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    cursor += 1
                    continue
                }
                break
            }
            guard cursor < inlines.count else { break }

            // 收集紧邻下一个 Link 前的 @用户名 片段（允许用户名里含下划线等形成 Emphasis）。
            var mentionEnd = cursor
            while mentionEnd < inlines.count {
                let node = inlines[mentionEnd]
                if node is Markdown.Link { break }
                if node is SoftBreak || node is LineBreak || node is InlineCode || node is Image || node is InlineHTML {
                    return results
                }
                mentionEnd += 1
            }

            guard mentionEnd < inlines.count,
                  let link = inlines[mentionEnd] as? Markdown.Link,
                  let prefixText = plainMentionText(from: Array(inlines[cursor..<mentionEnd])),
                  isSingleLeadingMention(prefixText) else {
                break
            }

            // 必须长得像标准楼层链接文字 [#数字] 或 [任意#...]，否则视为普通正文链接并停止采集。
            let linkLabel = link.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard linkLabel.hasPrefix("#") else {
                break
            }

            let target = validatedTargetFloor(
                link: link,
                postID: postID,
                currentFloor: currentFloor,
                baseURL: baseURL
            )

            if let firstRange = inlines[cursor].range,
               let linkRange = link.range,
               let startIndex = lineTable.stringRange(for: firstRange)?.lowerBound,
               let endIndex = lineTable.stringRange(for: linkRange)?.upperBound,
               startIndex < endIndex {
                let trimmedStart = trimLeadingWhitespace(from: startIndex, upperBound: endIndex, in: source)
                results.append(ParsedLeadingReply(targetFloor: target, mentionRange: trimmedStart..<endIndex))
            } else {
                // 没有源码范围时仍记录目标，供建边使用。
                results.append(ParsedLeadingReply(targetFloor: target, mentionRange: source.startIndex..<source.startIndex))
            }

            cursor = mentionEnd + 1

            // Link 后如果紧跟着同一 Text 节点里的空白 + 下一个 @mention，需要支持拆分。
            if cursor < inlines.count, let nextText = inlines[cursor] as? Markdown.Text {
                let trimmedLeading = nextText.string.drop(while: { $0.isWhitespace })
                if trimmedLeading.isEmpty {
                    cursor += 1
                    continue
                }
                if !trimmedLeading.hasPrefix("@") {
                    // 进入普通正文（或标点后正文），停止采集。
                    break
                }
            }
        }

        return results
    }

    private static func validatedTargetFloor(
        link: Markdown.Link,
        postID: String,
        currentFloor: Int,
        baseURL: URL
    ) -> Int? {
        guard let destination = link.destination?.trimmingCharacters(in: .whitespacesAndNewlines),
              !destination.isEmpty,
              let url = URL(string: destination, relativeTo: baseURL),
              let route = NodeSeekPostRouteResolver.route(for: url, baseURL: baseURL),
              route.postID == postID,
              let anchorFloor = parseStrictNonNegativeInt(route.anchorID),
              let labelFloor = parseFloorDigits(link.plainText),
              anchorFloor == labelFloor,
              anchorFloor < currentFloor else {
            return nil
        }
        return anchorFloor
    }

    private static func prefixUpToFirstLineBreak(_ nodes: [Markup]) -> [Markup] {
        var line: [Markup] = []
        for node in nodes {
            if node is SoftBreak || node is LineBreak { break }
            line.append(node)
        }
        return line
    }

    private static func plainMentionText(from nodes: [Markup]) -> String? {
        guard !nodes.isEmpty else { return nil }
        var buffer = ""
        for node in nodes {
            if let text = node as? Markdown.Text {
                buffer += text.string
            } else if let emphasis = node as? Emphasis {
                guard let inner = plainMentionText(from: Array(emphasis.children)) else { return nil }
                buffer += "_\(inner)_"
            } else if let strong = node as? Strong {
                guard let inner = plainMentionText(from: Array(strong.children)) else { return nil }
                buffer += "__\(inner)__"
            } else {
                return nil
            }
        }
        return buffer
    }

    private static func plainInlineText(from nodes: [Markup]) -> String? {
        var buffer = ""
        for node in nodes {
            if let text = node as? Markdown.Text {
                buffer += text.string
            } else if node is SoftBreak || node is LineBreak {
                break
            } else {
                return nil
            }
        }
        return buffer
    }

    /// 匹配单个前导 `@用户名 `（用户名不含空白，末尾至少一个水平空白）。
    private static func isSingleLeadingMention(_ raw: String) -> Bool {
        let strippedLeading = raw.drop(while: { $0 == " " || $0 == "\t" })
        guard strippedLeading.hasPrefix("@") else { return false }
        let afterAt = strippedLeading.dropFirst()
        let username = afterAt.prefix(while: { !$0.isWhitespace })
        guard !username.isEmpty else { return false }
        let tail = afterAt.dropFirst(username.count)
        guard !tail.isEmpty, tail.allSatisfy({ $0 == " " || $0 == "\t" }) else { return false }
        return true
    }

    private static func parseFloorDigits(_ raw: String?) -> Int? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        if text.hasPrefix("#") {
            text.removeFirst()
        }
        return parseStrictNonNegativeInt(text)
    }

    private static func parseStrictNonNegativeInt(_ raw: String?) -> Int? {
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty,
              text.unicodeScalars.allSatisfy({ $0.isASCII && CharacterSet.decimalDigits.contains($0) }) else {
            return nil
        }
        return Int(text)
    }

    private static func normalizeLineEndings(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private static func trimLeadingWhitespace(
        from start: String.Index,
        upperBound: String.Index,
        in source: String
    ) -> String.Index {
        var idx = start
        while idx < upperBound, source[idx].isWhitespace {
            idx = source.index(after: idx)
        }
        return idx
    }

    private static func expandingTrailingNewlines(
        _ range: Range<String.Index>,
        in source: String
    ) -> Range<String.Index> {
        var upper = range.upperBound
        while upper < source.endIndex, source[upper] == " " || source[upper] == "\t" {
            upper = source.index(after: upper)
        }
        while upper < source.endIndex, source[upper] == "\n" {
            upper = source.index(after: upper)
        }
        return range.lowerBound..<upper
    }

    private static func expandingTrailingSeparators(
        _ range: Range<String.Index>,
        in source: String
    ) -> Range<String.Index> {
        var upper = range.upperBound
        while upper < source.endIndex, source[upper] == " " || source[upper] == "\t" {
            upper = source.index(after: upper)
        }
        if upper < source.endIndex, source[upper] == "\n" {
            upper = source.index(after: upper)
        }
        return range.lowerBound..<upper
    }

    private static func mergeRanges(_ ranges: [Range<String.Index>]) -> [Range<String.Index>] {
        let sorted = ranges.filter { !$0.isEmpty }.sorted { $0.lowerBound < $1.lowerBound }
        var merged: [Range<String.Index>] = []
        for range in sorted {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }
}

/// 将 `swift-markdown` 的 1-based 行/UTF-8 列坐标映射回 Swift `String.Index`。
private nonisolated struct LineOffsetTable {
    private let source: String
    private let lineStarts: [String.Index]

    init(_ source: String) {
        self.source = source
        var starts: [String.Index] = [source.startIndex]
        var index = source.startIndex
        while index < source.endIndex {
            if source[index] == "\n" {
                starts.append(source.index(after: index))
            }
            index = source.index(after: index)
        }
        self.lineStarts = starts
    }

    func stringRange(for range: SourceRange) -> Range<String.Index>? {
        guard let lower = index(line: range.lowerBound.line, utf8Column: range.lowerBound.column),
              let upper = index(line: range.upperBound.line, utf8Column: range.upperBound.column),
              lower <= upper else {
            return nil
        }
        return lower..<upper
    }

    private func index(line: Int, utf8Column: Int) -> String.Index? {
        let lineIndex = line - 1
        guard lineIndex >= 0, lineIndex < lineStarts.count else { return nil }
        let lineStart = lineStarts[lineIndex]
        let lineEnd: String.Index = lineIndex + 1 < lineStarts.count ? lineStarts[lineIndex + 1] : source.endIndex
        let targetOffset = max(0, utf8Column - 1)
        let utf8 = source.utf8
        guard let startUTF8 = lineStart.samePosition(in: utf8),
              let endUTF8 = lineEnd.samePosition(in: utf8) else {
            return nil
        }
        let available = utf8.distance(from: startUTF8, to: endUTF8)
        let clampedOffset = min(targetOffset, available)
        let targetUTF8 = utf8.index(startUTF8, offsetBy: clampedOffset)
        return String.Index(targetUTF8, within: source) ?? lineEnd
    }
}
