import Foundation

/// 保存 APNs device token，供设置页复制到 ns-apns。
final class PushNotificationTokenStore {
    static let shared = PushNotificationTokenStore()
    static let didChangeNotification = Notification.Name("PushNotificationTokenStore.didChange")

    private let defaults: UserDefaults
    private let tokenKey = "push.deviceToken.hex"
    private let errorKey = "push.deviceToken.error"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var deviceTokenHex: String? {
        defaults.string(forKey: tokenKey)
    }

    var lastError: String? {
        defaults.string(forKey: errorKey)
    }

    func update(deviceToken: Data) {
        defaults.set(Self.hexString(from: deviceToken), forKey: tokenKey)
        defaults.removeObject(forKey: errorKey)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    func updateRegistrationError(_ error: Error) {
        defaults.set(error.localizedDescription, forKey: errorKey)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    static func hexString(from data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
