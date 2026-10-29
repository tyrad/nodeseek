import Foundation

final class DetailImageDimmingSettings {
    enum Level: String, CaseIterable {
        case light
        case standard
        case strong

        var title: String {
            switch self {
            case .light: return "轻"
            case .standard: return "标准"
            case .strong: return "强"
            }
        }

        var opacity: CGFloat {
            switch self {
            case .light: return 0.2
            case .standard: return 0.35
            case .strong: return 0.5
            }
        }
    }

    static let shared = DetailImageDimmingSettings()
    static let didChangeNotification = Notification.Name("DetailImageDimmingSettings.didChange")

    private let userDefaults: UserDefaults
    private let storageKey: String
    private let levelStorageKey: String

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "detailImageDimming.isEnabled",
        levelStorageKey: String = "detailImageDimming.level"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        self.levelStorageKey = levelStorageKey
    }

    /// 未设置过时默认开启，只在深色模式生效，对浅色用户无影响。
    var isEnabled: Bool {
        guard userDefaults.object(forKey: storageKey) != nil else { return true }
        return userDefaults.bool(forKey: storageKey)
    }

    var level: Level {
        userDefaults.string(forKey: levelStorageKey).flatMap(Level.init(rawValue:)) ?? .standard
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        userDefaults.set(enabled, forKey: storageKey)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    func setLevel(_ level: Level) {
        guard self.level != level else { return }
        userDefaults.set(level.rawValue, forKey: levelStorageKey)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
