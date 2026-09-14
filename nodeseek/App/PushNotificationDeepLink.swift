import UIKit
import UserNotifications

@MainActor
enum PushNotificationDeepLink {
    private static var pending: PushNotificationRoute?
    private static weak var navigator: PushNotificationNavigating?

    static func attach(_ navigator: PushNotificationNavigating) {
        self.navigator = navigator
        if let pending {
            self.pending = nil
            navigator.open(pending)
        }
    }

    static func handle(userInfo: [AnyHashable: Any]) {
        guard let route = PushNotificationRoute(userInfo: userInfo) else { return }
        handle(route)
    }

    static func handle(_ route: PushNotificationRoute) {
        if let navigator {
            navigator.open(route)
        } else {
            pending = route
        }
    }
}

@MainActor
protocol PushNotificationNavigating: AnyObject {
    func open(_ route: PushNotificationRoute)
}

extension AppRouter: PushNotificationNavigating {
    func open(_ route: PushNotificationRoute) {
        switch route {
        case let .reply(postID, page, floor, url),
             let .atMe(postID, page, floor, url):
            let post = PostSummary(
                id: postID,
                title: "",
                url: url,
                authorName: "",
                nodeName: nil,
                replyCount: 0,
                lastActivityText: nil
            )
            let detail = PostDetailRouter.createModule(
                post: post,
                page: page,
                initialAnchorID: floor
            )
            push(detail)
        case .checkin:
            push(UserInfoWebViewController(profileURL: NodeSeekSite.boardURL, title: "签到"))
        case let .webPage(url, title):
            push(UserInfoWebViewController(profileURL: url, title: title))
        case .inbox:
            push(NotificationViewController())
        case .bannerOnly:
            break
        }
    }
}
