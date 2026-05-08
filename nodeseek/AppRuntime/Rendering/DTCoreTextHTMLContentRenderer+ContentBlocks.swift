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
            || fragment.range(of: "<iframe", options: [.caseInsensitive]) != nil
            || fragment.range(of: "<img", options: [.caseInsensitive]) != nil
            || fragment.range(of: Self.unsupportedContentClassName, options: [.caseInsensitive]) != nil
            || containsCheckPlaceReportSVGURL(in: fragment)
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
            blocks.append(contentsOf: checkPlaceReportImageBlocks(in: codeBlock.text).map(RenderedContentBlock.image))
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
            appendRawIFrameLinkBlocks(
                fromHTML: source.substring(with: beforeRange),
                into: &blocks,
                baseURL: baseURL,
                maxImageWidth: maxImageWidth
            )

            let candidateHTML = source.substring(with: match.range)
            if let unsupportedBlock = unsupportedBlock(fromHTML: candidateHTML) {
                blocks.append(unsupportedBlock)
            } else if appendMixedIFrameLinkBlocks(
                fromHTML: candidateHTML,
                into: &blocks,
                baseURL: baseURL,
                maxImageWidth: maxImageWidth
            ) {
                // iframe 作为外部嵌入链接块渲染，不交给 DTCoreText 直接吞掉。
            } else if let imageBlocks = standaloneImageBlocks(fromHTML: candidateHTML, baseURL: baseURL) {
                blocks.append(contentsOf: imageBlocks.map(RenderedContentBlock.image))
            } else if appendMixedNormalImageBlocks(
                fromHTML: candidateHTML,
                into: &blocks,
                baseURL: baseURL,
                maxImageWidth: maxImageWidth
            ) {
                // 普通图片按块级内容渲染，避免 DTCoreText attachment 行高和真实图片高度不同步。
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
        appendRawIFrameLinkBlocks(
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
        blocks.append(contentsOf: checkPlaceReportImageBlocks(in: plainCodeText(fromHTML: html)).map(RenderedContentBlock.image))
    }

    func appendRawIFrameLinkBlocks(
        fromHTML html: String,
        into blocks: inout [RenderedContentBlock],
        baseURL: URL,
        maxImageWidth: CGFloat
    ) {
        let source = html as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        let matches = Self.iframeTagRegex.matches(in: html, options: [], range: fullRange)
        guard matches.isEmpty == false else {
            appendTextBlocks(
                fromHTML: html,
                into: &blocks,
                baseURL: baseURL,
                maxImageWidth: maxImageWidth
            )
            return
        }

        var currentLocation = 0
        for match in matches {
            guard match.range.location >= currentLocation else { continue }
            let beforeRange = NSRange(location: currentLocation, length: match.range.location - currentLocation)
            appendTextBlocks(
                fromHTML: source.substring(with: beforeRange),
                into: &blocks,
                baseURL: baseURL,
                maxImageWidth: maxImageWidth
            )

            let iframeTag = source.substring(with: match.range)
            if let iframeBlock = iframeLinkBlock(fromHTML: iframeTag, baseURL: baseURL) {
                blocks.append(.iframeLink(iframeBlock))
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

    func appendMixedIFrameLinkBlocks(
        fromHTML html: String,
        into blocks: inout [RenderedContentBlock],
        baseURL: URL,
        maxImageWidth: CGFloat
    ) -> Bool {
        guard let shell = containerShell(fromHTML: html) else { return false }

        let source = shell.innerHTML as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        let matches = Self.iframeTagRegex.matches(in: shell.innerHTML, options: [], range: fullRange)
        guard matches.isEmpty == false else { return false }

        var emittedIFrameBlock = false
        var currentLocation = 0
        var localBlocks: [RenderedContentBlock] = []
        for match in matches {
            guard match.range.location >= currentLocation else { continue }
            let beforeRange = NSRange(location: currentLocation, length: match.range.location - currentLocation)
            appendContainerTextBlocks(
                fromHTML: source.substring(with: beforeRange),
                shell: shell,
                into: &localBlocks,
                baseURL: baseURL,
                maxImageWidth: maxImageWidth
            )

            let iframeTag = source.substring(with: match.range)
            if let iframeBlock = iframeLinkBlock(fromHTML: iframeTag, baseURL: baseURL) {
                localBlocks.append(.iframeLink(iframeBlock))
                emittedIFrameBlock = true
            }
            currentLocation = NSMaxRange(match.range)
        }

        guard emittedIFrameBlock else { return false }
        let remainingRange = NSRange(location: currentLocation, length: fullRange.length - currentLocation)
        appendContainerTextBlocks(
            fromHTML: source.substring(with: remainingRange),
            shell: shell,
            into: &localBlocks,
            baseURL: baseURL,
            maxImageWidth: maxImageWidth
        )
        blocks.append(contentsOf: localBlocks)
        return true
    }

    func iframeLinkBlock(fromHTML html: String, baseURL: URL) -> RenderedIFrameLinkBlock? {
        guard let rawSource = attributeValue(Self.srcAttributeRegex, in: html)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              rawSource.isEmpty == false else {
            return nil
        }

        let source = decodedHTMLEntities(in: rawSource)
        guard let openURL = openURL(forIFrameSource: source, baseURL: baseURL),
              let scheme = openURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        return RenderedIFrameLinkBlock(
            source: source,
            displayDomain: openURL.host ?? source,
            openURL: openURL
        )
    }

    func openURL(forIFrameSource source: String, baseURL: URL) -> URL? {
        if source.hasPrefix("//") {
            return URL(string: "https:\(source)")
        }
        return URL(string: source, relativeTo: baseURL)?.absoluteURL
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
        if let reason, reason.isEmpty == false {
            return .unsupported(reason: reason)
        }
        return .unsupported(reason: Self.unsupportedXtermContentNotice)
    }

    func tableBlock(from tableNode: XMLElement, baseURL: URL) -> RenderedTableBlock? {
        let rows = tableNode.css("tr").compactMap { rowNode -> RenderedTableBlock.Row? in
            let cells = rowNode.xpath("./th|./td").compactMap { cellNode -> RenderedTableBlock.Cell? in
                guard isTableCellElement(cellNode) else { return nil }
                let content = tableCellContent(from: cellNode, baseURL: baseURL)
                let imageURL = imageURL(from: cellNode, baseURL: baseURL)
                guard content.text.isEmpty == false || imageURL != nil else { return nil }
                return RenderedTableBlock.Cell(
                    text: content.text,
                    links: content.links,
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

    private func tableCellContent(from node: XMLElement, baseURL: URL) -> (text: String, links: [RenderedTableBlock.Cell.Link]) {
        let html = (node.innerHTML ?? node.text ?? "")
            .replacingOccurrences(
                of: "(?is)<(script|style)\\b[^>]*>.*?</\\1>",
                with: "",
                options: .regularExpression
            )
        let source = html as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        var currentLocation = 0
        var currentLinkURL: URL?
        var units: [TableCellTextUnit] = []

        for match in Self.htmlTagRegex.matches(in: html, options: [], range: fullRange) {
            let textRange = NSRange(location: currentLocation, length: match.range.location - currentLocation)
            appendTableCellText(source.substring(with: textRange), url: currentLinkURL, into: &units)

            let tag = source.substring(with: match.range)
            handleTableCellTag(tag, baseURL: baseURL, currentLinkURL: &currentLinkURL, units: &units)
            currentLocation = NSMaxRange(match.range)
        }

        let remainingRange = NSRange(location: currentLocation, length: fullRange.length - currentLocation)
        appendTableCellText(source.substring(with: remainingRange), url: currentLinkURL, into: &units)

        return normalizedTableCellContent(from: units)
    }

    private func appendTableCellText(_ text: String, url: URL?, into units: inout [TableCellTextUnit]) {
        for character in decodedHTMLEntities(in: text) {
            units.append(TableCellTextUnit(character: character, url: url))
        }
    }

    private func handleTableCellTag(
        _ tag: String,
        baseURL: URL,
        currentLinkURL: inout URL?,
        units: inout [TableCellTextUnit]
    ) {
        guard let name = htmlTagName(in: tag) else { return }
        if name == "a" {
            currentLinkURL = isHTMLClosingTag(tag)
                ? nil
                : hrefURL(in: tag, baseURL: baseURL)
            return
        }

        guard name != "img" else { return }
        if name == "br" || Self.tableCellLineBreakTags.contains(name) {
            units.append(TableCellTextUnit(character: "\n", url: nil))
        }
    }

    private func normalizedTableCellContent(from units: [TableCellTextUnit]) -> (text: String, links: [RenderedTableBlock.Cell.Link]) {
        var normalized: [TableCellTextUnit] = []
        var index = 0

        while index < units.count {
            let unit = units[index]
            guard unit.character.isTableCellWhitespace else {
                normalized.append(unit)
                index += 1
                continue
            }

            var run: [TableCellTextUnit] = []
            var containsNewline = false
            while index < units.count, units[index].character.isTableCellWhitespace {
                containsNewline = containsNewline || units[index].character == "\n"
                run.append(units[index])
                index += 1
            }
            normalized.append(TableCellTextUnit(
                character: containsNewline ? "\n" : " ",
                url: commonLinkURL(in: run)
            ))
        }

        while normalized.first?.character.isTableCellWhitespace == true {
            normalized.removeFirst()
        }
        while normalized.last?.character.isTableCellWhitespace == true {
            normalized.removeLast()
        }

        return tableCellContent(fromNormalizedUnits: normalized)
    }

    private func tableCellContent(fromNormalizedUnits units: [TableCellTextUnit]) -> (text: String, links: [RenderedTableBlock.Cell.Link]) {
        var text = ""
        var links: [RenderedTableBlock.Cell.Link] = []
        var activeURL: URL?
        var activeLocation = 0
        var activeLength = 0
        var location = 0

        func flushActiveLink() {
            guard let activeURL, activeLength > 0 else { return }
            links.append(RenderedTableBlock.Cell.Link(
                location: activeLocation,
                length: activeLength,
                url: activeURL
            ))
        }

        for unit in units {
            let characterText = String(unit.character)
            let length = (characterText as NSString).length
            text.append(unit.character)

            if unit.url == activeURL {
                activeLength += unit.url == nil ? 0 : length
            } else {
                flushActiveLink()
                activeURL = unit.url
                activeLocation = location
                activeLength = unit.url == nil ? 0 : length
            }
            location += length
        }
        flushActiveLink()

        return (text, links)
    }

    private func commonLinkURL(in units: [TableCellTextUnit]) -> URL? {
        var commonURL: URL?
        for unit in units {
            guard let url = unit.url else { return nil }
            if let current = commonURL, current != url {
                return nil
            }
            commonURL = url
        }
        return commonURL
    }

    private func htmlTagName(in tag: String) -> String? {
        var text = tag.dropFirst()
        if text.first == "/" {
            text = text.dropFirst()
        }
        text = text.drop { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }
        let name = text.prefix { $0.isLetter || $0.isNumber }
        return name.isEmpty ? nil : name.lowercased()
    }

    private func isHTMLClosingTag(_ tag: String) -> Bool {
        tag.dropFirst().drop { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }.first == "/"
    }

    private func hrefURL(in tag: String, baseURL: URL) -> URL? {
        let source = tag as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        guard let match = Self.hrefAttributeRegex.firstMatch(in: tag, options: [], range: fullRange),
              match.numberOfRanges >= 3,
              match.range(at: 2).location != NSNotFound else {
            return nil
        }
        let href = decodedHTMLEntities(in: source.substring(with: match.range(at: 2)))
        return URL(string: href, relativeTo: baseURL)?.absoluteURL
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

    func containsCheckPlaceReportSVGURL(in text: String) -> Bool {
        DetailImageURLRules.containsCheckPlaceReportSVGURL(in: text)
    }

    func checkPlaceReportImageBlocks(in text: String) -> [RenderedImageBlock] {
        checkPlaceReportURLs(in: text).map {
            RenderedImageBlock(url: $0, altText: "check.place report")
        }
    }

    func checkPlaceReportURLs(in text: String) -> [URL] {
        let decodedText = decodedHTMLEntities(in: text)
        return DetailImageURLRules.checkPlaceReportSVGURLs(in: decodedText)
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

    func imageBlock(fromImageTag tag: String, baseURL: URL) -> RenderedImageBlock? {
        guard let document = try? HTML(html: tag, encoding: .utf8),
              let imageNode = document.at_css("img") else {
            return nil
        }
        return imageBlock(from: imageNode, baseURL: baseURL)
    }

    func appendMixedNormalImageBlocks(
        fromHTML html: String,
        into blocks: inout [RenderedContentBlock],
        baseURL: URL,
        maxImageWidth: CGFloat
    ) -> Bool {
        guard let shell = containerShell(fromHTML: html) else { return false }

        let source = shell.innerHTML as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        let matches = Self.imageTagRegex.matches(in: shell.innerHTML, options: [], range: fullRange)
        guard matches.isEmpty == false else { return false }

        var emittedImageBlock = false
        var currentLocation = 0
        var localBlocks: [RenderedContentBlock] = []
        for match in matches {
            guard match.range.location >= currentLocation else { continue }
            let imageTag = source.substring(with: match.range)
            let beforeRange = NSRange(location: currentLocation, length: match.range.location - currentLocation)
            let beforeHTML = source.substring(with: beforeRange)
            let afterHTML = source.substring(from: NSMaxRange(match.range))
            guard shouldSplitMixedImageTag(imageTag, beforeHTML: beforeHTML, afterHTML: afterHTML),
                  let imageBlock = imageBlock(fromImageTag: imageTag, baseURL: baseURL) else {
                continue
            }

            appendContainerTextBlocks(
                fromHTML: beforeHTML,
                shell: shell,
                into: &localBlocks,
                baseURL: baseURL,
                maxImageWidth: maxImageWidth
            )
            localBlocks.append(.image(imageBlock))
            emittedImageBlock = true
            currentLocation = NSMaxRange(match.range)
            currentLocation = rangeAfterAdjacentLineBreaks(in: source, startingAt: currentLocation).location
        }

        guard emittedImageBlock else { return false }
        let remainingRange = NSRange(location: currentLocation, length: fullRange.length - currentLocation)
        appendContainerTextBlocks(
            fromHTML: source.substring(with: remainingRange),
            shell: shell,
            into: &localBlocks,
            baseURL: baseURL,
            maxImageWidth: maxImageWidth
        )
        blocks.append(contentsOf: localBlocks)
        return true
    }

    func containerShell(fromHTML html: String) -> HTMLContainerShell? {
        let source = html as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        guard let match = Self.containerShellRegex.firstMatch(in: html, options: [], range: fullRange),
              match.numberOfRanges >= 5 else {
            return nil
        }

        let openingTagRange = match.range(at: 1)
        let innerRange = match.range(at: 3)
        let closingTagRange = match.range(at: 4)
        guard openingTagRange.location != NSNotFound,
              innerRange.location != NSNotFound,
              closingTagRange.location != NSNotFound else {
            return nil
        }

        return HTMLContainerShell(
            openingTag: source.substring(with: openingTagRange),
            innerHTML: source.substring(with: innerRange),
            closingTag: source.substring(with: closingTagRange)
        )
    }

    func appendContainerTextBlocks(
        fromHTML html: String,
        shell: HTMLContainerShell,
        into blocks: inout [RenderedContentBlock],
        baseURL: URL,
        maxImageWidth: CGFloat
    ) {
        guard html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }
        appendTextBlocks(
            fromHTML: shell.openingTag + html + shell.closingTag,
            into: &blocks,
            baseURL: baseURL,
            maxImageWidth: maxImageWidth
        )
    }

    func shouldSplitMixedImageTag(_ tag: String, beforeHTML: String, afterHTML: String) -> Bool {
        guard let source = preferredImageSource(in: tag),
              source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("data:") == false else {
            return false
        }
        return hasBlockBoundaryBeforeImage(beforeHTML) && hasBlockBoundaryAfterImage(afterHTML)
    }

    func hasBlockBoundaryBeforeImage(_ html: String) -> Bool {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return true }
        if trimmed.range(of: #"(?i)^<(?:p|div|section|article)\b[^>]*>$"#, options: .regularExpression) != nil {
            return true
        }
        if trimmed.range(of: #"(?i)<img\b[^>]*>$"#, options: .regularExpression) != nil {
            return true
        }
        return trimmed.range(of: #"(?i)<br\s*/?>$"#, options: .regularExpression) != nil
    }

    func hasBlockBoundaryAfterImage(_ html: String) -> Bool {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return true }
        return trimmed.range(of: #"(?i)^(?:<img\b|<br\s*/?>|</)"#, options: .regularExpression) != nil
    }

    func rangeAfterAdjacentLineBreaks(in source: NSString, startingAt location: Int) -> NSRange {
        var currentLocation = location
        let fullLength = source.length
        while currentLocation < fullLength {
            let remaining = source.substring(from: currentLocation)
            guard let match = Self.adjacentLineBreakRegex.firstMatch(
                in: remaining,
                options: [],
                range: NSRange(location: 0, length: (remaining as NSString).length)
            ) else {
                break
            }
            currentLocation += match.range.length
        }
        return NSRange(location: currentLocation, length: fullLength - currentLocation)
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

private struct TableCellTextUnit {
    let character: Character
    let url: URL?
}

private extension Character {
    var isTableCellWhitespace: Bool {
        self == " "
            || self == "\t"
            || self == "\r"
            || self == "\n"
            || self == "\u{00A0}"
    }
}
