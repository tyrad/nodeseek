import Foundation
import Kanna

nonisolated enum NodeSeekVoteParser {
    indirect enum Part {
        case html(String)
        case vote(Int)
        case quote([Part])
    }

    static func voteID(in url: URL) -> Int? {
        guard url.scheme?.lowercased() == "nsapp", url.host?.lowercased() == "vote",
              url.path.isEmpty, url.user == nil, url.password == nil, url.port == nil,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let values = components.queryItems?.filter { $0.name == "id" } ?? []
        guard values.count == 1, let raw = values.first?.value else { return nil }
        return positiveID(raw)
    }

    static func parts(in html: String) -> [Part]? {
        guard html.localizedCaseInsensitiveContains("nsapp://vote") || html.contains("vote-panel"),
              let doc = try? HTML(html: "<div id=\"__vote_root__\">\(html)</div>", encoding: .utf8),
              let root = doc.at_css("#__vote_root__"), containsVote(root) else { return nil }
        return split(root)
    }

    private static func positiveID(_ text: String) -> Int? {
        guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }),
              let id = Int(text), id > 0, id <= 9_007_199_254_740_991 else { return nil }
        return id
    }

    private static func isExcluded(_ node: Kanna.XMLElement) -> Bool {
        ["pre", "code", "script", "style", "textarea"].contains(node.tagName?.lowercased() ?? "")
    }

    private static func reference(_ node: Kanna.XMLElement) -> Int? {
        if node.tagName?.lowercased() == "a" {
            for value in [node["data-href"], node["href"]].compactMap({ $0 }) {
                if let url = URL(string: value), let id = voteID(in: url) { return id }
            }
        }
        guard (node["class"] ?? "").split(whereSeparator: \.isWhitespace).contains("vote-panel") else { return nil }
        // 官网挂载后原链接被替换，编号仍保留在组件说明或选项 ID 中。
        let text = node.text ?? ""
        if let range = text.range(of: #"nsapp://vote\?id=[0-9]+(?![0-9])"#, options: .regularExpression),
           let url = URL(string: String(text[range])), let id = voteID(in: url) { return id }
        for input in node.css("input[id]") {
            let parts = (input["id"] ?? "").split(separator: "-")
            if parts.count == 4, parts[0] == "vote", parts[1] == "item",
               let id = positiveID(String(parts[2])), positiveID(String(parts[3])) != nil { return id }
        }
        return nil
    }

    private static func containsVote(_ node: Kanna.XMLElement) -> Bool {
        if isExcluded(node) { return false }
        return reference(node) != nil || node.children.contains(where: containsVote)
    }

    private static func split(_ node: Kanna.XMLElement) -> [Part] {
        var parts: [Part] = []
        var pending = ""
        func flush() {
            if !pending.isEmpty { parts.append(.html(pending)); pending = "" }
        }
        for child in node.xpath("node()") {
            guard containsVote(child) else { pending += child.toHTML ?? ""; continue }
            flush()
            if let id = reference(child) { parts.append(.vote(id)) }
            else if child.tagName?.lowercased() == "blockquote" { parts.append(.quote(split(child))) }
            else { parts += split(child) }
        }
        flush()
        return parts
    }
}
