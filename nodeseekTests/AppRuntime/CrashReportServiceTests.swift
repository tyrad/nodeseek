import XCTest
@testable import nodeseek

@MainActor
final class CrashReportServiceTests: XCTestCase {
    func testAppEnablesAutomaticUploadAndUsesMatchingFirebaseConfiguration() throws {
        let bundle = Bundle(for: AppDelegate.self)
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "FirebaseCrashlyticsCollectionEnabled") as? Bool, true)
        let url = try XCTUnwrap(bundle.url(forResource: "GoogleService-Info", withExtension: "plist"))
        let config = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        XCTAssertEqual(config["BUNDLE_ID"] as? String, bundle.bundleIdentifier)
    }
}
