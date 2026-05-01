//
//  DTCoreTextHTMLContentRenderer+MagicTabs.swift
//  nodeseek
//
//  Created by Codex on 2026/4/30.
//

import Foundation
import Kanna

extension DTCoreTextHTMLContentRenderer {
    func expandNodeSeekMagicTabs(in fragment: String) -> String {
        guard fragment.contains("nsk-magic-tabs") else { return fragment }
        guard let document = try? HTML(
            html: "<div id=\"__nodeseek_fragment_root__\">\(fragment)</div>",
            encoding: .utf8
        ),
              let root = document.at_css("#__nodeseek_fragment_root__") else {
            return fragment
        }

        let expanded = root.children
            .compactMap { expandedHTML(for: $0) }
            .joined()
        return expanded.isEmpty ? fragment : expanded
    }

    func expandedHTML(for node: XMLElement) -> String? {
        guard hasClass("nsk-magic-tabs", in: node) else {
            return node.toHTML
        }

        var sections: [String] = []
        var pendingTitleHTML: String?

        for child in node.children {
            if hasClass("nsk-magic-tab-title", in: child) {
                if let titleHTML = pendingTitleHTML {
                    sections.append(expandedMagicTabTitleHTML(titleHTML))
                }
                pendingTitleHTML = child.innerHTML ?? child.text
                continue
            }

            if hasClass("nsk-magic-tab-body", in: child) {
                if let titleHTML = pendingTitleHTML {
                    sections.append(expandedMagicTabTitleHTML(titleHTML))
                    pendingTitleHTML = nil
                }
                if let bodyHTML = child.innerHTML, bodyHTML.isEmpty == false {
                    sections.append("<div>\(simplifiedMagicTabBodyHTML(bodyHTML))</div>")
                }
                continue
            }

            if let titleHTML = pendingTitleHTML {
                sections.append(expandedMagicTabTitleHTML(titleHTML))
                pendingTitleHTML = nil
            }
            if let childHTML = child.toHTML {
                sections.append(childHTML)
            }
        }

        if let titleHTML = pendingTitleHTML {
            sections.append(expandedMagicTabTitleHTML(titleHTML))
        }

        return sections.joined(separator: "\n")
    }

    func expandedMagicTabTitleHTML(_ titleHTML: String) -> String {
        "<p><strong>\(titleHTML)</strong></p>"
    }

    func simplifiedMagicTabBodyHTML(_ bodyHTML: String) -> String {
        if isXtermMagicTabBodyHTML(bodyHTML) {
            return unsupportedContentHTML(reason: Self.unsupportedXtermContentNotice)
        }

        let mayContainANSICode = bodyHTML.contains("language-ansi") || bodyHTML.contains("data-ansicode")
        guard mayContainANSICode else { return bodyHTML }
        guard let document = try? HTML(
            html: "<div id=\"__nodeseek_magic_tab_body__\">\(bodyHTML)</div>",
            encoding: .utf8
        ),
              let root = document.at_css("#__nodeseek_magic_tab_body__") else {
            return bodyHTML
        }

        var blocks: [String] = []

        blocks.append(contentsOf: root.css("pre > code").compactMap { code -> String? in
            let isANSICode = hasClass("language-ansi", in: code) || (code.toHTML?.contains("data-ansicode") == true)
            guard isANSICode else { return nil }
            guard let rawText = code.text, rawText.isEmpty == false else { return nil }
            let normalizedText = stripANSICodes(from: rawText)
            guard normalizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                return nil
            }
            return "<pre><code>\(escapedHTML(normalizedText))</code></pre>"
        })

        for image in root.css("img") {
            if let imageHTML = image.toHTML {
                blocks.append(imageHTML)
            }
        }

        return blocks.isEmpty ? bodyHTML : blocks.joined(separator: "\n")
    }

    func isXtermMagicTabBodyHTML(_ bodyHTML: String) -> Bool {
        guard let document = try? HTML(
            html: "<div id=\"__nodeseek_magic_tab_body__\">\(bodyHTML)</div>",
            encoding: .utf8
        ),
              let root = document.at_css("#__nodeseek_magic_tab_body__") else {
            let normalizedHTML = bodyHTML.lowercased()
            return normalizedHTML.contains("xterm-rows")
                || normalizedHTML.contains("class=\"terminal-container embedmode\"")
                || normalizedHTML.contains("class='terminal-container embedmode'")
        }

        if root.at_css(".xterm-rows") != nil {
            return true
        }

        return root.css(".terminal-container").contains { hasClass("embedMode", in: $0) }
    }

    func unsupportedContentHTML(reason: String) -> String {
        "<p class=\"\(Self.unsupportedContentClassName)\">\(escapedHTML(reason))</p>"
    }

    func escapedHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    func stripANSICodes(from text: String) -> String {
        let escapedText = text.replacingOccurrences(of: "\u{001B}", with: "")
        let fullRange = NSRange(location: 0, length: (escapedText as NSString).length)
        return Self.ansiCodeRegex.stringByReplacingMatches(
            in: escapedText,
            options: [],
            range: fullRange,
            withTemplate: ""
        )
    }
}
