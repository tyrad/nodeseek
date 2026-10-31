//
//  AppNavigationLayout.swift
//  nodeseek
//

import Foundation

/// App 整体布局：阅读模式把入口收在侧边栏，多 Tab 模式用底部标签栏切换首页、通知、我的。
enum AppNavigationLayout: String, CaseIterable {
    case reading
    case tabs

    var title: String {
        switch self {
        case .reading:
            return "阅读模式"
        case .tabs:
            return "多 Tab 模式"
        }
    }

    var subtitle: String {
        switch self {
        case .reading:
            return "入口收在侧边栏，\n列表满屏，专心看帖"
        case .tabs:
            return "首页、通知、我的\n在底部一点即达"
        }
    }
}

final class AppNavigationLayoutSettings {
    static let didChangeNotification = Notification.Name("AppNavigationLayoutSettings.didChange")
    static let shared = AppNavigationLayoutSettings()

    /// 从这个版本起，升级后弹一次布局选择页。
    static let choicePromptVersion = "1.2.0"

    private enum Keys {
        static let layout = "appNavigationLayout.layout"
        static let hasConfirmedChoice = "appNavigationLayout.hasConfirmedChoice"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    /// 没选过时保持阅读模式，与升级前一致。
    var layout: AppNavigationLayout {
        guard let rawValue = userDefaults.string(forKey: Keys.layout),
              let layout = AppNavigationLayout(rawValue: rawValue) else {
            return .reading
        }
        return layout
    }

    var hasConfirmedChoice: Bool {
        userDefaults.bool(forKey: Keys.hasConfirmedChoice)
    }

    func setLayout(_ layout: AppNavigationLayout) {
        guard self.layout != layout else { return }
        userDefaults.set(layout.rawValue, forKey: Keys.layout)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    func markChoiceConfirmed() {
        userDefaults.set(true, forKey: Keys.hasConfirmedChoice)
    }

    func needsChoicePrompt(currentVersion: String) -> Bool {
        guard hasConfirmedChoice == false else { return false }
        return currentVersion.compare(Self.choicePromptVersion, options: .numeric) != .orderedAscending
    }
}
