import Foundation
import Testing

#if SWIFT_PACKAGE
@testable import NodeSeekCore
#else
@testable import nodeseek
#endif

struct NodeSeekWebDeepLinkTests {
    private func parse(_ string: String) throws -> PushNotificationRoute? {
        NodeSeekWebDeepLink.route(for: try #require(URL(string: string)))
    }

    private func open(_ target: String) throws -> PushNotificationRoute? {
        let encoded = try #require(target.addingPercentEncoding(withAllowedCharacters: .alphanumerics))
        return try parse("nsconnect://open?url=\(encoded)")
    }

    @Test func firstPageLinksAreEquivalent() throws {
        let expected = PushNotificationRoute.reply(postID: "893437", page: 1, floor: nil,
                                                    url: NodeSeekSite.postURL(id: "893437", page: 1))
        #expect(try parse("nsconnect://post/893437") == expected)
        #expect(try parse("nsconnect://post/893437-1") == expected)
        #expect(try open("https://www.nodeseek.com/post-893437-1") == expected)
        #expect(try open("http://NODESEEK.COM/post-893437?from=share") == expected)
    }

    @Test func bothFormsPreserveTheTargetFloor() throws {
        let expected = PushNotificationRoute.reply(postID: "1016685", page: 2, floor: "18",
                                                    url: NodeSeekSite.postURL(id: "1016685", page: 2))
        #expect(try parse("nsconnect://post/1016685-2?floor=18") == expected)
        #expect(try open("https://nodeseek.com/post-1016685-2#18") == expected)
    }

    @Test(arguments: ["https://example.com/path?q=1&b=2#part", "http://other.nodeseek.com/post-893437",
                      "https://nodeseek.com.example.org/post-893437", "https://nodeseek.com@example.org/post-893437"])
    func externalWebAddressesGoToSafari(_ address: String) throws {
        let target = try #require(URL(string: address))
        #expect(try open(address) == .externalWebPage(target))
    }

    @Test(arguments: ["ftp://nodeseek.com/post-893437", "ftp://example.com/file", "file:///tmp/example",
                      "javascript:void(0)", "//example.org/post-893437", "/post-893437", "https:///missing-host",
                      "https://www.nodeseek.com/board", "https://nodeseek.com/post-893437/extra"])
    func ignoresUnsupportedTargets(_ address: String) throws {
        #expect(try open(address) == nil)
    }

    @Test(arguments: ["nsconnect://post/abc", "nsconnect://post/893437-bad", "nsconnect://post/893437/extra",
                      "nsconnect://post/893437--2", "nsconnect://post/893437-2-3", "nsconnect://unknown/1",
                      "nsconnect://open", "nsconnect://open?url=", "https://www.nodeseek.com/post-893437",
                      "nsconnect://probe", "nsconnect://probe?node=1"])
    func ignoresInvalidOrUnownedRoutes(_ link: String) throws {
        #expect(try parse(link) == nil)
    }
}
