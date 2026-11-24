import SafariServices
import UIKit
import UserNotifications

@MainActor
enum PushNotificationDeepLink {
    private static var pending: PushNotificationRoute?
    private static weak var navigator: PushNotificationNavigating?

    private static var lastResponse: PushResponseIdentity?

    static func attach(_ navigator: PushNotificationNavigating) {
        self.navigator = navigator
        if let pending {
            self.pending = nil
            navigator.open(pending)
        }
    }

    static func handle(_ response: UNNotificationResponse) {
        let notification = response.notification
        guard let route = PushNotificationRoute(userInfo: notification.request.content.userInfo) else { return }
        // 冷启动时 Scene 和通知代理可能同时收到同一次点按。
        let identity = PushResponseIdentity(requestID: notification.request.identifier,
                                            deliveredAt: notification.date,
                                            actionID: response.actionIdentifier)
        guard identity != lastResponse else { return }
        lastResponse = identity
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

private struct PushResponseIdentity: Equatable {
    let requestID: String
    let deliveredAt: Date
    let actionID: String
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
        case let .externalWebPage(url):
            guard var presenter = window?.rootViewController else { return }
            while let presented = presenter.presentedViewController {
                presenter = presented
            }
            presenter.present(SFSafariViewController(url: url), animated: true)
        case let .webPage(url, title):
            push(UserProfileRouter.makeViewController(profileURL: url, title: title))
        case .inbox, .atMeList:
            push(NotificationViewController(initialTab: .atMe))
        case .replyList:
            push(NotificationViewController(initialTab: .reply))
        case let .probe(link):
            openProbe(link)
        case .bannerOnly:
            break
        }
    }

    private func openProbe(_ link: ProbeWidgetLink) {
        guard let navigationController else { return }
        ProbeMonitorViewController.show(link, in: navigationController)
    }
}
