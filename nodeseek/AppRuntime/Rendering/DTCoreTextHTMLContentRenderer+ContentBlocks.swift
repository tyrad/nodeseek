//
//  DTCoreTextHTMLContentRenderer+ContentBlocks.swift
//  nodeseek
//
//  Created by Codex on 2026/4/30.
//

import DTCoreText
import Foundation
import Kanna
import UIKit

extension DTCoreTextHTMLContentRenderer {
    func renderContentBlocks(
        fragment: String,
        baseURL: URL,
        maxImageWidth: CGFloat
    ) -> [RenderedContentBlock] {
        let needsStructuredParsing = fragment.range(of: "<table", options: [.caseInsensitive]) != nil
            || fragment.range(of: "<pre", options: [.caseInsensitive]) != nil
            || fragment.range(of: "<img", options: [.caseInsensitive]) != nil
            || fragment.range(of: Self.unsupportedContentClassName, options: [.caseInsensitive]) != nil
        guard needsStructuredParsing else {
            return renderTextBlocks(fragment: fragment, baseURL: baseURL, maxImageWidth: maxImageWidth)
        }

        guard (try? HTML(
            html: "<div id=\"__nodeseek_content_root__\">\(fragment)</div>",
            encoding: .utf8
        ))?.at_css("#__nodeseek_content_root__") != nil else {
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

    func appendContentBlocks(
        fromHTML html: String,
        pendingHTML: inout String,
        blocks: inout [RenderedContentBlock],
        baseURL: URL,
        maxImageWidth: CGFloat
    ) {
        let source = html as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        var currentLocation = 0

        for match in Self.structuredBlockRegex.matches(in: html, options: [], range: fullRange) {
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
                appendStructuredBlock(from: node, into: &blocks, baseURL: baseURL)
            }
            currentLocation = NSMaxRange(match.range)
        }

        let remainingRange = NSRange(location: currentLocation, length: fullRange.length - currentLocation)
        appendPendingHTMLFragment(source.substring(with: remainingRange), into: &pendingHTML)
    }

    func appendPendingHTMLFragment(_ html: String, into pendingHTML: inout String) {
        guard html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }
        pendingHTML.append(html)
    }

    func appendStructuredBlock(
        from node: XMLElement,
        into blocks: inout [RenderedContentBlock],
        baseURL: URL
    ) {
        if isTableElement(node), let table = tableBlock(from: node, baseURL: baseURL) {
            blocks.append(.table(table))
        } else if isPreElement(node), let codeBlock = codeBlock(from: node) {
            blocks.append(.codeBlock(codeBlock))
        }
    }

