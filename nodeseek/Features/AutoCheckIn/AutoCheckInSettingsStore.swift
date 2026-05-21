//
//  AutoCheckInSettingsStore.swift
//  nodeseek
//

import Foundation

final class AutoCheckInSettingsStore {
    static let didChangeNotification = Notification.Name("AutoCheckInSettingsStore.didChangeNotification")
    static let shared = AutoCheckInSettingsStore()

    private let userDefaults: UserDefaults
    private let storageKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(userDefaults: UserDefaults = .standard, storageKey: String = "autoCheckIn.settings") {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
    }

    var settings: AutoCheckInSettings {
        guard let data = userDefaults.data(forKey: storageKey),
              let decoded = try? decoder.decode(AutoCheckInSettings.self, from: data) else {
            return .default
        }
        return decoded
    }

    var summary: String {
        let current = settings
        guard current.isEnabled else { return "未开启" }
        return "已开启 · \(current.mode.displayName)"
    }

    func setEnabled(_ isEnabled: Bool) {
        var next = settings
        guard next.isEnabled != isEnabled else { return }
        next.isEnabled = isEnabled
        persist(next)
    }

    func setMode(_ mode: AutoCheckInMode) {
        var next = settings
        guard next.mode != mode else { return }
        next.mode = mode
        persist(next)
    }

    private func persist(_ settings: AutoCheckInSettings) {
        guard let data = try? encoder.encode(settings) else {
            AppLog.error(.autoCheckIn, "settings persist failed: encode")
            return
        }
        userDefaults.set(data, forKey: storageKey)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
