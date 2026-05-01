//
//  DTCoreTextHTMLContentRenderer.swift
//  nodeseek
//
//  Created by Codex on 2026/4/28.
//

import DTCoreText
import Foundation
import OSLog
import UIKit

struct DTCoreTextHTMLContentRenderer {
    enum Layout {
        static let defaultMaxImageWidth: CGFloat = 320
        static let bodyLineSpacing: CGFloat = 5
        static let blockquoteTextIndent: CGFloat = 11
    }

    static let linkColor = UIColor(red: 15 / 255, green: 128 / 255, blue: 85 / 255, alpha: 1)

    static let imageTagRegex = try! NSRegularExpression(
        pattern: "<img\\b[^>]*>",
        options: [.caseInsensitive]
    )
    static let videoTagRegex = try! NSRegularExpression(
        pattern: "<video\\b[\\s\\S]*?</video>",
        options: [.caseInsensitive]
    )
    static let videoStartTagRegex = try! NSRegularExpression(
        pattern: "<video\\b[^>]*>",
        options: [.caseInsensitive]
    )
    static let sourceTagRegex = try! NSRegularExpression(
        pattern: "<source\\b[^>]*>",
        options: [.caseInsensitive]
    )
    static let srcAttributeRegex = try! NSRegularExpression(
        pattern: "\\bsrc\\s*=\\s*([\"'])([^\"']+)\\1",
        options: [.caseInsensitive]
    )
    static let typeAttributeRegex = try! NSRegularExpression(
        pattern: "\\btype\\s*=\\s*([\"'])([^\"']+)\\1",
        options: [.caseInsensitive]
    )
    static let dataSourceAttributeRegex = try! NSRegularExpression(
        pattern: "\\b(?:data-src|data-original)\\s*=\\s*([\"'])([^\"']+)\\1",
        options: [.caseInsensitive]
    )
    static let srcsetAttributeRegex = try! NSRegularExpression(
        pattern: "\\bsrcset\\s*=\\s*([\"'])([^\"']+)\\1",
        options: [.caseInsensitive]
    )
    static let classAttributeRegex = try! NSRegularExpression(
        pattern: "\\bclass\\s*=\\s*([\"'])([^\"']+)\\1",
        options: [.caseInsensitive]
    )
    static let structuredBlockRegex = try! NSRegularExpression(
        pattern: "(?is)<(table|pre)\\b[^>]*>.*?</\\1>",
        options: []
    )
    static let standaloneImageContainerRegex = try! NSRegularExpression(
        pattern: "(?is)<(p|div|section)\\b[^>]*>.*?</\\1>",
        options: []
    )
    static let unsupportedXtermContentNotice = "不支持显示此内容，请前往网页查看。"
    static let unsupportedContentClassName = "nodeseek-unsupported-content"
    static let listMarkerRegex = try! NSRegularExpression(
        pattern: "\\t((?:\\d+[.)])|[•◦▪])\\t",
        options: []
    )
    static let ansiCodeRegex = try! NSRegularExpression(
        pattern: "(?:\\u001B\\[|\\[)\\d{1,3}(?:;\\d{1,3})*m",
        options: []
    )
    static let logger = Logger(subsystem: "com.nodeseek.app", category: "DetailDTCoreTextRenderer")

    func render(fragment: String, baseURL: URL) -> [RenderedContentBlock] {
        render(fragment: fragment, baseURL: baseURL, maxImageWidth: Layout.defaultMaxImageWidth)
    }

    func render(fragment: String, baseURL: URL, maxImageWidth: CGFloat) -> [RenderedContentBlock] {
        guard fragment.isEmpty == false else { return [] }

        logDiagnostics(
            "render start fragmentLength=\(fragment.count) hasMagicTabs=\(fragment.contains("nsk-magic-tabs")) maxImageWidth=\(numberString(maxImageWidth))"
        )
        let expandedFragment = expandNodeSeekMagicTabs(in: fragment)
        let normalizedVideoFragment = normalizeVideoStickerSources(in: expandedFragment, baseURL: baseURL)
        let normalizedFragment = normalizeImageSources(in: normalizedVideoFragment, baseURL: baseURL)
        logDiagnostics(
            "render normalized expandedLength=\(expandedFragment.count) normalizedLength=\(normalizedFragment.count)"
        )

        let blocks = renderContentBlocks(
            fragment: normalizedFragment,
            baseURL: baseURL,
            maxImageWidth: maxImageWidth
        )
        return blocks.isEmpty ? fallbackBlocks(from: normalizedFragment) : blocks
    }

    func renderTextBlocks(fragment: String, baseURL: URL, maxImageWidth: CGFloat) -> [RenderedContentBlock] {
        let html = wrapHTML(fragment: fragment, baseURL: baseURL)
        guard let data = html.data(using: .utf8) else {
            return fallbackBlocks(from: fragment)
        }

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
            maxImageWidth: maxImageWidth
        )
        logDiagnostics(
            "render done textLength=\(normalized.length) attachments=\(attachmentDiagnostics(in: normalized))"
        )
        return normalized.length > 0 ? [.text(normalized)] : fallbackBlocks(from: fragment)
    }
}

enum DetailAttachmentAttributes {
    static func value(named name: String, in attributes: [AnyHashable: Any]?) -> String? {
        guard let attributes else { return nil }
        if let value = attributes[name] as? String {
            return value
        }
        return attributes.first { key, _ in
            String(describing: key).caseInsensitiveCompare(name) == .orderedSame
        }?.value as? String
    }

    static func hasClass(_ className: String, in attributes: [AnyHashable: Any]?) -> Bool {
        guard let classValue = value(named: "class", in: attributes) else { return false }
        return classValue.split(whereSeparator: { $0.isWhitespace }).contains { $0 == className }
    }
}
