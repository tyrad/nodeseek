//
//  SpecialFollowKeywords.swift
//  nodeseek
//

import Foundation
import UIKit

struct SpecialFollowKeyword: Codable, Equatable, Sendable {
    static let defaultColorHex = "#FF3B30"

    var keyword: String
    var colorHex: String

    init(keyword: String, colorHex: String = Self.defaultColorHex) {
        self.keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        self.colorHex = UIColor.normalizedHexString(colorHex) ?? Self.defaultColorHex
    }

    var normalizedKeyword: String {
        Self.normalizedKeyword(keyword)
    }

    static func normalizedKeyword(_ keyword: String) -> String {
        keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum SpecialFollowKeywordImportError: Error, Equatable {
    case invalidFormat
}

struct SpecialFollowKeywordRule: Equatable {
    let keyword: String
    let color: UIColor

    init(keyword: String, colorHex: String) throws {
        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKeyword.isEmpty, let color = UIColor(hex: colorHex) else {
            throw SpecialFollowKeywordImportError.invalidFormat
        }
        self.keyword = trimmedKeyword
        self.color = color
    }
}

struct SpecialFollowKeywordPresetColor: Equatable {
    let name: String
    let colorHex: String

    static let colors: [SpecialFollowKeywordPresetColor] = [
        SpecialFollowKeywordPresetColor(name: "红色", colorHex: "#C62828"),
        SpecialFollowKeywordPresetColor(name: "橙色", colorHex: "#C2410C"),
        SpecialFollowKeywordPresetColor(name: "琥珀", colorHex: "#B45309"),
        SpecialFollowKeywordPresetColor(name: "绿色", colorHex: "#15803D"),
        SpecialFollowKeywordPresetColor(name: "青色", colorHex: "#0F766E"),
        SpecialFollowKeywordPresetColor(name: "蓝色", colorHex: "#1D4ED8"),
        SpecialFollowKeywordPresetColor(name: "紫色", colorHex: "#6D28D9"),
        SpecialFollowKeywordPresetColor(name: "玫红", colorHex: "#BE185D")
    ]
}

final class SpecialFollowKeywordStore {
    static let didChangeNotification = Notification.Name("SpecialFollowKeywordStore.didChangeNotification")
    static let shared = SpecialFollowKeywordStore()

    private let userDefaults: UserDefaults
    private let storageKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "specialFollowKeywords"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    var keywords: [SpecialFollowKeyword] {
        guard let data = userDefaults.data(forKey: storageKey) else { return [] }
        return (try? decoder.decode([SpecialFollowKeyword].self, from: data)) ?? []
    }

    var count: Int {
        keywords.count
    }

    var rules: [SpecialFollowKeywordRule] {
        keywords.compactMap { try? SpecialFollowKeywordRule(keyword: $0.keyword, colorHex: $0.colorHex) }
    }

    func save(keyword: String, colorHex: String = SpecialFollowKeyword.defaultColorHex) throws {
        let validated = try validatedKeyword(keyword: keyword, colorHex: colorHex)
        var nextKeywords = keywords
        upsert(validated, into: &nextKeywords)
        persist(nextKeywords)
    }

    func delete(keyword: String) {
        let normalized = SpecialFollowKeyword.normalizedKeyword(keyword)
        let nextKeywords = keywords.filter { $0.normalizedKeyword != normalized }
        persist(nextKeywords)
    }

    func importJSONData(_ data: Data) throws {
        let imported: [SpecialFollowKeyword]
        do {
            imported = try decoder.decode([SpecialFollowKeyword].self, from: data)
        } catch {
            throw SpecialFollowKeywordImportError.invalidFormat
        }

        let validated = try imported.map {
            try validatedKeyword(keyword: $0.keyword, colorHex: $0.colorHex)
        }

        var nextKeywords = keywords
        validated.forEach { upsert($0, into: &nextKeywords) }
        persist(nextKeywords)
    }

    func exportJSONData() throws -> Data {
        try encoder.encode(keywords)
    }

    private func validatedKeyword(keyword: String, colorHex: String) throws -> SpecialFollowKeyword {
        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKeyword.isEmpty, let normalizedColor = UIColor.normalizedHexString(colorHex) else {
            throw SpecialFollowKeywordImportError.invalidFormat
        }
        return SpecialFollowKeyword(keyword: trimmedKeyword, colorHex: normalizedColor)
    }

    private func upsert(_ keyword: SpecialFollowKeyword, into keywords: inout [SpecialFollowKeyword]) {
        if let index = keywords.firstIndex(where: { $0.normalizedKeyword == keyword.normalizedKeyword }) {
            keywords[index] = keyword
        } else {
            keywords.append(keyword)
        }
    }

    private func persist(_ keywords: [SpecialFollowKeyword]) {
        guard let data = try? encoder.encode(keywords) else { return }
        userDefaults.set(data, forKey: storageKey)
        let postNotification = {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
        if Thread.isMainThread {
            postNotification()
        } else {
            DispatchQueue.main.async(execute: postNotification)
        }
    }
}

enum SpecialFollowKeywordHighlighter {
    static func attributedText(
        string: String,
        baseAttributes: [NSAttributedString.Key: Any],
        rules: [SpecialFollowKeywordRule]
    ) -> NSAttributedString {
        let attributedText = NSMutableAttributedString(string: string, attributes: baseAttributes)
        applyHighlight(to: attributedText, rules: rules)
        return attributedText
    }

    static func applyHighlight(
        to attributedText: NSMutableAttributedString,
        rules: [SpecialFollowKeywordRule]
    ) {
        guard attributedText.length > 0, !rules.isEmpty else { return }
        let fullRange = NSRange(location: 0, length: attributedText.length)
        let source = attributedText.string as NSString

        for rule in rules {
            let keyword = rule.keyword as NSString
            guard keyword.length > 0 else { continue }

            var searchRange = fullRange
            while searchRange.location < attributedText.length {
                let range = source.range(
                    of: rule.keyword,
                    options: [.caseInsensitive, .diacriticInsensitive],
                    range: searchRange
                )
                guard range.location != NSNotFound else { break }

                attributedText.addAttribute(.backgroundColor, value: rule.color, range: range)
                attributedText.addAttribute(.foregroundColor, value: UIColor.white, range: range)
                let nextLocation = range.location + max(range.length, 1)
                searchRange = NSRange(
                    location: nextLocation,
                    length: attributedText.length - nextLocation
                )
            }
        }
    }
}

extension UIColor {
    convenience init?(hex: String) {
        guard let normalized = UIColor.normalizedHexString(hex) else { return nil }
        let hexValue = String(normalized.dropFirst())
        guard let value = UInt64(hexValue, radix: 16) else { return nil }

        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat
        if hexValue.count == 6 {
            red = CGFloat((value & 0xFF0000) >> 16) / 255
            green = CGFloat((value & 0x00FF00) >> 8) / 255
            blue = CGFloat(value & 0x0000FF) / 255
            alpha = 1
        } else {
            red = CGFloat((value & 0xFF000000) >> 24) / 255
            green = CGFloat((value & 0x00FF0000) >> 16) / 255
            blue = CGFloat((value & 0x0000FF00) >> 8) / 255
            alpha = CGFloat(value & 0x000000FF) / 255
        }

        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }

    static func normalizedHexString(_ string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#") else { return nil }
        let body = String(trimmed.dropFirst())
        guard body.count == 6 || body.count == 8 else { return nil }
        guard body.allSatisfy({ $0.isHexDigit }) else { return nil }
        return "#\(body.uppercased())"
    }

    func specialFollowHexString() -> String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(
            format: "#%02X%02X%02X",
            Int(round(red * 255)),
            Int(round(green * 255)),
            Int(round(blue * 255))
        )
    }
}
