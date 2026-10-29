//
//  MarkdownPreviewHTMLRenderer.swift
//  nodeseek
//

import Foundation

/// 发帖预览：把正文 Markdown 转成和站点帖子结构接近的 HTML，再交给详情页现有渲染器。
/// 只覆盖帖子常用语法，规则向站点 markdown-it（开启换行转 <br>）看齐。
nonisolated enum MarkdownPreviewHTMLRenderer {
    /// 表情标记 `:yct015:` 对应的图片地址；返回 nil 时按普通文字保留。
    typealias StickerURLResolver = (String) -> URL?

    static func html(from markdown: String, stickerURL: StickerURLResolver = { _ in nil }) -> String {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        return renderBlocks(lines[...], stickerURL: stickerURL)
    }

    // MARK: - 块级

    private static func renderBlocks(_ lines: ArraySlice<String>, stickerURL: StickerURLResolver) -> String {
        var output: [String] = []
        var paragraph: [String] = []
        var index = lines.startIndex

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            output.append("<p>" + paragraph.map { renderInline($0, stickerURL: stickerURL) }.joined(separator: "<br>") + "</p>")
            paragraph.removeAll()
        }

        while index < lines.endIndex {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flushParagraph()
                let fence = String(trimmed.prefix(3))
                let language = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                index += 1
                while index < lines.endIndex, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    code.append(lines[index])
                    index += 1
                }
                index += 1
                let classAttribute = language.isEmpty ? "" : " class=\"language-\(escape(language))\""
                output.append("<pre><code\(classAttribute)>\(escape(code.joined(separator: "\n")))</code></pre>")
                continue
            }

            if let heading = headingLevel(of: trimmed) {
                flushParagraph()
                let text = trimmed.dropFirst(heading + 1).trimmingCharacters(in: .whitespaces)
                output.append("<h\(heading)>\(renderInline(text, stickerURL: stickerURL))</h\(heading)>")
                index += 1
                continue
            }

            if isHorizontalRule(trimmed) {
                flushParagraph()
                output.append("<hr>")
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quoted: [String] = []
                while index < lines.endIndex {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard candidate.hasPrefix(">") else { break }
                    var inner = candidate.dropFirst()
                    if inner.first == " " { inner = inner.dropFirst() }
                    quoted.append(String(inner))
                    index += 1
                }
                output.append("<blockquote>\(renderBlocks(quoted[...], stickerURL: stickerURL))</blockquote>")
                continue
            }

            if let firstItem = listItem(trimmed) {
                flushParagraph()
                var items: [String] = []
                while index < lines.endIndex, let item = listItem(lines[index].trimmingCharacters(in: .whitespaces)),
                      item.ordered == firstItem.ordered {
                    items.append("<li>\(renderInline(item.text, stickerURL: stickerURL))</li>")
                    index += 1
                }
                let tag = firstItem.ordered ? "ol" : "ul"
                output.append("<\(tag)>\(items.joined())</\(tag)>")
                continue
            }

            if trimmed.contains("|"),
               index + 1 < lines.endIndex,
               isTableSeparator(lines[index + 1].trimmingCharacters(in: .whitespaces)) {
                flushParagraph()
                var rows = ["<tr>" + tableCells(trimmed).map { "<th>\(renderInline($0, stickerURL: stickerURL))</th>" }.joined() + "</tr>"]
                index += 2
                while index < lines.endIndex {
                    let row = lines[index].trimmingCharacters(in: .whitespaces)
                    guard !row.isEmpty, row.contains("|") else { break }
                    rows.append("<tr>" + tableCells(row).map { "<td>\(renderInline($0, stickerURL: stickerURL))</td>" }.joined() + "</tr>")
                    index += 1
                }
                output.append("<table>\(rows.joined())</table>")
                continue
            }

            paragraph.append(trimmed)
            index += 1
        }
        flushParagraph()
        return output.joined(separator: "\n")
    }

    private static func headingLevel(of line: String) -> Int? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private static func listItem(_ line: String) -> (ordered: Bool, text: String)? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return (false, String(line.dropFirst(marker.count)))
        }
        let digits = line.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return (true, String(rest.dropFirst(2)))
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let cells = tableCells(line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let core = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return !core.isEmpty && core.allSatisfy { $0 == "-" }
        }
    }

    private static func tableCells(_ line: String) -> [String] {
        var row = line
        if row.hasPrefix("|") { row.removeFirst() }
        if row.hasSuffix("|") { row.removeLast() }
        return row.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: - 行内

    /// 先把行内代码、图片、链接换成占位，避免后续粗体等规则误伤其中内容。
    private static func renderInline(_ text: String, stickerURL: StickerURLResolver) -> String {
        var stash: [String] = []
        func stashed(_ html: String) -> String {
            stash.append(html)
            return "\u{0}\(stash.count - 1)\u{0}"
        }

        var result = text
        result = replace(#"`([^`]+)`"#, in: result) { groups in
            stashed("<code>\(escape(groups[1]))</code>")
        }
        result = replace(#"!\[([^\]]*)\]\(([^)\s]+)\)"#, in: result) { groups in
            if groups[2].hasPrefix("uploading:") {
                return stashed("<em>（图片上传中）</em>")
            }
            return stashed("<img src=\"\(escape(groups[2]))\" alt=\"\(escape(groups[1]))\">")
        }
        result = replace(#"\[([^\]]+)\]\(([^)\s]+)\)"#, in: result) { groups in
            stashed("<a href=\"\(escape(groups[2]))\">\(escape(groups[1]))</a>")
        }
        result = replace(#"https?://[^\s<>\x{0}]+"#, in: result) { groups in
            stashed("<a href=\"\(escape(groups[0]))\">\(escape(groups[0]))</a>")
        }
        result = replace(#":([a-z]+[0-9A-Za-z_-]*):"#, in: result) { groups in
            guard let url = stickerURL(groups[1]) else { return groups[0] }
            return stashed("<img class=\"sticker\" src=\"\(escape(url.absoluteString))\" alt=\"\(escape(groups[1]))\">")
        }

        result = escape(result)
        result = replace(#"\*\*(.+?)\*\*"#, in: result) { "<strong>\($0[1])</strong>" }
        result = replace(#"__(.+?)__"#, in: result) { "<strong>\($0[1])</strong>" }
        result = replace(#"~~(.+?)~~"#, in: result) { "<del>\($0[1])</del>" }
        result = replace(#"(?<![*\w])\*(?!\s)(.+?)(?<!\s)\*(?!\*)"#, in: result) { "<em>\($0[1])</em>" }

        for (index, html) in stash.enumerated().reversed() {
            result = result.replacingOccurrences(of: "\u{0}\(index)\u{0}", with: html)
        }
        return result
    }

    private static func replace(_ pattern: String, in text: String, with transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let source = text as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            result += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let groups = (0..<match.numberOfRanges).map { index -> String in
                let range = match.range(at: index)
                return range.location == NSNotFound ? "" : source.substring(with: range)
            }
            result += transform(groups)
            cursor = NSMaxRange(match.range)
        }
        result += source.substring(from: cursor)
        return result
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
