import Foundation
import Kanna

/// 站点只输出签名的 HTML，没有 Markdown 原文。签名结构简单，这里直接转成原生块交给 TextKit 排版；
/// 遇到列表、表格、代码等不认识的结构返回 nil，由调用方退回网页渲染。
nonisolated enum DetailSignatureDocument {
    typealias Block = DetailDocument.Block
    typealias Inline = DetailDocument.Inline
    typealias Style = DetailDocument.Style

    private static let blockTags: Set<String> = ["p", "div", "center", "h1", "h2", "h3", "h4", "h5", "h6", "section", "article", "header", "footer"]
    private static let transparentTags: Set<String> = ["span", "font", "small", "big", "u", "ins", "sup", "sub", "label", "abbr", "mark", "body", "html"]

    private struct Unsupported: Error {}

    static func blocks(html: String, baseURL: URL) -> [Block]? {
        guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let document = try? HTML(html: "<body>" + html + "</body>", encoding: .utf8),
              let body = document.body else { return nil }
        var builder = Builder(baseURL: baseURL)
        do {
            try builder.visit(body, style: [], link: nil)
        } catch {
            return nil
        }
        builder.flush()
        // 签名开头的分隔线不显示，只保留内容之后的；否则与正文之间会多出一道线。
        let blocks = Array(builder.blocks.drop { $0 == .divider })
        return blocks.isEmpty ? nil : blocks
    }

    private struct Builder {
        let baseURL: URL
        var blocks: [Block] = []
        var runs: [Inline] = []

        mutating func visit(_ node: Kanna.XMLElement, style: Style, link: URL?) throws {
            for child in node.xpath("node()") {
                guard let name = child.tagName?.lowercased() else { continue }
                switch name {
                case "text":
                    append(child.text ?? "", style: style, link: link)
                case "comment", "script", "style":
                    continue
                case "br":
                    append("\n", style: style, link: nil, preservesNewline: true)
                case "a":
                    try visit(child, style: style, link: destination(child["href"]) ?? link)
                case "strong", "b":
                    try visit(child, style: style.union(.bold), link: link)
                case "em", "i":
                    try visit(child, style: style.union(.italic), link: link)
                case "del", "s", "strike":
                    try visit(child, style: style.union(.strike), link: link)
                case "code":
                    try visit(child, style: style.union(.code), link: link)
                case "img":
                    // 原生图片和表情都带不了外层链接，带链接的图交给网页渲染，免得点了只看大图。
                    guard link == nil else { throw Unsupported() }
                    try image(child)
                case "hr":
                    flush()
                    blocks.append(.divider)
                case _ where blockTags.contains(name):
                    flush()
                    try visit(child, style: style, link: link)
                    flush()
                case _ where transparentTags.contains(name):
                    try visit(child, style: style, link: link)
                default:
                    throw Unsupported()
                }
            }
        }

        private mutating func image(_ element: Kanna.XMLElement) throws {
            guard let url = destination(element["src"]) else { throw Unsupported() }
            if let token = NodeSeekStickerLibrary.token(for: url) {
                runs.append(.sticker(token: ":" + token + ":", url: url))
                return
            }
            guard !StickerImageRules.isStickerURL(url) else { throw Unsupported() }
            flush()
            blocks.append(.image(alt: element["alt"] ?? "", url: url))
        }

        /// 按网页规则把连续空白折叠成一个空格；换行只来自 <br>。
        private mutating func append(_ raw: String, style: Style, link: URL?, preservesNewline: Bool = false) {
            var text = preservesNewline ? raw : raw.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            if !preservesNewline, text.hasPrefix(" "), endsWithSpace { text.removeFirst() }
            guard !text.isEmpty else { return }
            if case let .text(previous, previousStyle, previousLink)? = runs.last, previousStyle == style, previousLink == link {
                runs[runs.count - 1] = .text(previous + text, style, link)
            } else {
                runs.append(.text(text, style, link))
            }
        }

        private var endsWithSpace: Bool {
            guard let last = runs.last else { return true }
            if case let .text(text, _, _) = last { return text.hasSuffix(" ") || text.hasSuffix("\n") }
            return false
        }

        mutating func flush() {
            defer { runs.removeAll(keepingCapacity: true) }
            var trimmed = runs
            // 段首段尾的空白和换行不显示，与网页一致。
            while case let .text(text, style, link)? = trimmed.first {
                let value = String(text.drop(while: { $0 == " " || $0 == "\n" }))
                if value.isEmpty { trimmed.removeFirst(); continue }
                trimmed[0] = .text(value, style, link)
                break
            }
            while case let .text(text, style, link)? = trimmed.last {
                var value = text
                while value.last == " " || value.last == "\n" { value.removeLast() }
                if value.isEmpty { trimmed.removeLast(); continue }
                trimmed[trimmed.count - 1] = .text(value, style, link)
                break
            }
            guard !trimmed.isEmpty else { return }
            blocks.append(.paragraph(trimmed))
        }

        private func destination(_ raw: String?) -> URL? {
            guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
                  // 与正文一致按 UTF-8 字节解析，含中文的地址也能成为链接。
                  let url = URL(dataRepresentation: Data(raw.utf8), relativeTo: baseURL)?.absoluteURL,
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  url.host?.isEmpty == false else { return nil }
            return url
        }
    }
}
