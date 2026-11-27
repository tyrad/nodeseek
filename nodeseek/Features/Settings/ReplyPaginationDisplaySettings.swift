//
//  ReplyPaginationDisplaySettings.swift
//  nodeseek
//

import Foundation

/// 详情页主帖下方的回复分页条开关，未设置时默认显示。
final class ReplyPaginationDisplaySettings {
    static let didChangeNotification = Notification.Name("ReplyPaginationDisplaySettings.didChange")
    static let shared = ReplyPaginationDisplaySettings()

    private let userDefaults: UserDefaults
    private let storageKey: String

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "replyPaginationDisplay.showsInlineBar"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
    }

    var showsInlineBar: Bool {
        guard userDefaults.object(forKey: storageKey) != nil else {
            return true
        }
        return userDefaults.bool(forKey: storageKey)
    }

    func setShowsInlineBar(_ showsInlineBar: Bool) {
        guard self.showsInlineBar != showsInlineBar else { return }
        userDefaults.set(showsInlineBar, forKey: storageKey)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
