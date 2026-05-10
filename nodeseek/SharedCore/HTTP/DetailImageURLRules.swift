//
//  DetailImageURLRules.swift
//  nodeseek
//
//  Created by Codex on 2026/5/6.
//

import Foundation

enum DetailSVGContentRules {
    static func isReportLikeSVG(_ data: Data, mimeType: String?) -> Bool {
        guard let svgContent = SVGContentInspector.inspect(data: data, mimeType: mimeType) else {
            return false
        }

        let width = svgContent.metadata.width
        let height = svgContent.metadata.height
        let usesTextRelativeCanvas = [width, height].contains { value in
            guard let value else { return false }
            return value.range(of: #"^\d+(?:\.\d+)?(?:ch|em)$"#, options: [.regularExpression, .caseInsensitive]) != nil
        }
        guard usesTextRelativeCanvas else { return false }

        return tagCount(named: "text", in: svgContent.text) + tagCount(named: "tspan", in: svgContent.text) >= 8
    }

    private static func tagCount(named tagName: String, in text: String) -> Int {
        let pattern = #"<\#(tagName)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return 0
        }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        return regex.numberOfMatches(in: text, options: [], range: range)
    }
}

enum DetailImageURLRules {
    static func isLikelyImageURL(_ url: URL) -> Bool {
        guard ["http", "https"].contains(url.scheme?.lowercased()) else {
            return false
        }

        let imageExtensions: Set<String> = [
            "jpg",
            "jpeg",
            "png",
            "gif",
            "webp",
            "svg",
            "avif",
            "heic",
            "heif",
            "tiff",
            "bmp",
        ]
        if imageExtensions.contains(url.pathExtension.lowercased()) {
            return true
        }

        return url.lastPathComponent.lowercased() == "image"
    }

    static func isCheckPlaceReportSVG(_ url: URL) -> Bool {
        guard ["http", "https"].contains(url.scheme?.lowercased()),
              url.pathExtension.lowercased() == "svg",
              url.host?.lowercased() == "report.check.place"
        else {
            return false
        }

        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 2,
              ["ip", "hardware"].contains(components[0]),
              components[1].isEmpty == false
        else {
            return false
        }

        return true
    }

    static func containsLikelyImageURL(in text: String) -> Bool {
        imageURLs(in: text).isEmpty == false
    }

    static func imageURLs(in text: String) -> [URL] {
        let source = text as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        var seen = Set<String>()
        var urls: [URL] = []

        for match in httpURLRegex.matches(in: text, options: [], range: fullRange) {
            let rawURL = trimmingTrailingURLPunctuation(from: source.substring(with: match.range))
            guard let url = URL(string: rawURL), isLikelyImageURL(url) else { continue }
            let key = url.absoluteString.lowercased()
            guard seen.insert(key).inserted else { continue }
            urls.append(url)
        }

        return urls
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

    private static func trimmingTrailingURLPunctuation(from rawURL: String) -> String {
        var trimmedURL = rawURL
        while let lastScalar = trimmedURL.unicodeScalars.last,
              trailingURLPunctuation.contains(lastScalar) {
            trimmedURL.removeLast()
        }
        return trimmedURL
    }

    private static let checkPlaceReportSVGURLRegex = try! NSRegularExpression(
        pattern: #"https?://report\.check\.place/(?:ip|hardware)/[A-Za-z0-9_-]+\.svg\b"#,
        options: [.caseInsensitive]
    )

    private static let httpURLRegex = try! NSRegularExpression(
        pattern: #"https?://[^\s<>"']+"#,
        options: [.caseInsensitive]
    )

    private static let trailingURLPunctuation = CharacterSet(charactersIn: ".,;:!?)]}，。；：！？）】》」』")
}

extension DetailImageKind {
    static func resolved(isSticker: Bool, imageURL _: URL?) -> DetailImageKind {
        if isSticker {
            return .sticker
        }
        return .normal
    }
}
