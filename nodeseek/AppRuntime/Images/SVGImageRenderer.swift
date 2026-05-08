//
//  SVGImageRenderer.swift
//  nodeseek
//
//  Created by Codex on 2026/5/6.
//

import SVGKit
import UIKit

enum SVGImageRenderer {
    enum RenderError: LocalizedError {
        case unsupportedData

        var errorDescription: String? {
            switch self {
            case .unsupportedData:
                return "SVG/位图数据均无法解析"
            }
        }
    }

    static func image(from data: Data, size: CGSize) -> UIImage? {
        withSVGImage(from: data) { svgImage in
            svgImage.size = size
            return svgImage.uiImage
        }
    }

    static func imageSize(from data: Data, fallbackSize: CGSize, maxPixelSide: CGFloat) -> CGSize? {
        withSVGImage(from: data) { svgImage in
            let sourceSize = svgImage.hasSize() ? svgImage.size : fallbackSize
            return normalizedSize(sourceSize, fallbackSize: fallbackSize, maxPixelSide: maxPixelSide)
        }
    }

    static func renderAsync(data: Data, targetSize: CGSize) async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let image = image(from: data, size: targetSize) else {
                    continuation.resume(throwing: RenderError.unsupportedData)
                    return
                }
                continuation.resume(returning: image)
            }
        }
    }

    private static func withSVGImage<Result>(
        from data: Data,
        _ body: (SVGKImage) -> Result?
    ) -> Result? {
        renderQueue.sync {
            guard let svgImage = SVGKImage(data: SVGImageNormalizer.normalizedData(from: data)) else {
                return nil
            }
            return body(svgImage)
        }
    }

    private static let renderQueue = DispatchQueue(label: "com.nodeseek.app.svgkit.render")

    private static func normalizedSize(
        _ size: CGSize,
        fallbackSize: CGSize,
        maxPixelSide: CGFloat
    ) -> CGSize {
        let sourceWidth = size.width.isFinite && size.width > 0 ? size.width : fallbackSize.width
        let sourceHeight = size.height.isFinite && size.height > 0 ? size.height : fallbackSize.height

        guard max(sourceWidth, sourceHeight) > maxPixelSide else {
            return CGSize(width: sourceWidth, height: sourceHeight)
        }

        let scale = maxPixelSide / max(sourceWidth, sourceHeight)
        return CGSize(width: sourceWidth * scale, height: sourceHeight * scale)
    }
}

private enum SVGImageNormalizer {
    static func normalizedData(from data: Data) -> Data {
        guard var svgText = String(data: data, encoding: .utf8) else {
            return data
        }

        svgText = removingUnsupportedPatterns(in: svgText)
        svgText = replacingRGBAColors(in: svgText)
        svgText = replacingTemplateNumericExpressions(in: svgText)
        svgText = replacingQuotedCSSLengths(in: svgText)
        svgText = replacingFontRelativeLengths(in: svgText)

        return Data(svgText.utf8)
    }

    private static func removingUnsupportedPatterns(in svgText: String) -> String {
        var normalizedText = svgText
        let fullRange = NSRange(normalizedText.startIndex ..< normalizedText.endIndex, in: normalizedText)
        let matches = patternElementRegex.matches(in: normalizedText, options: [], range: fullRange)
        var patternIDs: [String] = []

        for match in matches.reversed() {
            if let idRange = Range(match.range(at: 1), in: normalizedText) {
                patternIDs.append(String(normalizedText[idRange]))
            }
            if let replaceRange = Range(match.range, in: normalizedText) {
                normalizedText.removeSubrange(replaceRange)
            }
        }

        for patternID in patternIDs {
            normalizedText = replacingPaintServerReferences(
                in: normalizedText,
                id: patternID,
                attribute: "fill"
            )
            normalizedText = replacingPaintServerReferences(
                in: normalizedText,
                id: patternID,
                attribute: "stroke"
            )
        }

        return normalizedText
    }

