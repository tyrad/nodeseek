import XCTest
@testable import nodeseek

final class FeatureLocalizationTests: XCTestCase {
    func testSearchAndWidgetResourcesArePackagedInAllLanguages() throws {
        let widgetURL = try XCTUnwrap(Bundle.main.builtInPlugInsURL?.appendingPathComponent("ProbeWidget.appex"))
        let widget = try XCTUnwrap(Bundle(url: widgetURL))
        for (bundle, table) in [(Bundle.main, "Search"), (Bundle.main, "ProbeWidget"), (widget, "ProbeWidget"), (widget, "Localizable")] {
            var referenceKeys: Set<String>?
            for language in ["zh-Hans", "zh-Hant", "en"] {
                let path = try XCTUnwrap(bundle.path(forResource: table, ofType: "strings", inDirectory: nil, forLocalization: language))
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                let entries = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
                XCTAssertFalse(entries.isEmpty)
                XCTAssertTrue(entries.values.allSatisfy { !$0.isEmpty })
                let keys = Set(entries.keys)
                if let referenceKeys { XCTAssertEqual(keys, referenceKeys) }
                referenceKeys = keys
            }
        }
    }

    func testTranslatedSearchAndWidgetFormatStrings() throws {
        for (language, search, expiry) in [("zh-Hans", "搜索", "3 天后到期"), ("zh-Hant", "搜尋", "3 天後到期"), ("en", "Search", "Expires in 3 d")] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            XCTAssertEqual(bundle.localizedString(forKey: "搜索", value: nil, table: "Search"), search)
            let format = bundle.localizedString(forKey: "%ld 天后到期", value: nil, table: "ProbeWidget")
            XCTAssertEqual(String(format: format, 3), expiry)
            let traffic = bundle.localizedString(forKey: "流量 %@%%", value: nil, table: "ProbeWidget")
            XCTAssertTrue(String(format: traffic, "95").hasSuffix("95%"))
        }
    }
}
