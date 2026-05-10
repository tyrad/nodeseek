//
//  DTCoreTextHTMLContentRenderer+MediaSources.swift
//  nodeseek
//
//  Created by Codex on 2026/4/30.
//

import DTCoreText
import Foundation
import UIKit

extension DTCoreTextHTMLContentRenderer {
    func normalizeImageSources(in fragment: String, baseURL: URL) -> String {
        let source = fragment as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        let matches = Self.imageTagRegex.matches(in: fragment, options: [], range: fullRange)
        guard matches.isEmpty == false else { return fragment }

        let mutable = NSMutableString(string: fragment)
        for match in matches.reversed() {
            let tag = source.substring(with: match.range)
            guard let rawSource = preferredImageSource(in: tag),
                  let resolved = ImageURLResolver.resolve(rawSource, baseURL: baseURL) else { continue }

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

    func normalizeVideoStickerSources(in fragment: String, baseURL: URL) -> String {
        let source = fragment as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        let matches = Self.videoTagRegex.matches(in: fragment, options: [], range: fullRange)
        guard matches.isEmpty == false else { return fragment }

        let mutable = NSMutableString(string: fragment)
        for match in matches.reversed() {
            let tag = source.substring(with: match.range)
            guard let startTagMatch = firstMatch(Self.videoStartTagRegex, in: tag) else { continue }
            let startTag = (tag as NSString).substring(with: startTagMatch.range)
            guard hasStickerClass(in: startTag),
                  let rawSource = preferredVideoSource(in: tag),
                  let resolved = ImageURLResolver.resolve(rawSource, baseURL: baseURL) else { continue }

            let replacementStartTag = replacingOrAddingSource(
                in: startTag,
                source: resolved.absoluteString
            )
            let startRange = NSRange(
                location: match.range.location + startTagMatch.range.location,
                length: startTagMatch.range.length
            )
            mutable.replaceCharacters(in: startRange, with: replacementStartTag)
        }

        return mutable as String
    }

    func preferredImageSource(in tag: String) -> String? {
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

    func preferredSourceFromSrcset(_ srcset: String) -> String? {
        srcset.split(separator: ",").compactMap { candidate -> String? in
            let parts = candidate.split(whereSeparator: { $0.isWhitespace })
            return parts.first.map(String.init)
        }.last
    }

    func preferredVideoSource(in tag: String) -> String? {
        let source = tag as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        let matches = Self.sourceTagRegex.matches(in: tag, options: [], range: fullRange)
        let sources: [(url: String, type: String?)] = matches.compactMap { match in
            let sourceTag = source.substring(with: match.range)
            guard let url = attributeValue(Self.srcAttributeRegex, in: sourceTag),
                  url.isEmpty == false else { return nil }
            return (url, attributeValue(Self.typeAttributeRegex, in: sourceTag))
        }

        if let preferred = sources.first(where: { isIOSFriendlyVideoSource(url: $0.url, type: $0.type) }) {
            return preferred.url
        }
        if let first = sources.first {
            return first.url
        }
        return attributeValue(Self.srcAttributeRegex, in: tag)
    }

    func isIOSFriendlyVideoSource(url: String, type: String?) -> Bool {
        let lowerURL = url.lowercased()
        if lowerURL.hasSuffix(".mp4") || lowerURL.hasSuffix(".mov") || lowerURL.hasSuffix(".m4v") {
            return true
        }

        let lowerType = type?.lowercased() ?? ""
        return lowerType.contains("mp4") || lowerType.contains("quicktime")
    }

    func replacingOrAddingSource(in startTag: String, source: String) -> String {
        if let srcMatch = firstMatch(Self.srcAttributeRegex, in: startTag), srcMatch.numberOfRanges >= 3 {
            let valueRange = srcMatch.range(at: 2)
            guard valueRange.location != NSNotFound else { return startTag }
            let mutable = NSMutableString(string: startTag)
            mutable.replaceCharacters(in: valueRange, with: source)
            return mutable as String
        }

        var mutable = startTag
        let insertionIndex = mutable.index(before: mutable.endIndex)
        mutable.insert(contentsOf: " src=\"\(source)\"", at: insertionIndex)
        return mutable
    }

    func attributeValue(_ regex: NSRegularExpression, in tag: String) -> String? {
        guard let match = firstMatch(regex, in: tag), match.numberOfRanges >= 3 else { return nil }
        let source = tag as NSString
        let valueRange = match.range(at: 2)
        guard valueRange.location != NSNotFound else { return nil }
        return source.substring(with: valueRange)
    }

    func firstMatch(_ regex: NSRegularExpression, in string: String) -> NSTextCheckingResult? {
        regex.firstMatch(
            in: string,
            options: [],
            range: NSRange(location: 0, length: (string as NSString).length)
        )
    }

    func hasStickerClass(in tag: String) -> Bool {
        guard let classValue = attributeValue(Self.classAttributeRegex, in: tag) else { return false }
        return classValue.split(whereSeparator: { $0.isWhitespace }).contains { $0 == "sticker" }
    }

    func isStickerImageURL(_ url: URL?) -> Bool {
        StickerImageRules.isStickerURL(url)
    }
}
