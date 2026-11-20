import Foundation
import Markdown

nonisolated struct DetailMarkdownParser: Sendable {
    typealias Block = DetailDocument.Block
    typealias Inline = DetailDocument.Inline
    typealias Style = DetailDocument.Style
    let baseURL: URL

    nonisolated private enum ParseError: Error { case unsupported }

    func render(_ source: DetailFloorSource) -> DetailDocumentResult {
        guard let markdown = source.visibleMarkdown, !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let blocks = try? parseContainers(markdown), !blocks.isEmpty else { return .webpage(html: source.html) }
        return .native(DetailDocument(blocks: blocks))
    }

    // 仅在独立行识别站点容器。围栏内的冒号（包括与结束符相同的整行）属于代码。
    private func parseContainers(_ markdown: String) throws -> [Block] {
        guard markdown.contains(":::") else { return try ordinary(markdown) }
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var result: [Block] = []
        var buffer: [String] = []
        var tabs: [DetailDocument.Tab]?
        var title: String?
        var fence: (Character, Int)?
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
            case ":::":
                guard let currentTitle = title else { throw ParseError.unsupported }
                tabs?.append(.init(title: currentTitle, blocks: try ordinary(buffer.joined(separator: "\n"))))
                title = nil
            case "::::" where title == nil:
                guard let complete = tabs, !complete.isEmpty,
                      buffer.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) else { throw ParseError.unsupported }
                result.append(.tabs(complete))
                tabs = nil
            default:
                throw ParseError.unsupported
            }
            buffer.removeAll(keepingCapacity: true)
        }
        guard tabs == nil else { throw ParseError.unsupported }
        return result + (try ordinary(buffer.joined(separator: "\n")))
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
            return [.table(rows: try rows.map { row in
                try row.children.map { cell in
                    let runs = try inlineOnly(cell)
                    if runs.contains(where: { if case .sticker = $0 { true } else { false } }), runs.count > 1 {
                        throw ParseError.unsupported
                    }
                    return runs
                }
            })]
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

    private func inlineOnly(_ parent: Markup) throws -> [Inline] {
        try parent.children.flatMap { try pieces($0) }.map {
            guard case .inline(let value) = $0 else { throw ParseError.unsupported }
            return value
        }
    }

    private func inlineBlocks(_ parent: Markup) throws -> [Block] {
        var result: [Block] = []
        var run: [Inline] = []
        for child in parent.children {
            for piece in try pieces(child) {
                switch piece {
                case .inline(let inline): run.append(inline)
                case .block(let block):
                    if !run.isEmpty { result.append(.paragraph(run)); run.removeAll(keepingCapacity: true) }
                    result.append(block)
                }
            }
        }
        if !run.isEmpty { result.append(.paragraph(run)) }
        return result
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
            guard link == nil, let url = destination(image.source) else { throw ParseError.unsupported }
            return [.block(.image(alt: image.plainText, url: url))]
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
        return try node.children.flatMap { try pieces($0, style: style, link: link) }
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

    private func tokenize(_ text: String, style: Style, link: URL?) throws -> [Piece] {
        guard link == nil else { return [.inline(.text(text, style, link))] }
        let string = text as NSString
        var result: [Piece] = []
        var offset = 0
        for match in Self.token.matches(in: text, range: NSRange(location: 0, length: string.length)) {
            if match.range.location > offset {
                result.append(.inline(.text(string.substring(with: NSRange(location: offset, length: match.range.location-offset)), style, nil)))
            }
            let token = string.substring(with: match.range)
            if token.hasPrefix("nsapp://") {
                guard let url = URL(string: token), let id = NodeSeekVoteParser.voteID(in: url) else { throw ParseError.unsupported }
                result.append(.block(.vote(id)))
            } else if token.first == ":", let url = NodeSeekStickerLibrary.urlsByToken[String(token.dropFirst().dropLast())] {
                result.append(.inline(.sticker(token: token, url: url)))
            } else if token.first == "@" {
                var member = URLComponents(url: baseURL.appendingPathComponent("member"), resolvingAgainstBaseURL: true)
                member?.queryItems = [URLQueryItem(name: "t", value: String(token.dropFirst()))]
                result.append(.inline(.text(token, style, member?.url)))
            } else {
                let url = token.hasPrefix("http") ? destination(token) : nil
                result.append(.inline(.text(token, style, url)))
            }
            offset = NSMaxRange(match.range)
        }
        if offset < string.length { result.append(.inline(.text(string.substring(from: offset), style, nil))) }
        return result
    }
}
