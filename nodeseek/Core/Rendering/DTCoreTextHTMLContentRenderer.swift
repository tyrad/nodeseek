//
//  DTCoreTextHTMLContentRenderer.swift
//  nodeseek
//
//  Created by Codex on 2026/4/28.
//

import DTCoreText
import Foundation
import Kanna
import OSLog
import UIKit

struct DTCoreTextHTMLContentRenderer {
    private struct ImageDescriptor {
        let url: URL?
        let isSticker: Bool
    }

    private enum Layout {
        static let defaultMaxImageWidth: CGFloat = 320
        static let bodyLineSpacing: CGFloat = 5
        static let blockquoteTextIndent: CGFloat = 11
    }

    private static let linkColor = UIColor(red: 15 / 255, green: 128 / 255, blue: 85 / 255, alpha: 1)

    private static let imageTagRegex = try! NSRegularExpression(
        pattern: "<img\\b[^>]*>",
        options: [.caseInsensitive]
    )
    private static let srcAttributeRegex = try! NSRegularExpression(
        pattern: "\\bsrc\\s*=\\s*([\"'])([^\"']+)\\1",
        options: [.caseInsensitive]
    )
    private static let dataSourceAttributeRegex = try! NSRegularExpression(
        pattern: "\\b(?:data-src|data-original)\\s*=\\s*([\"'])([^\"']+)\\1",
        options: [.caseInsensitive]
    )
    private static let srcsetAttributeRegex = try! NSRegularExpression(
        pattern: "\\bsrcset\\s*=\\s*([\"'])([^\"']+)\\1",
        options: [.caseInsensitive]
    )
    private static let classAttributeRegex = try! NSRegularExpression(
        pattern: "\\bclass\\s*=\\s*([\"'])([^\"']+)\\1",
        options: [.caseInsensitive]
    )
    private static let listMarkerRegex = try! NSRegularExpression(
        pattern: "\\t((?:\\d+[.)])|[•◦▪])\\t",
        options: []
    )
    private static let ansiCodeRegex = try! NSRegularExpression(
        pattern: "(?:\\u001B\\[|\\[)\\d{1,3}(?:;\\d{1,3})*m",
        options: []
    )
    private static let logger = Logger(subsystem: "com.nodeseek.app", category: "DetailDTCoreTextRenderer")

    func render(fragment: String, baseURL: URL) -> [RenderedContentBlock] {
        render(fragment: fragment, baseURL: baseURL, maxImageWidth: Layout.defaultMaxImageWidth)
    }

    func render(fragment: String, baseURL: URL, maxImageWidth: CGFloat) -> [RenderedContentBlock] {
        guard fragment.isEmpty == false else { return [] }

        logDiagnostics(
            "render start fragmentLength=\(fragment.count) hasMagicTabs=\(fragment.contains("nsk-magic-tabs")) maxImageWidth=\(numberString(maxImageWidth))"
        )
        let expandedFragment = expandNodeSeekMagicTabs(in: fragment)
        let normalizedFragment = normalizeImageSources(in: expandedFragment, baseURL: baseURL)
        let normalizedSources = imageDescriptors(in: normalizedFragment, baseURL: baseURL)
        logDiagnostics(
            "render normalized expandedLength=\(expandedFragment.count) normalizedLength=\(normalizedFragment.count) imageSources=\(normalizedSources.count) urls=\(normalizedSources.prefix(6).compactMap { $0.url?.absoluteString }.joined(separator: " | "))"
        )

        let blocks = renderContentBlocks(
            fragment: normalizedFragment,
            baseURL: baseURL,
            maxImageWidth: maxImageWidth
        )
        return blocks.isEmpty ? fallbackBlocks(from: normalizedFragment) : blocks
    }