    private static func replacingPaintServerReferences(
        in svgText: String,
        id: String,
        attribute: String
    ) -> String {
        let escapedAttribute = NSRegularExpression.escapedPattern(for: attribute)
        let escapedPaintServer = NSRegularExpression.escapedPattern(for: "url(#\(id))")
        let pattern = #"\b"# + escapedAttribute + #"\s*=\s*(["'])"# + escapedPaintServer + #"\1"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return svgText
        }
        let fullRange = NSRange(svgText.startIndex ..< svgText.endIndex, in: svgText)
        return regex.stringByReplacingMatches(
            in: svgText,
            options: [],
            range: fullRange,
            withTemplate: "\(attribute)=\"none\""
        )
    }

    private static func replacingRGBAColors(in svgText: String) -> String {
        var normalizedText = svgText
        let fullRange = NSRange(normalizedText.startIndex ..< normalizedText.endIndex, in: normalizedText)
        let matches = rgbaAttributeRegex.matches(in: normalizedText, options: [], range: fullRange)

        for match in matches.reversed() {
            guard let attributeRange = Range(match.range(at: 1), in: normalizedText),
                  let quoteRange = Range(match.range(at: 2), in: normalizedText),
                  let redRange = Range(match.range(at: 3), in: normalizedText),
                  let greenRange = Range(match.range(at: 4), in: normalizedText),
                  let blueRange = Range(match.range(at: 5), in: normalizedText),
                  let alphaRange = Range(match.range(at: 6), in: normalizedText),
                  let replaceRange = Range(match.range, in: normalizedText),
                  let red = Double(normalizedText[redRange]),
                  let green = Double(normalizedText[greenRange]),
                  let blue = Double(normalizedText[blueRange]),
                  let alpha = Double(normalizedText[alphaRange])
            else {
                continue
            }

            let attribute = String(normalizedText[attributeRange])
            let quote = String(normalizedText[quoteRange])
            let replacement = replacementColorAttribute(
                name: attribute,
                quote: quote,
                red: red,
                green: green,
                blue: blue,
                alpha: alpha
            )
            normalizedText.replaceSubrange(replaceRange, with: replacement)
        }

        return normalizedText
    }

    private static func replacementColorAttribute(
        name: String,
        quote: String,
        red: Double,
        green: Double,
        blue: Double,
        alpha: Double
    ) -> String {
        let opacityAttribute: String
        switch name.lowercased() {
        case "stroke":
            opacityAttribute = "stroke-opacity"
        case "stop-color":
            opacityAttribute = "stop-opacity"
        default:
            opacityAttribute = "fill-opacity"
        }

        return "\(name)=\(quote)rgb(\(clampedColorComponent(red)),\(clampedColorComponent(green)),\(clampedColorComponent(blue)))\(quote) \(opacityAttribute)=\(quote)\(numberString(clampedAlpha(alpha)))\(quote)"
    }

    private static func replacingFontRelativeLengths(in svgText: String) -> String {
        var normalizedText = svgText
        let fontSize = baseFontSize(in: normalizedText)
        let chWidth = fontSize * 0.6
        let fullRange = NSRange(normalizedText.startIndex ..< normalizedText.endIndex, in: normalizedText)
        let matches = fontRelativeLengthRegex.matches(in: normalizedText, options: [], range: fullRange)

        for match in matches.reversed() {
            guard let valueRange = Range(match.range(at: 1), in: normalizedText),
                  let unitRange = Range(match.range(at: 2), in: normalizedText),
                  let value = Double(normalizedText[valueRange]),
                  let replaceRange = Range(match.range, in: normalizedText)
            else {
                continue
            }

            let factor = normalizedText[unitRange].lowercased() == "ch" ? chWidth : fontSize
            normalizedText.replaceSubrange(replaceRange, with: "\(numberString(value * factor))px")
        }

        return normalizedText
    }

    private static func clampedColorComponent(_ value: Double) -> Int {
        Int(min(max(value.rounded(), 0), 255))
    }

    private static func clampedAlpha(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private static func replacingTemplateNumericExpressions(in svgText: String) -> String {
        var normalizedText = svgText
        let fullRange = NSRange(normalizedText.startIndex ..< normalizedText.endIndex, in: normalizedText)
        let matches = templateNumericExpressionRegex.matches(in: normalizedText, options: [], range: fullRange)

        for match in matches.reversed() {
            guard let lhsRange = Range(match.range(at: 1), in: normalizedText),
                  let operatorRange = Range(match.range(at: 2), in: normalizedText),
                  let rhsRange = Range(match.range(at: 3), in: normalizedText),
                  let replaceRange = Range(match.range, in: normalizedText),
                  let lhs = Double(normalizedText[lhsRange]),
                  let rhs = Double(normalizedText[rhsRange])
            else {
                continue
            }

            let value: Double?
            switch normalizedText[operatorRange] {
            case "+":
                value = lhs + rhs
            case "-":
                value = lhs - rhs
            case "*":
                value = lhs * rhs
            case "/":
                value = rhs == 0 ? nil : lhs / rhs
            default:
                value = nil
            }

            guard let value, value.isFinite else { continue }
            normalizedText.replaceSubrange(replaceRange, with: numberString(value))
        }

        return normalizedText
    }

    private static func replacingQuotedCSSLengths(in svgText: String) -> String {
        var normalizedText = svgText
        let fullRange = NSRange(normalizedText.startIndex ..< normalizedText.endIndex, in: normalizedText)
        let matches = quotedCSSLengthRegex.matches(in: normalizedText, options: [], range: fullRange)

        for match in matches.reversed() {
            guard let prefixRange = Range(match.range(at: 1), in: normalizedText),
                  let valueRange = Range(match.range(at: 2), in: normalizedText),
                  let replaceRange = Range(match.range, in: normalizedText)
            else {
                continue
            }
            normalizedText.replaceSubrange(
                replaceRange,
                with: "\(normalizedText[prefixRange])\(normalizedText[valueRange])"
            )
        }

        return normalizedText
    }

    private static func baseFontSize(in svgText: String) -> Double {
        let fullRange = NSRange(svgText.startIndex ..< svgText.endIndex, in: svgText)
        guard let match = fontSizeRegex.firstMatch(in: svgText, options: [], range: fullRange),
              let valueRange = Range(match.range(at: 1), in: svgText),
              let fontSize = Double(svgText[valueRange]),
              fontSize.isFinite,
              fontSize > 0
        else {
            return 14
        }
        return fontSize
    }

    private static func numberString(_ value: Double) -> String {
        let rounded = (value * 1000).rounded() / 1000
        if rounded.rounded() == rounded {
            return String(Int(rounded))
        }
        return String(rounded)
    }

    private static let fontRelativeLengthRegex = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z])(-?\d+(?:\.\d+)?)(ch|em)\b"#,
        options: [.caseInsensitive]
    )

    private static let fontSizeRegex = try! NSRegularExpression(
        pattern: #"font-size\s*:\s*(\d+(?:\.\d+)?)px\b"#,
        options: [.caseInsensitive]
    )

    private static let templateNumericExpressionRegex = try! NSRegularExpression(
        pattern: #"\{\s*(-?\d+(?:\.\d+)?)\s*([+\-*/])\s*(-?\d+(?:\.\d+)?)\s*\}"#,
        options: []
    )

    private static let quotedCSSLengthRegex = try! NSRegularExpression(
        pattern: #"(:\s*)"(-?\d+(?:\.\d+)?(?:px|pt|em|ch|%)?)""#,
        options: [.caseInsensitive]
    )

    private static let patternElementRegex = try! NSRegularExpression(
        pattern: #"<pattern\b[^>]*\bid\s*=\s*['"]([^'"]+)['"][^>]*>[\s\S]*?</pattern>"#,
        options: [.caseInsensitive]
    )

    private static let rgbaAttributeRegex = try! NSRegularExpression(
        pattern: #"\b(fill|stroke|stop-color)\s*=\s*(["'])rgba\(\s*(\d+(?:\.\d+)?)\s*,\s*(\d+(?:\.\d+)?)\s*,\s*(\d+(?:\.\d+)?)\s*,\s*(\d?(?:\.\d+)?)\s*\)\2"#,
        options: [.caseInsensitive]
    )
}
