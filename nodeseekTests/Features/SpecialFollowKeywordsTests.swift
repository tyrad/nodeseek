//
//  SpecialFollowKeywordsTests.swift
//  nodeseekTests
//

import Testing
import UIKit
@testable import nodeseek

struct SpecialFollowKeywordsTests {
    @Test func storePersistsKeywordWithDefaultRedColor() throws {
        let suiteName = "special-follow-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SpecialFollowKeywordStore(userDefaults: defaults, storageKey: "keywords")

        try store.save(keyword: "  NodeImage  ")

        let reloaded = SpecialFollowKeywordStore(userDefaults: defaults, storageKey: "keywords")
        #expect(reloaded.keywords == [
            SpecialFollowKeyword(keyword: "NodeImage", colorHex: "#FF3B30")
        ])
    }

    @Test func importingValidJSONOverwritesSameKeywordIgnoringCase() throws {
        let store = makeStore()
        try store.save(keyword: "NodeImage", colorHex: "#FF3B30")
        let json = """
        [
          {"keyword": "nodeimage", "colorHex": "#34C759"},
          {"keyword": "VPS", "colorHex": "#007AFF"}
        ]
        """

        try store.importJSONData(Data(json.utf8))

        #expect(store.keywords == [
            SpecialFollowKeyword(keyword: "nodeimage", colorHex: "#34C759"),
            SpecialFollowKeyword(keyword: "VPS", colorHex: "#007AFF")
        ])
    }

    @Test func importingInvalidJSONKeepsExistingKeywords() throws {
        let store = makeStore()
        try store.save(keyword: "NodeImage", colorHex: "#FF3B30")
        let json = """
        [
          {"keyword": "", "colorHex": "#34C759"}
        ]
        """

        #expect(throws: SpecialFollowKeywordImportError.self) {
            try store.importJSONData(Data(json.utf8))
        }
        #expect(store.keywords == [
            SpecialFollowKeyword(keyword: "NodeImage", colorHex: "#FF3B30")
        ])
    }

    @Test func exportedJSONCanBeImportedByAnotherStore() throws {
        let source = makeStore()
        try source.save(keyword: "mist", colorHex: "#5856D6")
        let data = try source.exportJSONData()
        let target = makeStore()

        try target.importJSONData(data)

        #expect(target.keywords == [
            SpecialFollowKeyword(keyword: "mist", colorHex: "#5856D6")
        ])
    }

    @Test func highlighterColorsMatchingKeywordRanges() throws {
        let rules = [
            try SpecialFollowKeywordRule(keyword: "NodeImage", colorHex: "#34C759")
        ]
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 17),
            .foregroundColor: UIColor.label
        ]

        let text = SpecialFollowKeywordHighlighter.attributedText(
            string: "NodeImage 正式版发布",
            baseAttributes: attributes,
            rules: rules
        )

        let hitColor = try #require(text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor)
        let normalColor = try #require(text.attribute(.foregroundColor, at: 10, effectiveRange: nil) as? UIColor)
        #expect(hitColor.isEqual(UIColor(hex: "#34C759")))
        #expect(normalColor.isEqual(UIColor.label))
    }

    @Test func presetColorsAvoidLightColors() throws {
        #expect(SpecialFollowKeywordPresetColor.colors.count >= 6)
        for presetColor in SpecialFollowKeywordPresetColor.colors {
            let color = try #require(UIColor(hex: presetColor.colorHex))
            #expect(color.relativeLuminanceForTesting < 0.45)
        }
    }
}

private func makeStore() -> SpecialFollowKeywordStore {
    let suiteName = "special-follow-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return SpecialFollowKeywordStore(userDefaults: defaults, storageKey: "keywords")
}

private extension UIColor {
    var relativeLuminanceForTesting: CGFloat {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }
}