    private func renderTextBlocks(fragment: String, baseURL: URL, maxImageWidth: CGFloat) -> [RenderedContentBlock] {
        let html = wrapHTML(fragment: fragment, baseURL: baseURL)
        guard let data = html.data(using: .utf8) else {
            return fallbackBlocks(from: fragment)
        }

        let imageSources = imageDescriptors(in: fragment, baseURL: baseURL)
        let options: [String: Any] = [
            NSBaseURLDocumentOption: baseURL,
            DTDefaultFontSize: UIFont.preferredFont(forTextStyle: .body).pointSize,
            DTDefaultTextColor: UIColor.label,
            DTDefaultLinkColor: Self.linkColor,
            DTMaxImageSize: NSValue(cgSize: CGSize(width: maxImageWidth, height: DetailImageLayout.maxImageHeight)),
            DTUseiOS6Attributes: true
        ]
        let builder = DTHTMLAttributedStringBuilder(
            html: data,
            options: options,
            documentAttributes: nil
        )
        guard let rendered = builder?.generatedAttributedString(), rendered.length > 0 else {
            return fallbackBlocks(from: fragment)
        }

        let normalized = normalize(
            attributed: rendered,
            baseURL: baseURL,
            imageSources: imageSources,
            maxImageWidth: maxImageWidth
        )
        logDiagnostics(
            "render done textLength=\(normalized.length) attachments=\(attachmentDiagnostics(in: normalized))"
        )
        return normalized.length > 0 ? [.text(normalized)] : fallbackBlocks(from: fragment)
    }

    private func renderContentBlocks(
        fragment: String,
        baseURL: URL,
        maxImageWidth: CGFloat
    ) -> [RenderedContentBlock] {
        let needsStructuredParsing = fragment.range(of: "<table", options: [.caseInsensitive]) != nil
            || fragment.range(of: "<pre", options: [.caseInsensitive]) != nil
        guard needsStructuredParsing else {
            return renderTextBlocks(fragment: fragment, baseURL: baseURL, maxImageWidth: maxImageWidth)
        }

        guard let document = try? HTML(
            html: "<div id=\"__nodeseek_content_root__\">\(fragment)</div>",
            encoding: .utf8
        ),
              document.at_css("#__nodeseek_content_root__") != nil else {
            return renderTextBlocks(fragment: fragment, baseURL: baseURL, maxImageWidth: maxImageWidth)
        }

        var blocks: [RenderedContentBlock] = []
        var pendingHTML = ""
        appendContentBlocks(
            fromHTML: fragment,
            pendingHTML: &pendingHTML,
            blocks: &blocks,
            baseURL: baseURL,
            maxImageWidth: maxImageWidth
        )
        flushPendingHTML(
            &pendingHTML,
            into: &blocks,
            baseURL: baseURL,
            maxImageWidth: maxImageWidth
        )
        return blocks
    }

    private func appendContentBlocks(
        fromHTML html: String,
        pendingHTML: inout String,
        blocks: inout [RenderedContentBlock],
        baseURL: URL,
        maxImageWidth: CGFloat
    ) {
        let pattern = "(?is)<(table|pre)\\b[^>]*>.*?</\\1>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            pendingHTML.append(html)
            return
        }

        let source = html as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        var currentLocation = 0
        for match in regex.matches(in: html, options: [], range: fullRange) {
            guard match.range.location >= currentLocation else { continue }
            let beforeRange = NSRange(location: currentLocation, length: match.range.location - currentLocation)
            appendPendingHTMLFragment(source.substring(with: beforeRange), into: &pendingHTML)
            flushPendingHTML(
                &pendingHTML,
                into: &blocks,
                baseURL: baseURL,
                maxImageWidth: maxImageWidth
            )

            let structuredHTML = source.substring(with: match.range)
            if let document = try? HTML(html: structuredHTML, encoding: .utf8),
               let node = document.at_css("table") ?? document.at_css("pre") {
                appendStructuredBlock(
                    from: node,
                    blocks: &blocks,
                    baseURL: baseURL
                )
            }
            currentLocation = NSMaxRange(match.range)
        }

