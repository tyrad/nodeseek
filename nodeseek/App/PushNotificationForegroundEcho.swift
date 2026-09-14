import UserNotifications

/// 前台收到远程推送时，再发一条本地通知，保证横幅能出来。
enum PushNotificationForegroundEcho {
    static let flagKey = "ns_local_echo"

    static func isEcho(_ userInfo: [AnyHashable: Any]) -> Bool {
        switch userInfo[flagKey] {
        case let value as Int:
            return value != 0
        case let value as Bool:
            return value
        case let value as String:
            return value == "1" || value.lowercased() == "true"
        default:
            return false
        }
    }

    static func schedule(from notification: UNNotification) {
        let source = notification.request.content
        let content = UNMutableNotificationContent()
        content.title = source.title
        content.subtitle = source.subtitle
        content.body = source.body
        content.sound = source.sound ?? .default
        var userInfo = source.userInfo
        userInfo[flagKey] = 1
        content.userInfo = userInfo
        content.threadIdentifier = source.threadIdentifier

        let request = UNNotificationRequest(
            identifier: "local-\(notification.request.identifier)-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.2, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }
}
