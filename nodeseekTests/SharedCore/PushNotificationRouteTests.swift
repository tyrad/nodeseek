import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import NodeSeekCore
#else
@testable import nodeseek
#endif

struct PushNotificationRouteTests {
    @Test func parsesReplyFromNsApnsPayload() throws {
        let route = try #require(PushNotificationRoute(userInfo: [
            "type": "reply",
            "post_id": "758151",
            "floor": "13",
            "url": "https://www.nodeseek.com/post-758151-2#13",
        ]))
        guard case let .reply(postID, page, floor, url) = route else {
            Issue.record("expected reply")
            return
        }
        #expect(postID == "758151")
        #expect(page == 2)
        #expect(floor == "13")
        #expect(url.absoluteString == "https://www.nodeseek.com/post-758151-2#13")
    }

    @Test func infersPageFromFloorWhenURLHasNoPage() throws {
        let route = try #require(PushNotificationRoute(userInfo: [
            "type": "reply",
            "post_id": 100,
            "floor": 13,
        ]))
        guard case let .reply(_, page, floor, _) = route else {
            Issue.record("expected reply")
            return
        }
        #expect(page == 2)
        #expect(floor == "13")
    }

    @Test func mapsCheckinAndMessage() {
        #expect(PushNotificationRoute(userInfo: ["type": "checkin"]) == .checkin)
        #expect(PushNotificationRoute(userInfo: ["type": "message"]) == .inbox)
        #expect(PushNotificationRoute(userInfo: ["type": "at", "post_id": "1"]) != nil)
    }

    @Test func atMeListOpensWebPage() throws {
        let route = try #require(PushNotificationRoute(userInfo: [
            "type": "at",
            "url": "https://www.nodeseek.com/notification#/atMe",
        ]))
        guard case let .webPage(_, title) = route else {
            Issue.record("expected webPage for atMe list")
            return
        }
        #expect(title == "提到我")
    }

    @Test func mapsSystemReminderToHiddenHeaderWebPage() throws {
        let route = try #require(PushNotificationRoute(userInfo: [
            "type": "inbox",
            "url": "https://www.nodeseek.com/notification#/message?mode=talk&to=5230",
        ]))
        guard case let .webPage(url, title) = route else {
            Issue.record("expected webPage")
            return
        }
        #expect(url.absoluteString == "https://www.nodeseek.com/notification#/message?mode=talk&to=5230")
        #expect(title == "私信")
    }

    @Test func unknownTypeDoesNotNavigate() {
        #expect(PushNotificationRoute(userInfo: ["type": "other", "raw_text": "奇怪的通知"]) == .bannerOnly)
        #expect(PushNotificationRoute(userInfo: ["type": "unknown"]) == .bannerOnly)
    }
}