        let remainingRange = NSRange(location: currentLocation, length: fullRange.length - currentLocation)
        appendPendingHTMLFragment(source.substring(with: remainingRange), into: &pendingHTML)
    }

    private func appendPendingHTMLFragment(_ html: String, into pendingHTML: inout String) {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        pendingHTML.append(html)
    }

    private func appendStructuredBlock(
        from node: XMLElement,
        blocks: inout [RenderedContentBlock],
        baseURL: URL
    ) {
        if isTableElement(node), let table = tableBlock(from: node, baseURL: baseURL) {
            blocks.append(.table(table))
        } else if isPreElement(node), let codeBlock = codeBlock(from: node) {
            blocks.append(.codeBlock(codeBlock))
        }
    }

    private func flushPendingHTML(
        _ pendingHTML: inout String,
        into blocks: inout [RenderedContentBlock],
        baseURL: URL,
        maxImageWidth: CGFloat
    ) {
        guard pendingHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            pendingHTML.removeAll(keepingCapacity: true)
            return
        }
        blocks.append(contentsOf: renderTextBlocks(
            fragment: pendingHTML,
            baseURL: baseURL,
            maxImageWidth: maxImageWidth
        ))
        pendingHTML.removeAll(keepingCapacity: true)
    }

    private func tableBlock(from tableNode: XMLElement, baseURL: URL) -> RenderedTableBlock? {
        let rows = tableNode.css("tr").compactMap { rowNode -> RenderedTableBlock.Row? in
            let cells = rowNode.xpath("./th|./td").compactMap { cellNode -> RenderedTableBlock.Cell? in
                guard isTableCellElement(cellNode) else { return nil }
                let text = normalizedCellText(from: cellNode)
                let imageURL = imageURL(from: cellNode, baseURL: baseURL)
                guard text.isEmpty == false || imageURL != nil else { return nil }
                return RenderedTableBlock.Cell(
                    text: text,
                    imageURL: imageURL,
                    isHeader: tagName(of: cellNode) == "th"
                )
            }
            guard cells.isEmpty == false else { return nil }
            return RenderedTableBlock.Row(
                cells: cells,
                isHeader: cells.contains(where: \.isHeader) || hasAncestor(named: "thead", for: rowNode)
            )
        }

        return rows.isEmpty ? nil : RenderedTableBlock(rows: rows)
    }

    private func codeBlock(from preNode: XMLElement) -> RenderedCodeBlock? {
        let rawText: String?
        if let codeNode = preNode.at_css("code") {
            rawText = codeText(from: codeNode)
        } else {
            rawText = fallbackPreText(from: preNode)
        }

        guard let text = rawText.map({ normalizedCodeText($0) }),
              text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }
        return RenderedCodeBlock(text: text)
    }

    private func codeText(from codeNode: XMLElement) -> String {
        if let html = codeNode.innerHTML, html.isEmpty == false {
            return plainCodeText(fromHTML: html)
        }
        return codeNode.text ?? ""
    }

    private func fallbackPreText(from preNode: XMLElement) -> String {
        let html = preNode.innerHTML ?? preNode.text ?? ""
        return plainCodeText(fromHTML: html)
    }

    private func plainCodeText(fromHTML html: String) -> String {
        let withoutChrome = html
            .replacingOccurrences(
                of: "(?is)<(script|style|button|svg)\\b[^>]*>.*?</\\1>",
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "(?i)<br\\s*/?>",
                with: "\n",
                options: .regularExpression
            )
        let stripped = withoutChrome.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
        return decodedHTMLEntities(in: stripped)
    }

    private func normalizedCodeText(_ text: String) -> String {
        decodedHTMLEntities(in: text)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .newlines)
    }

    private func normalizedCellText(from node: XMLElement) -> String {
        let rawText = htmlTextPreservingLineBreaks(from: node)
        return rawText
            .replacingOccurrences(of: "[ \\t\\r\\u{00A0}]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " *\\n+ *", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\\n{2,}", with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func htmlTextPreservingLineBreaks(from node: XMLElement) -> String {
        let html = node.innerHTML ?? node.text ?? ""
        let withoutHiddenContent = html
            .replacingOccurrences(
                of: "(?is)<(script|style)\\b[^>]*>.*?</\\1>",
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "(?is)<img\\b[^>]*>",
                with: "",
                options: .regularExpression
            )
        let withLineBreaks = withoutHiddenContent
            .replacingOccurrences(
                of: "(?i)<br\\s*/?>",
                with: "\n",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "(?i)</?(p|div|section|article|header|footer|blockquote|pre|ul|ol|li|h[1-6])\\b[^>]*>",
                with: "\n",
                options: .regularExpression
            )
        let stripped = withLineBreaks.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
        return decodedHTMLEntities(in: stripped)
    }

    private func decodedHTMLEntities(in text: String) -> String {
        guard text.range(
            of: #"&(?:[A-Za-z][A-Za-z0-9]+|#[0-9]+|#x[0-9A-Fa-f]+);"#,
            options: .regularExpression
        ) != nil,
              let data = text
            .replacingOccurrences(of: "\n", with: "__NODESEEK_CELL_LINE_BREAK__")
            .data(using: .utf8) else {
            return text
        }

        let decoded = (try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        ).string) ?? text
        return decoded.replacingOccurrences(of: "__NODESEEK_CELL_LINE_BREAK__", with: "\n")
    }

    private func imageURL(from node: XMLElement, baseURL: URL) -> URL? {
        guard let source = node.at_css("img")?["src"] else { return nil }
        return AvatarImageLoader.resolveImageURL(source, baseURL: baseURL)
    }

    private func isTableElement(_ node: XMLElement) -> Bool {
        tagName(of: node) == "table"
    }

    private func isPreElement(_ node: XMLElement) -> Bool {
        tagName(of: node) == "pre"
    }

    private func isTableCellElement(_ node: XMLElement) -> Bool {
        let tag = tagName(of: node)
        return tag == "td" || tag == "th"
    }

    private func hasAncestor(named targetName: String, for node: XMLElement) -> Bool {
        var current = node.parent
        while let ancestor = current {
            if tagName(of: ancestor) == targetName {
                return true
            }
            current = ancestor.parent
        }
        return false
    }

    private func tagName(of node: XMLElement) -> String {
        node.tagName?.lowercased() ?? ""
    }

    private func expandNodeSeekMagicTabs(in fragment: String) -> String {
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

    private func expandedHTML(for node: XMLElement) -> String? {
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

    private func expandedMagicTabTitleHTML(_ titleHTML: String) -> String {
        "<p><strong>\(titleHTML)</strong></p>"
    }

    private func simplifiedMagicTabBodyHTML(_ bodyHTML: String) -> String {
        let containsXtermRows = bodyHTML.contains("xterm-rows")
        let mayContainANSICode = bodyHTML.contains("language-ansi") || bodyHTML.contains("data-ansicode")
        let containsPre = bodyHTML.range(of: "<pre", options: [.caseInsensitive]) != nil
        guard containsXtermRows || mayContainANSICode || containsPre else { return bodyHTML }
        guard let document = try? HTML(
            html: "<div id=\"__nodeseek_magic_tab_body__\">\(bodyHTML)</div>",
            encoding: .utf8
        ),
              let root = document.at_css("#__nodeseek_magic_tab_body__") else {
            return bodyHTML
        }

        var blocks: [String] = []
        for child in root.children {
            if let simplified = simplifiedMagicTabChildHTML(child) {
                blocks.append(simplified)
            }
        }

        return blocks.isEmpty ? bodyHTML : blocks.joined(separator: "\n")
    }

    private func simplifiedMagicTabChildHTML(_ child: XMLElement) -> String? {
        if let rows = child.at_css(".xterm-rows") {
            return magicTabCodeHTML(from: xtermText(from: rows))
        }

        if isPreElement(child), let code = child.at_css("code") {
            return simplifiedMagicTabCodeHTML(from: code)
        }

        if let code = child.at_css("pre > code"),
           hasClass("language-ansi", in: code) || (code.toHTML?.contains("data-ansicode") == true) {
            return simplifiedMagicTabCodeHTML(from: code)
        }

        return child.toHTML
    }

    private func simplifiedMagicTabCodeHTML(from code: XMLElement) -> String? {
        let isANSICode = hasClass("language-ansi", in: code) || (code.toHTML?.contains("data-ansicode") == true)
        let rawText: String
        if isANSICode {
            rawText = stripANSICodes(from: code.text ?? "")
        } else {
            rawText = codeText(from: code)
        }
        return magicTabCodeHTML(from: rawText)
    }

    private func xtermText(from rows: XMLElement) -> String {
        rows.children.compactMap { row -> String? in
            guard let text = row.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  text.isEmpty == false else {
                return nil
            }
            return text
        }.joined(separator: "\n")
    }

    private func magicTabCodeHTML(from text: String) -> String? {
        let normalized = normalizedCodeText(text)
        guard normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }
        return "<p><code>\(escapedHTML(normalized).replacingOccurrences(of: "\n", with: "<br>"))</code></p>"
    }

    private func escapedHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func stripANSICodes(from text: String) -> String {
        let escapedText = text.replacingOccurrences(of: "\u{001B}", with: "")
        let fullRange = NSRange(location: 0, length: (escapedText as NSString).length)
        return Self.ansiCodeRegex.stringByReplacingMatches(
            in: escapedText,
            options: [],
            range: fullRange,
            withTemplate: ""
        )
    }

    private func wrapHTML(fragment: String, baseURL: URL) -> String {
        """
        <html>
        <head>
        <base href="\(baseURL.absoluteString)">
        <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", Helvetica, Arial, sans-serif;
            font-size: 17px;
            line-height: 1.42;
            color: #111111;
        }
        article, section, div { margin: 0; padding: 0; }
        p { margin: 0 0 12px 0; }
        h1, h2, h3, h4, h5, h6 {
            margin: 18px 0 8px 0;
            line-height: 1.28;
            font-weight: 700;
            color: #111111;
        }
        h1 { font-size: 24px; }
        h2 { font-size: 22px; color: #2ea44f; }
        h3 { font-size: 20px; }
        h4 { font-size: 19px; }
        h5 { font-size: 18px; }
        h6 { font-size: 17px; }
        strong, b { font-weight: 700; }
        em, i { font-style: italic; }
        a { color: #0f8055; text-decoration: none; }
        ul, ol { margin: 0 0 12px 0; padding-left: 22px; }
        li { margin: 0 0 6px 0; }
        img { max-width: 100%; height: auto; margin: 4px 0 12px 0; }
        blockquote {
            background-color: #f6f8fa;
            border-left: 3px solid #d0d7de;
            margin-top: 8px;
            margin-right: 0;
            margin-bottom: 12px;
            margin-left: 0;
            padding-top: 12px;
            padding-right: 10px;
            padding-bottom: 12px;
            padding-left: 8px;
            color: #555555;
        }
        pre {
            font-family: Menlo, Monaco, monospace;
            font-size: 13px;
            line-height: 1.35;
            white-space: pre-wrap;
            margin: 8px 0 12px 0;
        }
        code {
            font-family: Menlo, Monaco, monospace;
            font-size: 13px;
        }
        </style>
        </head>
        <body>\(fragment)</body>
        </html>
        """
    }

    private func normalize(
        attributed: NSAttributedString,
        baseURL: URL,
        imageSources: [ImageDescriptor],
        maxImageWidth: CGFloat
    ) -> NSMutableAttributedString {
        let mutable = NSMutableAttributedString(attributedString: attributed)
        guard mutable.length > 0 else { return mutable }

        normalizeBaseTextAttributes(in: mutable)
        normalizeParagraphStyles(in: mutable)
        normalizeTextBlocks(in: mutable)
        normalizeLinks(in: mutable, baseURL: baseURL)
        normalizeVisibleListMarkers(in: mutable)
        normalizeImageAttachments(in: mutable, imageSources: imageSources, maxImageWidth: maxImageWidth)
        return mutable
    }

    private func normalizeBaseTextAttributes(in attributed: NSMutableAttributedString) {
        let fullRange = NSRange(location: 0, length: attributed.length)
        let bodyColor = UIColor.label

        let bodyFont = UIFont.preferredFont(forTextStyle: .body)
        attributed.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            guard let font = value as? UIFont else {
                attributed.addAttribute(.font, value: bodyFont, range: range)
                return
            }

            attributed.addAttribute(.font, value: normalizedSystemFont(from: font, fallback: bodyFont), range: range)
        }

        attributed.enumerateAttribute(.foregroundColor, in: fullRange) { value, range, _ in
            let color = (value as? UIColor).map(normalizedTextColor(from:)) ?? bodyColor
            attributed.addAttribute(.foregroundColor, value: color, range: range)
        }
    }

    private func normalizeParagraphStyles(in attributed: NSMutableAttributedString) {
        let fullRange = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttribute(.paragraphStyle, in: fullRange) { value, range, _ in
            let baseStyle = (value as? NSParagraphStyle) ?? .default
            let style = NSMutableParagraphStyle()
            style.setParagraphStyle(baseStyle)
            style.lineSpacing = max(style.lineSpacing, Layout.bodyLineSpacing)
            style.lineBreakMode = .byWordWrapping
            if containsBlockquoteTextBlock(in: attributed, range: range) {
                style.firstLineHeadIndent = Layout.blockquoteTextIndent
                style.headIndent = Layout.blockquoteTextIndent
                style.tailIndent = -Layout.blockquoteTextIndent
            }
            attributed.addAttribute(.paragraphStyle, value: style, range: range)
        }
    }

    private func containsBlockquoteTextBlock(in attributed: NSAttributedString, range: NSRange) -> Bool {
        guard range.location != NSNotFound, range.length > 0, NSMaxRange(range) <= attributed.length else {
            return false
        }
        let textBlocks = attributed.attribute(
            NSAttributedString.Key(DTTextBlocksAttribute),
            at: range.location,
            effectiveRange: nil
        ) as? [DTTextBlock]
        return textBlocks?.contains { $0.backgroundColor != nil } == true
    }

    private func normalizeTextBlocks(in attributed: NSMutableAttributedString) {
        let key = NSAttributedString.Key(DTTextBlocksAttribute)
        attributed.enumerateAttribute(
            key,
            in: NSRange(location: 0, length: attributed.length)
        ) { value, _, _ in
            guard let textBlocks = value as? [DTTextBlock] else { return }
            for block in textBlocks where block.backgroundColor != nil {
                let padding = block.padding
                block.padding = UIEdgeInsets(
                    top: max(padding.top, 12),
                    left: min(max(padding.left, 0), 8),
                    bottom: max(padding.bottom, 12),
                    right: max(padding.right, 10)
                )
            }
        }
    }

    private func normalizedSystemFont(from font: UIFont, fallback: UIFont) -> UIFont {
        let pointSize = font.pointSize > 0 ? font.pointSize : fallback.pointSize
        let traits = font.fontDescriptor.symbolicTraits
        let weight: UIFont.Weight = traits.contains(.traitBold) ? .semibold : .regular
        let baseFont = isMonospaced(font)
            ? UIFont.monospacedSystemFont(ofSize: pointSize, weight: weight)
            : UIFont.systemFont(ofSize: pointSize, weight: weight)
        guard traits.contains(.traitItalic),
              let descriptor = baseFont.fontDescriptor.withSymbolicTraits(
                baseFont.fontDescriptor.symbolicTraits.union(.traitItalic)
              ) else {
            return baseFont
        }
        return UIFont(descriptor: descriptor, size: pointSize)
    }

    private func isMonospaced(_ font: UIFont) -> Bool {
        let traits = font.fontDescriptor.symbolicTraits
        guard traits.contains(.traitMonoSpace) == false else { return true }
        let name = "\(font.fontName) \(font.familyName)".lowercased()
        return name.contains("mono") || name.contains("menlo") || name.contains("courier")
    }

    private func normalizedTextColor(from color: UIColor) -> UIColor {
        guard let components = rgbComponents(from: color) else { return color }
        if isNearGray(components, target: 17) {
            return .label
        }
        if isNearGray(components, target: 85) {
            return .secondaryLabel
        }
        return color
    }

    private func rgbComponents(from color: UIColor) -> (red: CGFloat, green: CGFloat, blue: CGFloat)? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        return (red, green, blue)
    }

    private func isNearGray(_ components: (red: CGFloat, green: CGFloat, blue: CGFloat), target: CGFloat) -> Bool {
        let normalizedTarget = target / 255
        let tolerance: CGFloat = 0.02
        return abs(components.red - normalizedTarget) <= tolerance
            && abs(components.green - normalizedTarget) <= tolerance
            && abs(components.blue - normalizedTarget) <= tolerance
    }

    private func normalizeLinks(in attributed: NSMutableAttributedString, baseURL: URL) {
        let dtLinkKey = NSAttributedString.Key(DTLinkAttribute)
        attributed.enumerateAttribute(
            dtLinkKey,
            in: NSRange(location: 0, length: attributed.length)
        ) { value, range, _ in
            guard let value else { return }
            let raw: String?
            if let url = value as? URL {
                raw = url.absoluteString
            } else if let string = value as? String {
                raw = string
            } else {
                raw = nil
            }
            guard let raw, let resolved = URL(string: raw, relativeTo: baseURL)?.absoluteURL else { return }
            attributed.addAttribute(.link, value: resolved, range: range)
            attributed.addAttribute(.foregroundColor, value: Self.linkColor, range: range)
            if dtLinkKey != .link {
                attributed.removeAttribute(dtLinkKey, range: range)
            }
        }
    }

    private func normalizeVisibleListMarkers(in attributed: NSMutableAttributedString) {
        let source = attributed.string as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        let matches = Self.listMarkerRegex.matches(in: attributed.string, options: [], range: fullRange)
        guard matches.isEmpty == false else { return }

        for match in matches.reversed() {
            guard match.numberOfRanges >= 2 else { continue }
            let markerRange = match.range(at: 1)
            guard markerRange.location != NSNotFound else { continue }
            let marker = source.substring(with: markerRange)
            let attributes = attributed.attributes(at: match.range.location, effectiveRange: nil)
            attributed.replaceCharacters(
                in: match.range,
                with: NSAttributedString(string: "\(marker) ", attributes: attributes)
            )
        }
    }

    private func normalizeImageAttachments(
        in attributed: NSMutableAttributedString,
        imageSources: [ImageDescriptor],
        maxImageWidth: CGFloat
    ) {
        guard maxImageWidth > 0 else { return }

        var normalizedCount = 0
        var stickerFixedCount = 0
        var placeholderCount = 0
        var attachmentSummaries: [String] = []
        var imageIndex = 0
        attributed.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributed.length)
        ) { value, range, _ in
            guard let attachment = value as? DTTextAttachment else { return }
            let contentURL = attachment.contentURL
            let descriptor = imageIndex < imageSources.count ? imageSources[imageIndex] : nil
            guard let imageURL = contentURL ?? descriptor?.url else { return }

            if attachment.contentURL == nil {
                attachment.contentURL = imageURL
            }

            let isSticker = (descriptor?.isSticker == true) || isStickerImageURL(imageURL)
            if isSticker {
                stickerFixedCount += 1
            }

            let originalSize = attachment.originalSize
            var usedPlaceholder = false
            let layoutSourceSize: CGSize
            if originalSize.width > 0, originalSize.height > 0 {
                layoutSourceSize = originalSize
            } else if isSticker, attachment.displaySize.width > 0, attachment.displaySize.height > 0 {
                layoutSourceSize = attachment.displaySize
            } else {
                layoutSourceSize = .zero
                usedPlaceholder = true
                placeholderCount += 1
            }
            // 避免 attachment 初始尺寸为 0 时无法创建视图，导致图片永远不触发下载回流。
            attachment.displaySize = DetailImageLayout.presentation(
                for: layoutSourceSize,
                maxWidth: maxImageWidth,
                isSticker: isSticker
            ).size

            attachmentSummaries.append(
                "url=\(imageURL.absoluteString),original=\(string(from: attachment.originalSize)),display=\(string(from: attachment.displaySize)),placeholder=\(usedPlaceholder)"
            )
            normalizedCount += 1
            imageIndex += 1
        }

        logDiagnostics(
            "已保留DTCoreText图片附件 count=\(normalizedCount) stickerFixed=\(stickerFixedCount) placeholder=\(placeholderCount) details=\(attachmentSummaries.prefix(6).joined(separator: " | "))"
        )
    }

    private func normalizeImageSources(in fragment: String, baseURL: URL) -> String {
        let source = fragment as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        let matches = Self.imageTagRegex.matches(in: fragment, options: [], range: fullRange)
        guard matches.isEmpty == false else { return fragment }

        let mutable = NSMutableString(string: fragment)
        for match in matches.reversed() {
            let tag = source.substring(with: match.range)
            guard let rawSource = preferredImageSource(in: tag),
                  let resolved = AvatarImageLoader.resolveImageURL(rawSource, baseURL: baseURL) else { continue }

            if let srcMatch = firstMatch(Self.srcAttributeRegex, in: tag), srcMatch.numberOfRanges >= 3 {
                let localRange = srcMatch.range(at: 2)
                guard localRange.location != NSNotFound else { continue }
                let srcRange = NSRange(location: match.range.location + localRange.location, length: localRange.length)
                mutable.replaceCharacters(in: srcRange, with: resolved.absoluteString)
                continue
            }

            let insertion = " src=\"\(resolved.absoluteString)\""
            let insertionLocation = tag.hasSuffix("/>")
                ? match.range.location + max(tag.count - 2, 0)
                : match.range.location + max(tag.count - 1, 0)
            mutable.insert(insertion, at: insertionLocation)
        }

        return mutable as String
    }

    private func imageDescriptors(in fragment: String, baseURL: URL) -> [ImageDescriptor] {
        let source = fragment as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        let matches = Self.imageTagRegex.matches(in: fragment, options: [], range: fullRange)
        guard matches.isEmpty == false else { return [] }
        return matches.compactMap { match in
            let tag = source.substring(with: match.range)
            guard let rawSource = preferredImageSource(in: tag),
                  let resolved = AvatarImageLoader.resolveImageURL(rawSource, baseURL: baseURL) else { return nil }
            return ImageDescriptor(url: resolved, isSticker: hasStickerClass(in: tag))
        }
    }

    private func preferredImageSource(in tag: String) -> String? {
        if let source = attributeValue(Self.srcAttributeRegex, in: tag), source.isEmpty == false {
            return source
        }
        if let source = attributeValue(Self.dataSourceAttributeRegex, in: tag), source.isEmpty == false {
            return source
        }
        if let srcset = attributeValue(Self.srcsetAttributeRegex, in: tag) {
            return preferredSourceFromSrcset(srcset)
        }
        return nil
    }

    private func preferredSourceFromSrcset(_ srcset: String) -> String? {
        srcset.split(separator: ",").compactMap { candidate -> String? in
            let parts = candidate.split(whereSeparator: { $0.isWhitespace })
            return parts.first.map(String.init)
        }.last
    }

    private func attributeValue(_ regex: NSRegularExpression, in tag: String) -> String? {
        guard let match = firstMatch(regex, in: tag), match.numberOfRanges >= 3 else { return nil }
        let source = tag as NSString
        let valueRange = match.range(at: 2)
        guard valueRange.location != NSNotFound else { return nil }
        return source.substring(with: valueRange)
    }

    private func firstMatch(_ regex: NSRegularExpression, in string: String) -> NSTextCheckingResult? {
        regex.firstMatch(
            in: string,
            options: [],
            range: NSRange(location: 0, length: (string as NSString).length)
        )
    }

    private func hasStickerClass(in tag: String) -> Bool {
        guard let classValue = attributeValue(Self.classAttributeRegex, in: tag) else { return false }
        return classValue.split(whereSeparator: { $0.isWhitespace }).contains { $0 == "sticker" }
    }

    private func isStickerImageURL(_ url: URL?) -> Bool {
        guard let absolute = url?.absoluteString.lowercased() else { return false }
        return absolute.contains("sticker")
    }

    private func logDiagnostics(_ message: String) {
        guard NodeSeekDebugConfig.enableDetailRenderDiagnostics else { return }
        Self.logger.info("\(message, privacy: .public)")
    }

    private func attachmentDiagnostics(in attributedText: NSAttributedString) -> String {
        guard attributedText.length > 0 else { return "[]" }
        var parts: [String] = []
        attributedText.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributedText.length)
        ) { value, _, _ in
            guard let attachment = value as? DTTextAttachment else { return }
            parts.append(
                "url=\(attachment.contentURL?.absoluteString ?? "nil"),original=\(string(from: attachment.originalSize)),display=\(string(from: attachment.displaySize))"
            )
        }
        if parts.count > 6 {
            return "[\(parts.prefix(6).joined(separator: " | ")) | ... total=\(parts.count)]"
        }
        return "[\(parts.joined(separator: " | "))]"
    }

    private func string(from size: CGSize) -> String {
        "\(numberString(size.width))x\(numberString(size.height))"
    }

    private func numberString(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }

    private func hasClass(_ className: String, in node: XMLElement) -> Bool {
        guard let classes = node.className?.split(whereSeparator: { $0.isWhitespace }) else {
            return false
        }
        return classes.contains { $0 == className }
    }

    private func fallbackBlocks(from html: String) -> [RenderedContentBlock] {
        let fallback = html
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? [] : [.text(NSAttributedString(string: fallback))]
    }
}
