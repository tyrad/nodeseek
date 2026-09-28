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

    @Test(arguments: ["at", "atme", "mention", "notification", "system", "inbox"])
    func atMeListOpensNativeTab(type: String) {
        #expect(PushNotificationRoute(userInfo: [
            "type": type,
            "url": "https://www.nodeseek.com/notification#/atMe",
        ]) == .atMeList)
    }

    @Test(arguments: ["reply", "notification", "system", "inbox"])
    func replyListOpensNativeTab(type: String) {
        #expect(PushNotificationRoute(userInfo: [
            "type": type,
            "url": "https://nodeseek.com/notification#/reply",
        ]) == .replyList)
    }

    @Test func unrelatedURLsKeepExistingRouting() throws {
        for address in [
            "https://www.nodeseek.com/space/1#/atMe",
            "https://www.nodeseek.com/notification#/replyExtra",
            "https://www.nodeseek.com/notification#/message?mode=list",
        ] {
            let url = try #require(URL(string: address))
            #expect(PushNotificationRoute(userInfo: ["type": "system", "url": address])
                == .webPage(url: url, title: address.contains("atMe") ? "提到我" : "系统提醒"))
        }
        #expect(PushNotificationRoute(userInfo: [
            "type": "system", "url": "https://example.com/notification#/reply",
        ]) == .inbox)
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

    @Test func mapsOfficialPrivateMessage() throws {
        let route = try #require(PushNotificationRoute(userInfo: [
            "type": "message",
            "author": "ICMP不可达喵",
            "url": "https://www.nodeseek.com/notification#/message?mode=talk&to=28302",
        ]))
        guard case let .webPage(url, title) = route else {
            Issue.record("expected webPage for private message")
            return
        }
        #expect(url.absoluteString == "https://www.nodeseek.com/notification#/message?mode=talk&to=28302")
        #expect(title == "私信")
    }

    @Test func mapsLegacyOtherPrivateMessageByTalkURL() throws {
        let route = try #require(PushNotificationRoute(userInfo: [
            "type": "other",
            "url": "https://www.nodeseek.com/notification#/message?mode=talk&to=28302",
            "raw_text": "ICMP不可达喵给你发了一条私信，点击查看",
        ]))
        guard case let .webPage(url, title) = route else {
            Issue.record("expected webPage for legacy other private message")
            return
        }
        #expect(url.absoluteString == "https://www.nodeseek.com/notification#/message?mode=talk&to=28302")
        #expect(title == "私信")
    }
}
