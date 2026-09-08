import CryptoKit
import Foundation
import Kanna

extension DTCoreTextHTMLContentRenderer {
    func renderMagicTabs(in fragment: String, baseURL: URL, maxImageWidth: CGFloat) -> [RenderedContentBlock]? {
        guard fragment.contains("nsk-magic-tabs"),
              let document = try? HTML(html: "<div id=\"__tabs_root__\">\(fragment)</div>", encoding: .utf8),
              let root = document.at_css("#__tabs_root__") else { return nil }
        let groups = root.css(".nsk-magic-tabs").filter {
            $0.xpath("ancestor::*[contains(concat(' ', normalize-space(@class), ' '), ' nsk-magic-tabs ')]").first == nil
        }
        guard !groups.isEmpty else { return nil }
        var remaining = root.innerHTML ?? fragment
        var blocks: [RenderedContentBlock] = []
        for group in groups {
            guard let html = group.toHTML, let range = remaining.range(of: html) else { continue }
            blocks += render(fragment: String(remaining[..<range.lowerBound]), baseURL: baseURL, maxImageWidth: maxImageWidth)
            var sections: [RenderedMagicTabsBlock.Section] = []
            var title = "内容"
            for child in group.children {
                if hasClass("nsk-magic-tab-title", in: child) {
                    title = child.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "内容"
                } else if hasClass("nsk-magic-tab-body", in: child) {
                    sections.append(.init(title: title, blocks: renderMagicTabBody(child, baseURL: baseURL, maxImageWidth: maxImageWidth)))
                }
            }
            if !sections.isEmpty {
                let id = SHA256.hash(data: Data(html.utf8)).map { String(format: "%02x", $0) }.joined()
                blocks.append(.tabs(.init(id: id, sections: sections)))
            }
            remaining = String(remaining[range.upperBound...])
        }
        // 未匹配时交给旧兼容路径，避免异常 HTML 导致递归。
        guard !blocks.isEmpty else { return nil }
        blocks += render(fragment: remaining, baseURL: baseURL, maxImageWidth: maxImageWidth)
        return blocks
    }

    private func renderMagicTabBody(_ body: XMLElement, baseURL: URL, maxImageWidth: CGFloat) -> [RenderedContentBlock] {
        let html = body.innerHTML ?? ""
        // WebView 在网页替换 code 节点前保存的完整原文；不从可见 xterm 行拼凑报告。
        if let encoded = body["data-nodeseek-terminal-source"],
           let data = Data(base64Encoded: encoded),
           let sources = try? JSONDecoder().decode([String].self, from: data), !sources.isEmpty {
            let terminals = sources.map { RenderedContentBlock.terminal(.init(ansi: $0)) }
            let images = body.css("img").compactMap(\.toHTML).joined()
            return terminals + render(fragment: images, baseURL: baseURL, maxImageWidth: maxImageWidth)
        }
        if isXtermMagicTabBodyHTML(html) {
            return [.unsupported(reason: Self.unsupportedXtermContentNotice)]
        }
        var remaining = html
        var blocks: [RenderedContentBlock] = []
        for pre in body.css("pre") {
            guard let preHTML = pre.toHTML, let range = remaining.range(of: preHTML) else { continue }
            blocks += render(fragment: String(remaining[..<range.lowerBound]), baseURL: baseURL, maxImageWidth: maxImageWidth)
            let ansi = terminalSource(from: pre.at_css("code") ?? pre)
            if !ansi.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(.terminal(.init(ansi: ansi)))
            }
            remaining = String(remaining[range.upperBound...])
        }
        blocks += render(fragment: remaining, baseURL: baseURL, maxImageWidth: maxImageWidth)
        return blocks
    }

    private func terminalSource(from node: XMLElement) -> String {
        // NodeSeek 用空 span 存放 ESC/退格字符，直接取 text 会丢失控制字符。
        if let raw = node["data-ansicode"], let value = UInt32(raw), let scalar = UnicodeScalar(value) {
            return String(scalar)
        }
        if node.tagName?.lowercased() == "br" { return "\n" }
        let children = node.xpath("node()").map { $0 }
        if children.isEmpty { return node.text ?? "" }
        return children.map { terminalSource(from: $0) }.joined()
    }
}
