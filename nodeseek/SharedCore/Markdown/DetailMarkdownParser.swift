import Foundation
import Kanna
import Markdown

nonisolated struct DetailMarkdownParser: Sendable {
    typealias Block = DetailDocument.Block
    typealias Inline = DetailDocument.Inline
    typealias Style = DetailDocument.Style
    let baseURL: URL
    var mediaURLs: [URL: URL] = [:]
    /// 网页 linkify 生成的无协议域名链接，按显示文字索引。
    private var fuzzyLinks: [String: URL] = [:]

    nonisolated private enum ParseError: Error { case unsupported }

    func render(_ source: DetailFloorSource) -> DetailDocumentResult {
        guard let markdown = source.visibleMarkdown, !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let blocks = try? withFuzzyLinks(from: source.html).parseContainers(markdown, html: source.html), !blocks.isEmpty else { return .webpage(html: source.html) }
        return .native(DetailDocument(blocks: blocks))
    }

    // 网页 linkify 还会把 ping.nodeseek.com 这类不带协议的域名转成链接，判定依赖顶级域名表。
    // 直接沿用本楼网页已生成的这些链接，不自行猜测，避免把 README.md 之类误判为链接。
    private static let fuzzyAnchor = try! NSRegularExpression(pattern: #"<a href="/jump\?to=([^"]+)"[^>]*>([^<&]+)</a>"#)

    private func withFuzzyLinks(from html: String) -> Self {
        guard html.contains("/jump?to=") else { return self }
        var parser = self
        let string = html as NSString
        for match in Self.fuzzyAnchor.matches(in: html, range: NSRange(location: 0, length: string.length)) {
            let label = string.substring(with: match.range(at: 2))
            // 只认显示文字就是去掉协议后的地址的链接；[地址](https://…) 这类自定义文字不算。
            guard let target = string.substring(with: match.range(at: 1)).removingPercentEncoding,
                  let scheme = target.range(of: "://"), target[scheme.upperBound...] == label,
                  let url = destination(target) else { continue }
            parser.fuzzyLinks[label] = url
        }
        return parser
    }

    // 仅在独立行识别站点容器。围栏内的冒号（包括与结束符相同的整行）属于代码。
    // 容器外出现站点未识别的 ::: 行（例如外部博客搬运的 :::note）时，以网页正文是否原样保留为依据决定按普通文字解析还是回退网页。
    private func parseContainers(_ markdown: String, html: String) throws -> [Block] {
        guard markdown.contains(":::") else { return try ordinary(markdown) }
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var result: [Block] = []
        var buffer: [String] = []
        var tabs: [DetailDocument.Tab]?
        var title: String?
        var fence: (Character, Int)?
        var plainHTMLText: String?
        for line in lines {
            let marker = line.trimmingCharacters(in: .whitespaces)
            let indent = line.prefix(while: { $0 == " " }).count
            let atBoundary = indent <= 3 && !line.hasPrefix("\t")
            if let active = fence {
                buffer.append(line)
                if atBoundary && marker.count >= active.1 && marker.allSatisfy({ $0 == active.0 }) { fence = nil }
                continue
            }
            if atBoundary, let char = marker.first, char == "`" || char == "~" {
                let count = marker.prefix(while: { $0 == char }).count
                if count >= 3 && (char != "`" || !marker.dropFirst(count).contains("`")) { fence = (char, count) }
            }
            guard atBoundary && marker.hasPrefix(":::") else { buffer.append(line); continue }
            switch marker {
            case ":::: tabs" where tabs == nil:
                result += try ordinary(buffer.joined(separator: "\n"))
                tabs = []
            case _ where marker.hasPrefix("::: tab-item ") && tabs != nil && title == nil:
                guard buffer.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) else { throw ParseError.unsupported }
                title = String(marker.dropFirst("::: tab-item ".count))
            case ":::" where title != nil:
                guard let currentTitle = title else { throw ParseError.unsupported }
                tabs?.append(.init(title: currentTitle, blocks: try ordinary(buffer.joined(separator: "\n"))))
                title = nil
            case "::::" where tabs != nil && title == nil:
                guard let complete = tabs, !complete.isEmpty,
                      buffer.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) else { throw ParseError.unsupported }
                result.append(.tabs(complete))
                tabs = nil
            default:
                guard tabs == nil, isLiteralContainerLine(marker, in: html, cachedPlainText: &plainHTMLText) else { throw ParseError.unsupported }
                buffer.append(line)
                continue
            }
            buffer.removeAll(keepingCapacity: true)
        }
        guard tabs == nil else { throw ParseError.unsupported }
        return result + (try ordinary(buffer.joined(separator: "\n")))
    }

    /// 网页未把该 `:::` 行当作容器消费时，其非代码正文里会保留开头的字面标记。
    private func isLiteralContainerLine(_ marker: String, in html: String, cachedPlainText: inout String?) -> Bool {
        if html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        let plainText: String
        if let cached = cachedPlainText {
            plainText = cached
        } else {
            let extracted = Self.nonCodeText(from: html)
            cachedPlainText = extracted
            plainText = extracted
        }
        return plainText.contains(Self.containerLiteralPrefix(of: marker))
    }

    private static func nonCodeText(from html: String) -> String {
        guard let document = try? HTML(html: "<body>\(html)</body>", encoding: .utf8),
              let body = document.body else { return "" }
        for element in body.xpath(".//pre | .//code | .//script | .//style").reversed() {
            element.parent?.removeChild(element)
        }
        return body.text ?? ""
    }

    /// 提取连续冒号及紧随其后的容器名（如 `:::note[关于协议]` → `:::note`），避免行内样式或实体转义影响比对。
    private static func containerLiteralPrefix(of marker: String) -> String {
        let colons = marker.prefix(while: { $0 == ":" })
        let afterColons = marker.dropFirst(colons.count)
        let spaces = afterColons.prefix(while: { $0 == " " || $0 == "\t" })
        let rest = afterColons.dropFirst(spaces.count)
        let name = rest.prefix(while: { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        return name.isEmpty ? String(colons) : String(colons) + String(spaces) + String(name)
    }

    private func ordinary(_ markdown: String) throws -> [Block] {
        try Document(parsing: markdown, options: [.disableSmartOpts]).children.flatMap(blocks)
    }

    private func blocks(_ node: Markup) throws -> [Block] {
        switch node {
        case is Paragraph:
            return try inlineBlocks(node)
        case let heading as Heading:
            return [.heading(min(6, heading.level + 1), try inlineOnly(node))]
        case is BlockQuote:
            return [.quote(try node.children.flatMap(blocks))]
        case is UnorderedList, is OrderedList:
            let items = try node.children.map { item in
                guard let item = item as? ListItem, item.checkbox == nil else { throw ParseError.unsupported }
                return try item.children.flatMap(blocks)
            }
            return [.list(start: (node as? OrderedList).map { Int($0.startIndex) }, items: items)]
        case let table as Table:
            let rows = [table.head as Markup] + Array(table.body.children)
            return [.table(rows: try rows.map { try $0.children.map(tableCell) })]
        case let code as CodeBlock:
            return code.language?.lowercased() == "ansi" ? [.terminal(code.code)] : [.code(language: code.language, text: code.code)]
        case let html as HTMLBlock:
            let raw = html.rawHTML.trimmingCharacters(in: .newlines)
            guard isLiteralHTML(raw) else { throw ParseError.unsupported }
            return [.paragraph([.text(raw, [], nil)])]
        case is ThematicBreak: return [.divider]
        default: throw ParseError.unsupported
        }
    }

    nonisolated private enum Piece {
        case inline(Inline)
        case block(Block)
    }

    private func tableCell(_ cell: Markup) throws -> DetailDocument.TableCell {
        let content = try inlineChildren(cell).flatMap { try pieces($0) }
        if content.count == 1, case .block(.image(_, let url)) = content[0] {
            return .image(url)
        }
        let runs = try content.map { piece in
            guard case .inline(let run) = piece else { throw ParseError.unsupported }
            if case .sticker = run, content.count > 1 { throw ParseError.unsupported }
            return run
        }
        return .inline(runs)
    }

    private func inlineOnly(_ parent: Markup) throws -> [Inline] {
        try inlineChildren(parent).flatMap { try pieces($0) }.map {
            guard case .inline(let value) = $0 else { throw ParseError.unsupported }
            return value
        }
    }

    private func inlineBlocks(_ parent: Markup) throws -> [Block] {
        var result: [Block] = []
        var run: [Inline] = []
        // 图片等块把段落切开后，切口处的换行不再有意义；保留会形成只有换行的空段，图片之间多出一大段空白。
        func flush() {
            while case let .text(text, style, link)? = run.first, text.first == "\n" {
                let rest = String(text.drop { $0 == "\n" })
                if rest.isEmpty { run.removeFirst() } else { run[0] = .text(rest, style, link) }
            }
            while case let .text(text, style, link)? = run.last, text.last == "\n" {
                var rest = text
                while rest.last == "\n" { rest.removeLast() }
                if rest.isEmpty { run.removeLast() } else { run[run.count - 1] = .text(rest, style, link) }
            }
            if !run.isEmpty { result.append(.paragraph(run)) }
            run.removeAll(keepingCapacity: true)
        }
        for child in try inlineChildren(parent) {
            for piece in try pieces(child) {
                switch piece {
                case .inline(let inline): run.append(inline)
                case .block(let block):
                    flush()
                    result.append(block)
                }
            }
        }
        flush()
        return result
    }

    // cmark-gfm 也把单波浪号当删除线，网页只认 ~~文字~~。单波浪号展开回原文并与相邻文字合并，
    // 让分享口令、裸链接和表情代码保持完整，后续按同一段文字识别。
    private func inlineChildren(_ parent: Markup) throws -> [Markup] {
        var result: [Markup] = []
        func append(_ node: Markup) {
            if let text = node as? Markdown.Text, let last = result.last as? Markdown.Text {
                result[result.count - 1] = Markdown.Text(last.string + text.string)
            } else {
                result.append(node)
            }
        }
        for child in parent.children {
            guard let strike = child as? Strikethrough, try isSingleTilde(strike) else { append(child); continue }
            append(Markdown.Text("~"))
            try inlineChildren(strike).forEach(append)
            append(Markdown.Text("~"))
        }
        return result
    }

    // 开始标记到首个子节点的列差就是波浪号个数。
    private func isSingleTilde(_ strike: Strikethrough) throws -> Bool {
        guard let opener = strike.range?.lowerBound, let content = strike.child(at: 0)?.range?.lowerBound,
              opener.line == content.line else { throw ParseError.unsupported }
        return content.column - opener.column == 1
    }

    private func pieces(_ node: Markup, style: Style = [], link: URL? = nil) throws -> [Piece] {
        var style = style
        var link = link
        switch node {
        case let text as Markdown.Text: return try tokenize(text.string, style: style, link: link)
        case is SoftBreak, is LineBreak: return [.inline(.text("\n", style, link))]
        case let code as InlineCode: return [.inline(.text(code.code, style.union(.code), link))]
        case is Strong: style.insert(.bold)
        case is Emphasis: style.insert(.italic)
        case is Strikethrough: style.insert(.strike)
        case let image as Markdown.Image:
            guard link == nil else { throw ParseError.unsupported }
            // 网页对无效地址同样显示加载失败，不必为此整楼退回网页渲染。
            guard let url = destination(image.source) else { return [.block(.brokenImage(alt: image.plainText))] }
            return [.block(.image(alt: image.plainText, url: mediaURLs[url] ?? url))]
        case let anchor as Markdown.Link:
            if let raw = anchor.destination, let url = URL(string: raw), let id = NodeSeekVoteParser.voteID(in: url) {
                return [.block(.vote(id))]
            }
            guard let url = destination(anchor.destination) else { throw ParseError.unsupported }
            link = url
        case let html as InlineHTML where isLiteralHTML(html.rawHTML):
            return [.inline(.text(html.rawHTML, style, link))]
        default: throw ParseError.unsupported
        }
        return try inlineChildren(node).flatMap { try pieces($0, style: style, link: link) }
    }

    // 网页在正文及表格中把这些标记转义为可见文字。
    private func isLiteralHTML(_ raw: String) -> Bool {
        raw.lowercased() == "<br>" || (raw.hasPrefix("<!--") && raw.hasSuffix("-->"))
    }

    private func destination(_ raw: String?) -> URL? {
        // UTF-8 字节初始化保留已有的 %XX，同时转义裸字符，避免混合输入被二次编码。
        guard let raw, !raw.isEmpty,
              let url = URL(dataRepresentation: Data(raw.utf8), relativeTo: baseURL)?.absoluteURL,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host, !host.isEmpty else { return nil }
        // 重新设置解码后的主机名，使无效主机不能借由百分号编码成为跳转目标。
        components.host = host
        return components.url
    }

    private static let token = try! NSRegularExpression(pattern: #"https?://[^\s<>]+|nsapp://[^\s<>]+|:[A-Za-z][A-Za-z0-9]+:|(?<![\p{L}\p{N}_])@[\p{L}\p{N}_-]+"#)

    /// 与网页 linkify 一致：主机名遇到标点（含全角）即结束；路径末尾的句读和不成对的右括号不算链接。
    private static func linkifiedLength(_ token: String) -> Int {
        let units = Array(token.utf16)
        let schemeEnd = (token as NSString).range(of: "://").upperBound
        let punctuation: Set<Unicode.GeneralCategory> = [.connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
                                                         .initialPunctuation, .finalPunctuation, .otherPunctuation]
        var end = units.count
        var position = 0
        for scalar in token.unicodeScalars {
            defer { position += UTF16.width(scalar) }
            guard position >= schemeEnd else { continue }
            if "/?#".unicodeScalars.contains(scalar) { break }
            if scalar.value > 0x7F, punctuation.contains(scalar.properties.generalCategory) { end = position; break }
        }
        let closing: [UInt16: UInt16] = [41: 40, 93: 91, 125: 123]
        while end > schemeEnd {
            let last = units[end - 1]
            if ".,;:!?'\"-".utf16.contains(last) { end -= 1; continue }
            if let open = closing[last], units[..<end].filter({ $0 == open }).count < units[..<end].filter({ $0 == last }).count { end -= 1; continue }
            break
        }
        return end
    }

    private func tokenize(_ text: String, style: Style, link: URL?) throws -> [Piece] {
        guard link == nil else { return [.inline(.text(text, style, link))] }
        let string = text as NSString
        var result: [Piece] = []
        var offset = 0
        // 逐个查找：裸链接截掉的尾部要重新参与匹配，里面可能还有 @ 或表情。
        while let match = Self.token.firstMatch(in: text, range: NSRange(location: offset, length: string.length - offset)) {
            if match.range.location > offset {
                result += plain(string.substring(with: NSRange(location: offset, length: match.range.location-offset)), style: style)
            }
            var range = match.range
            if string.substring(with: range).hasPrefix("http") { range.length = Self.linkifiedLength(string.substring(with: range)) }
            let token = string.substring(with: range)
            if token.hasPrefix("nsapp://") {
                guard let url = URL(string: token), let id = NodeSeekVoteParser.voteID(in: url) else { throw ParseError.unsupported }
                result.append(.block(.vote(id)))
            } else if token.first == ":", let url = NodeSeekStickerLibrary.urlsByToken[String(token.dropFirst().dropLast())] {
                result.append(.inline(.sticker(token: token, url: mediaURLs[url] ?? url)))
            } else if token.first == "@" {
                var member = URLComponents(url: baseURL.appendingPathComponent("member"), resolvingAgainstBaseURL: true)
                member?.queryItems = [URLQueryItem(name: "t", value: String(token.dropFirst()))]
                result.append(.inline(.text(token, style, member?.url)))
            } else {
                let url = token.hasPrefix("http") ? destination(token) : nil
                result.append(.inline(.text(token, style, url)))
            }
            offset = NSMaxRange(range)
        }
        if offset < string.length { result += plain(string.substring(from: offset), style: style) }
        return result
    }

    /// 普通文字里补上网页已识别的无协议域名链接；前后紧邻字母、数字、点或连字符时不算。
    private func plain(_ text: String, style: Style) -> [Piece] {
        guard !fuzzyLinks.isEmpty, !style.contains(.code) else { return [.inline(.text(text, style, nil))] }
        let labels = fuzzyLinks.keys.sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern(for:))
        guard let pattern = try? NSRegularExpression(pattern: "(?<![A-Za-z0-9.-])(?:" + labels.joined(separator: "|") + ")(?![A-Za-z0-9-])") else {
            return [.inline(.text(text, style, nil))]
        }
        let string = text as NSString
        var result: [Piece] = []
        var offset = 0
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: string.length)) {
            if match.range.location > offset {
                result.append(.inline(.text(string.substring(with: NSRange(location: offset, length: match.range.location - offset)), style, nil)))
            }
            let label = string.substring(with: match.range)
            result.append(.inline(.text(label, style, fuzzyLinks[label])))
            offset = NSMaxRange(match.range)
        }
        if offset < string.length { result.append(.inline(.text(string.substring(from: offset), style, nil))) }
        return result
    }
}
