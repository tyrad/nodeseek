import Foundation
import Testing

#if SWIFT_PACKAGE
@testable import NodeSeekCore
#else
@testable import nodeseek
#endif

struct NodeSeekWebDeepLinkTests {
    private func parse(_ string: String) throws -> PushNotificationRoute? {
        let url = try #require(URL(string: string))
        return NodeSeekWebDeepLink.route(for: url)
    }

    @Test func parsesPostLinkWithoutPage() throws {
        let route = try #require(try parse("nsconnect://post/139218"))
        guard case let .reply(postID, page, floor, url) = route else {
            Issue.record("nsconnect://post 应解析为帖子")
            return
        }
        #expect(postID == "139218")
        #expect(page == 1)
        #expect(floor == nil)
        #expect(url.absoluteString == "https://www.nodeseek.com/post-139218-1")
    }

    @Test func parsesPostLinkWithPageAndFloor() throws {
        let route = try #require(try parse("nsconnect://post/139218-3?floor=482913"))
        guard case let .reply(postID, page, floor, _) = route else {
            Issue.record("带页码与楼层的深链应解析为帖子")
            return
        }
        #expect(postID == "139218")
        #expect(page == 3)
        #expect(floor == "482913")
    }

    @Test func parsesOpenWithEncodedWebURL() throws {
        let web = "https://www.nodeseek.com/post-139218-2#482913"
        let encoded = try #require(web.addingPercentEncoding(withAllowedCharacters: .alphanumerics))

        let route = try #require(try parse("nsconnect://open?url=\(encoded)"))
        guard case let .reply(postID, page, floor, _) = route else {
            Issue.record("open?url= 应解析为帖子")
            return
        }
        #expect(postID == "139218")
        #expect(page == 2)
        #expect(floor == "482913")
    }

    @Test func ignoresInvalidRoutes() throws {
        for link in [
            "nsconnect://post/not-a-number",
            "nsconnect://unknown/1",
            "nsconnect://open?url=https%3A%2F%2Fexample.com%2Fpost-139218",
            "https://www.nodeseek.com/post-139218",
        ] {
            let route = try parse(link)
            #expect(route == nil, "\(link) 不应解析成帖子")
        }
    }

    @Test func leavesProbeWidgetLinkAlone() throws {
        for link in ["nsconnect://probe", "nsconnect://probe?node=1"] {
            let route = try parse(link)
            #expect(route == nil, "\(link) 应留给小组件")
        }
    }
}