    func flushPendingHTML(
        _ pendingHTML: inout String,
        into blocks: inout [RenderedContentBlock],
        baseURL: URL,
        maxImageWidth: CGFloat
    ) {
        guard pendingHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            pendingHTML.removeAll(keepingCapacity: true)
            return
        }
        let html = pendingHTML
        pendingHTML.removeAll(keepingCapacity: true)
        appendInlineContentBlocks(
            fromHTML: html,
            into: &blocks,
            baseURL: baseURL,
            maxImageWidth: maxImageWidth
        )
    }

    func appendInlineContentBlocks(
        fromHTML html: String,
        into blocks: inout [RenderedContentBlock],
        baseURL: URL,
        maxImageWidth: CGFloat
    ) {
        let source = html as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        var currentLocation = 0

        for match in Self.standaloneImageContainerRegex.matches(in: html, options: [], range: fullRange) {
            guard match.range.location >= currentLocation else { continue }

            let beforeRange = NSRange(location: currentLocation, length: match.range.location - currentLocation)
            appendTextBlocks(
                fromHTML: source.substring(with: beforeRange),
                into: &blocks,
                baseURL: baseURL,
                maxImageWidth: maxImageWidth
            )

            let candidateHTML = source.substring(with: match.range)
            if let unsupportedBlock = unsupportedBlock(fromHTML: candidateHTML) {
                blocks.append(unsupportedBlock)
            } else if let imageBlocks = standaloneImageBlocks(fromHTML: candidateHTML, baseURL: baseURL) {
                blocks.append(contentsOf: imageBlocks.map(RenderedContentBlock.image))
            } else {
                appendTextBlocks(
                    fromHTML: candidateHTML,
                    into: &blocks,
                    baseURL: baseURL,
                    maxImageWidth: maxImageWidth
                )
            }
            currentLocation = NSMaxRange(match.range)
        }

        let remainingRange = NSRange(location: currentLocation, length: fullRange.length - currentLocation)
        appendTextBlocks(
            fromHTML: source.substring(with: remainingRange),
            into: &blocks,
            baseURL: baseURL,
            maxImageWidth: maxImageWidth
        )
    }

    func appendTextBlocks(
        fromHTML html: String,
        into blocks: inout [RenderedContentBlock],
        baseURL: URL,
        maxImageWidth: CGFloat
    ) {
        guard html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }
        let renderedBlocks = renderTextBlocks(
            fragment: html,
            baseURL: baseURL,
            maxImageWidth: maxImageWidth
        ).filter { block in
            guard case .text(let text) = block else { return true }
            return text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        blocks.append(contentsOf: renderedBlocks)
    }

    func unsupportedBlock(fromHTML html: String) -> RenderedContentBlock? {
        guard html.range(of: Self.unsupportedContentClassName, options: [.caseInsensitive]) != nil else {
            return nil
        }
        guard let document = try? HTML(html: html, encoding: .utf8),
              let marker = document.at_css(".\(Self.unsupportedContentClassName)") else {
            return nil
        }
        let reason = marker.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return .unsupported(reason: reason?.isEmpty == false ? reason! : Self.unsupportedXtermContentNotice)
    }

    func tableBlock(from tableNode: XMLElement, baseURL: URL) -> RenderedTableBlock? {
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

    func codeBlock(from preNode: XMLElement) -> RenderedCodeBlock? {
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

    func codeText(from codeNode: XMLElement) -> String {
        if let html = codeNode.innerHTML, html.isEmpty == false {
            return plainCodeText(fromHTML: html)
        }
        return codeNode.text ?? ""
    }

    func fallbackPreText(from preNode: XMLElement) -> String {
        let html = preNode.innerHTML ?? preNode.text ?? ""
        return plainCodeText(fromHTML: html)
    }

    func plainCodeText(fromHTML html: String) -> String {
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

    func normalizedCodeText(_ text: String) -> String {
        decodedHTMLEntities(in: text)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .newlines)
    }

    func normalizedCellText(from node: XMLElement) -> String {
        let rawText = htmlTextPreservingLineBreaks(from: node)
        return rawText
            .replacingOccurrences(of: "[ \\t\\r\\u{00A0}]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " *\\n+ *", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\\n{2,}", with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func htmlTextPreservingLineBreaks(from node: XMLElement) -> String {
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

    func decodedHTMLEntities(in text: String) -> String {
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

    func standaloneImageBlocks(from node: XMLElement, baseURL: URL) -> [RenderedImageBlock]? {
        guard isStandaloneImageContainer(node) else { return nil }
        var imageBlocks: [RenderedImageBlock] = []
        for imageNode in node.css("img") {
            guard let imageBlock = imageBlock(from: imageNode, baseURL: baseURL) else { return nil }
            imageBlocks.append(imageBlock)
        }
        return imageBlocks.isEmpty ? nil : imageBlocks
    }

    func standaloneImageBlocks(fromHTML html: String, baseURL: URL) -> [RenderedImageBlock]? {
        guard let document = try? HTML(html: html, encoding: .utf8),
              let node = document.at_css("p") ?? document.at_css("div") ?? document.at_css("section") else {
            return nil
        }
        return standaloneImageBlocks(from: node, baseURL: baseURL)
    }

    func imageBlock(from imageNode: XMLElement, baseURL: URL) -> RenderedImageBlock? {
        guard let source = imageNode["src"],
              let url = AvatarImageLoader.resolveImageURL(source, baseURL: baseURL),
              hasClass("sticker", in: imageNode) == false,
              isStickerImageURL(url) == false else {
            return nil
        }
        let altText = imageNode["alt"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return RenderedImageBlock(
            url: url,
            altText: altText?.isEmpty == false ? altText : nil
        )
    }

    func isStandaloneImageContainer(_ node: XMLElement) -> Bool {
        guard isStandaloneImageContainerTag(tagName(of: node)) else { return false }
        guard node.at_css("img") != nil else { return false }
        return containsOnlyStandaloneImageContent(node)
    }

    func isStandaloneImageContainerTag(_ tag: String) -> Bool {
        tag == "p" || tag == "div" || tag == "section" || tag == "article"
    }

    func containsOnlyStandaloneImageContent(_ node: XMLElement) -> Bool {
        let html = node.innerHTML ?? node.text ?? ""
        let text = html
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
            .replacingOccurrences(
                of: "(?i)<br\\s*/?>",
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "<[^>]+>",
                with: "",
                options: .regularExpression
            )
        return decodedHTMLEntities(in: text).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func imageURL(from node: XMLElement, baseURL: URL) -> URL? {
        guard let source = node.at_css("img")?["src"] else { return nil }
        return AvatarImageLoader.resolveImageURL(source, baseURL: baseURL)
    }

    func isTableElement(_ node: XMLElement) -> Bool {
        tagName(of: node) == "table"
    }

    func isPreElement(_ node: XMLElement) -> Bool {
        tagName(of: node) == "pre"
    }

    func isTableCellElement(_ node: XMLElement) -> Bool {
        let tag = tagName(of: node)
        return tag == "td" || tag == "th"
    }

    func hasAncestor(named targetName: String, for node: XMLElement) -> Bool {
        var current = node.parent
        while let ancestor = current {
            if tagName(of: ancestor) == targetName {
                return true
            }
            current = ancestor.parent
        }
        return false
    }

    func tagName(of node: XMLElement) -> String {
        node.tagName?.lowercased() ?? ""
    }
}
