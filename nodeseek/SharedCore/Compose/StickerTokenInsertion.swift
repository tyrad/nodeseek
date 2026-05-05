//
//  StickerTokenInsertion.swift
//  nodeseek
//
//  Created by Codex on 2026/5/3.
//

import Foundation

enum StickerTokenInsertion {
    struct Result: Equatable {
        let text: String
        let selectedRange: NSRange
    }

    nonisolated static func inserting(
        token: String,
        into text: String,
        selectedRange: NSRange
    ) -> Result {
        let source = text as NSString
        let safeRange = clampedRange(selectedRange, textLength: source.length)
        let marker = ":\(token):"
        let replacement = boundedToken(marker, in: source, replacing: safeRange)
        let updated = source.replacingCharacters(in: safeRange, with: replacement)
        let caretLocation = safeRange.location + (replacement as NSString).length
        return Result(
            text: updated,
            selectedRange: NSRange(location: caretLocation, length: 0)
        )
    }

    private nonisolated static func clampedRange(_ range: NSRange, textLength: Int) -> NSRange {
        let location = min(max(0, range.location), textLength)
        let upperBound = min(max(location, range.location + range.length), textLength)
        return NSRange(location: location, length: upperBound - location)
    }

    private nonisolated static func boundedToken(
        _ token: String,
        in source: NSString,
        replacing range: NSRange
    ) -> String {
        let needsLeadingSpace = range.location > 0
            && isWhitespace(source.character(at: range.location - 1)) == false
        let rangeEnd = range.location + range.length
        let needsTrailingSpace = rangeEnd >= source.length
            || isWhitespace(source.character(at: rangeEnd)) == false

        return "\(needsLeadingSpace ? " " : "")\(token)\(needsTrailingSpace ? " " : "")"
    }

    private nonisolated static func isWhitespace(_ unichar: unichar) -> Bool {
        guard let scalar = UnicodeScalar(Int(unichar)) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }
}
