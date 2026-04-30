//
//  DTCoreTextHTMLContentRenderer+Attributes.swift
//  nodeseek
//
//  Created by Codex on 2026/4/30.
//

import DTCoreText
import Foundation
import UIKit

extension DTCoreTextHTMLContentRenderer {
    private var blockquoteTextColor: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor.secondaryLabel : UIColor.label
        }
    }

    func normalize(
        attributed: NSAttributedString,
        baseURL: URL,
        maxImageWidth: CGFloat
    ) -> NSMutableAttributedString {
        let mutable = NSMutableAttributedString(attributedString: attributed)
        guard mutable.length > 0 else { return mutable }

        normalizeBaseTextAttributes(in: mutable)
        normalizeStrikethroughAttributes(in: mutable)
        normalizeTextBlocks(in: mutable)
        normalizeParagraphStyles(in: mutable)
        normalizeLinks(in: mutable, baseURL: baseURL)
        normalizeVisibleListMarkers(in: mutable)
        normalizeMediaAttachments(in: mutable, baseURL: baseURL, maxImageWidth: maxImageWidth)
        return mutable
    }

    func normalizeBaseTextAttributes(in attributed: NSMutableAttributedString) {
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
            let color = containsBlockquoteTextBlock(in: attributed, range: range)
                ? blockquoteTextColor
                : ((value as? UIColor).map(normalizedTextColor(from:)) ?? bodyColor)
            attributed.addAttribute(.foregroundColor, value: color, range: range)
        }
    }

    func normalizeStrikethroughAttributes(in attributed: NSMutableAttributedString) {
        let fullRange = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttribute(NSAttributedString.Key(DTStrikeOutAttribute), in: fullRange) { value, range, _ in
            guard isEnabledAttributeValue(value) else { return }
            attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }
    }

    func isEnabledAttributeValue(_ value: Any?) -> Bool {
        switch value {
        case let number as NSNumber:
            return number.intValue != 0
        case let int as Int:
            return int != 0
        case let bool as Bool:
            return bool
        default:
            return false
        }
    }

    func normalizeParagraphStyles(in attributed: NSMutableAttributedString) {
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

    func normalizeTextBlocks(in attributed: NSMutableAttributedString) {
        let fullRange = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttribute(
            NSAttributedString.Key(DTTextBlocksAttribute),
            in: fullRange
        ) { value, _, _ in
            guard let textBlocks = value as? [DTTextBlock] else { return }
            for textBlock in textBlocks where textBlock.backgroundColor != nil {
                textBlock.padding = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 10)
                // HTML 里 blockquote 的 background-color 是固定色；这里统一替换成动态系统色以适配深色模式。
                textBlock.backgroundColor = UIColor.secondarySystemBackground
            }
        }
        attributed.enumerateAttribute(
            NSAttributedString.Key(DTTextBlocksAttribute),
            in: fullRange
        ) { value, range, _ in
            guard let textBlocks = value as? [DTTextBlock],
                  textBlocks.contains(where: { $0.backgroundColor != nil }) else {
                return
            }
            attributed.addAttribute(.foregroundColor, value: blockquoteTextColor, range: range)
        }
    }

    func containsBlockquoteTextBlock(in attributed: NSAttributedString, range: NSRange) -> Bool {
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

    func normalizedSystemFont(from font: UIFont, fallback: UIFont) -> UIFont {
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

    func isMonospaced(_ font: UIFont) -> Bool {
        let traits = font.fontDescriptor.symbolicTraits
        guard traits.contains(.traitMonoSpace) == false else { return true }
        let name = "\(font.fontName) \(font.familyName)".lowercased()
        return name.contains("mono") || name.contains("menlo") || name.contains("courier")
    }

    func normalizedTextColor(from color: UIColor) -> UIColor {
        guard let components = rgbComponents(from: color) else { return color }
        if isNearGray(components, target: 17) {
            return .label
        }
        if isNearGray(components, target: 85) {
            return .secondaryLabel
        }
        return color
    }

    func rgbComponents(from color: UIColor) -> (red: CGFloat, green: CGFloat, blue: CGFloat)? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        return (red, green, blue)
    }

    func isNearGray(_ components: (red: CGFloat, green: CGFloat, blue: CGFloat), target: CGFloat) -> Bool {
        let normalizedTarget = target / 255
        let tolerance: CGFloat = 0.02
        return abs(components.red - normalizedTarget) <= tolerance
            && abs(components.green - normalizedTarget) <= tolerance
            && abs(components.blue - normalizedTarget) <= tolerance
    }

    func normalizeLinks(in attributed: NSMutableAttributedString, baseURL: URL) {
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

    func normalizeVisibleListMarkers(in attributed: NSMutableAttributedString) {
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

    func normalizeMediaAttachments(
        in attributed: NSMutableAttributedString,
        baseURL: URL,
        maxImageWidth: CGFloat
    ) {
        guard maxImageWidth > 0 else { return }

        var normalizedCount = 0
        var stickerFixedCount = 0
        var placeholderCount = 0
        var attachmentSummaries: [String] = []
        attributed.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributed.length)
        ) { value, _, _ in
            guard let attachment = value as? DTTextAttachment else { return }
            let contentURL = attachment.contentURL
            guard let imageURL = contentURL ?? attachmentSourceURL(from: attachment, baseURL: baseURL) else { return }

            if attachment.contentURL == nil {
                attachment.contentURL = imageURL
            }

            let isSticker = DetailAttachmentAttributes.hasClass("sticker", in: attachment.attributes) || isStickerImageURL(imageURL)
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
        }

        logDiagnostics(
            "已保留DTCoreText图片附件 count=\(normalizedCount) stickerFixed=\(stickerFixedCount) placeholder=\(placeholderCount) details=\(attachmentSummaries.prefix(6).joined(separator: " | "))"
        )
    }

    func attachmentSourceURL(from attachment: DTTextAttachment, baseURL: URL) -> URL? {
        if let source = DetailAttachmentAttributes.value(named: "src", in: attachment.attributes),
           let resolved = AvatarImageLoader.resolveImageURL(source, baseURL: baseURL) {
            return resolved
        }
        if let source = DetailAttachmentAttributes.value(named: "data-src", in: attachment.attributes)
            ?? DetailAttachmentAttributes.value(named: "data-original", in: attachment.attributes),
           let resolved = AvatarImageLoader.resolveImageURL(source, baseURL: baseURL) {
            return resolved
        }
        if let srcset = DetailAttachmentAttributes.value(named: "srcset", in: attachment.attributes),
           let source = preferredSourceFromSrcset(srcset) {
            return AvatarImageLoader.resolveImageURL(source, baseURL: baseURL)
        }
        return nil
    }
}
