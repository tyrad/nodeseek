//
//  DetailImageURLRules.swift
//  nodeseek
//
//  Created by Codex on 2026/5/6.
//

import Foundation

enum DetailSVGContentRules {
    static func isReportLikeSVG(_ data: Data, mimeType: String?) -> Bool {
        guard let svgText = String(data: data, encoding: .utf8),
              looksLikeSVG(svgText, mimeType: mimeType),
              let openingTag = svgOpeningTag(in: svgText) else {
            return false
        }

        let width = attribute("width", in: openingTag)
        let height = attribute("height", in: openingTag)
        let usesTextRelativeCanvas = [width, height].contains { value in
            guard let value else { return false }
            return value.range(of: #"^\d+(?:\.\d+)?(?:ch|em)$"#, options: [.regularExpression, .caseInsensitive]) != nil
        }
        guard usesTextRelativeCanvas else { return false }

        return tagCount(named: "text", in: svgText) + tagCount(named: "tspan", in: svgText) >= 8
    }

    private static func looksLikeSVG(_ text: String, mimeType: String?) -> Bool {
        if mimeType?.lowercased().contains("svg") == true {
            return true
        }

        let prefix = text.prefix(512).lowercased()
        return prefix.contains("<svg")
            || prefix.contains("</svg>")
            || (prefix.contains("<?xml") && prefix.contains("svg"))
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
              match.numberOfRanges >= 2 else {
            return nil
        }
        return source.substring(with: match.range(at: 1))
    }

    private static func tagCount(named tagName: String, in text: String) -> Int {
        let pattern = #"<\#(tagName)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return 0
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.numberOfMatches(in: text, options: [], range: range)
    }
}

enum DetailImageURLRules {
    static func isCheckPlaceReportSVG(_ url: URL) -> Bool {
        guard ["http", "https"].contains(url.scheme?.lowercased()),
              url.pathExtension.lowercased() == "svg",
              url.host?.lowercased() == "report.check.place" else {
            return false
        }

        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 2,
              ["ip", "hardware"].contains(components[0]),
              components[1].isEmpty == false else {
            return false
        }

        return true
    }

    static func containsCheckPlaceReportSVGURL(in text: String) -> Bool {
        let range = NSRange(location: 0, length: (text as NSString).length)
        return checkPlaceReportSVGURLRegex.firstMatch(in: text, options: [], range: range) != nil
    }

    static func checkPlaceReportSVGURLs(in text: String) -> [URL] {
        let source = text as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        var seen = Set<String>()
        var urls: [URL] = []

        for match in checkPlaceReportSVGURLRegex.matches(in: text, options: [], range: fullRange) {
            let rawURL = source.substring(with: match.range)
            guard let url = URL(string: rawURL), isCheckPlaceReportSVG(url) else { continue }
            let key = url.absoluteString.lowercased()
            guard seen.insert(key).inserted else { continue }
            urls.append(url)
        }

        return urls
    }

    private static let checkPlaceReportSVGURLRegex = try! NSRegularExpression(
        pattern: #"https?://report\.check\.place/(?:ip|hardware)/[A-Za-z0-9_-]+\.svg\b"#,
        options: [.caseInsensitive]
    )
}

extension DetailImageKind {
    static func resolved(isSticker: Bool, imageURL: URL?) -> DetailImageKind {
        if isSticker {
            return .sticker
        }
        return .normal
    }
}
