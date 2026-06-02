//
//  PostListSearchEntrySettings.swift
//  nodeseek
//
//  Created by Codex on 2026/6/2.
//

import Foundation

final class PostListSearchEntrySettings {
    static let didChangeNotification = Notification.Name("PostListSearchEntrySettings.didChange")
    static let shared = PostListSearchEntrySettings()

    private let userDefaults: UserDefaults
    private let storageKey: String

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "postListSearchEntry.showsTopSearchEntry"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
    }

    var showsTopSearchEntry: Bool {
        guard userDefaults.object(forKey: storageKey) != nil else {
            return false
        }
        return userDefaults.bool(forKey: storageKey)
    }

    func setShowsTopSearchEntry(_ showsTopSearchEntry: Bool) {
        guard self.showsTopSearchEntry != showsTopSearchEntry else { return }
        userDefaults.set(showsTopSearchEntry, forKey: storageKey)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
