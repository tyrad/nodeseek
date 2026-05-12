//
//  PostSignatureDisplaySettings.swift
//  nodeseek
//
//  Created by Codex on 2026/5/12.
//

import Foundation

final class PostSignatureDisplaySettings {
    static let didChangeNotification = Notification.Name("PostSignatureDisplaySettings.didChange")
    static let shared = PostSignatureDisplaySettings()

    private let userDefaults: UserDefaults
    private let storageKey: String

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "postSignatureDisplay.showsSignatures"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
    }

    var showsSignatures: Bool {
        guard userDefaults.object(forKey: storageKey) != nil else {
            return true
        }
        return userDefaults.bool(forKey: storageKey)
    }

    func setShowsSignatures(_ showsSignatures: Bool) {
        guard self.showsSignatures != showsSignatures else { return }
        userDefaults.set(showsSignatures, forKey: storageKey)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
