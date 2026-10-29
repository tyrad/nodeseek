import Foundation

final class DetailImageDimmingSettings {
    static let shared = DetailImageDimmingSettings()
    static let didChangeNotification = Notification.Name("DetailImageDimmingSettings.didChange")

    private let userDefaults: UserDefaults
    private let storageKey: String

    init(userDefaults: UserDefaults = .standard, storageKey: String = "detailImageDimming.isEnabled") {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
    }

    var isEnabled: Bool { userDefaults.bool(forKey: storageKey) }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        userDefaults.set(enabled, forKey: storageKey)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
