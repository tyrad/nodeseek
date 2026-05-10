//
//  SVGContentInspector.swift
//  nodeseek
//

import Foundation

struct SVGContent {
    let data: Data
    let text: String
    let mimeType: String?
    let metadata: SVGContentMetadata
}

struct SVGContentMetadata {
    let openingTag: String
    let width: String?
    let height: String?
    let viewBox: String?
}

enum SVGContentInspector {
    static func inspect(data: Data, mimeType: String? = nil) -> SVGContent? {
        guard let text = String(data: data, encoding: .utf8),
              looksLikeSVG(text, mimeType: mimeType),
              let metadata = metadata(in: text)
        else {
            return nil
        }

        return SVGContent(data: data, text: text, mimeType: mimeType, metadata: metadata)
    }

    static func looksLikeSVG(_ data: Data, mimeType: String? = nil) -> Bool {
        guard let prefix = String(data: data.prefix(512), encoding: .utf8) else {
            return false
        }
        return looksLikeSVG(prefix, mimeType: mimeType)
    }

    static func looksLikeSVG(_ text: String, mimeType: String? = nil) -> Bool {
        if mimeType?.lowercased().contains("svg") == true {
            return true
        }

        let prefix = text.prefix(512).lowercased()
        return prefix.contains("<svg")
            || prefix.contains("</svg>")
            || (prefix.contains("<?xml") && prefix.contains("svg"))
    }

    private static func metadata(in text: String) -> SVGContentMetadata? {
        guard let openingTag = svgOpeningTag(in: text) else {
            return nil
        }

        return SVGContentMetadata(
            openingTag: openingTag,
            width: attribute("width", in: openingTag),
            height: attribute("height", in: openingTag),
            viewBox: attribute("viewBox", in: openingTag)
        )
    }

    private static func svgOpeningTag(in text: String) -> String? {
        guard let range = text.range(of: #"<svg\b[^>]*>"#, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        return String(text[range])
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = #"\b\#(name)\s*=\s*['"]([^'"]*)['"]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let source = tag as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        guard let match = regex.firstMatch(in: tag, options: [], range: fullRange),
              match.numberOfRanges >= 2
        else {
            return nil
        }
        return source.substring(with: match.range(at: 1))
    }
}
