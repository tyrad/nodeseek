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

/// 多 Tab 模式底部栏可放的入口。
enum MainTabItem: String, CaseIterable {
    case home
    case notification
    case recent
    case discussions
    case collections
    case comments
    case search
    case me

    /// 默认组合，和最初的多 Tab 模式一致。
    static let defaultItems: [MainTabItem] = [.home, .notification, .me]
    /// 超过 5 个系统会折叠成「更多」，标签也会过挤。
    static let maximumCount = 5

    var title: String {
        switch self {
        case .home: return "首页"
        case .notification: return "通知"
        case .recent: return "最近浏览"
        case .discussions: return "我的帖子"
        case .collections: return "我的收藏"
        case .comments: return "我的评论"
        case .search: return "搜一搜"
        case .me: return "我的"
        }
    }

    var symbolName: String {
        switch self {
        case .home: return "house"
        case .notification: return "bell"
        case .recent: return "clock"
        case .discussions: return "doc.text"
        case .collections: return "star"
        case .comments: return "bubble.left"
        case .search: return "magnifyingglass"
        case .me: return "person"
        }
    }

    /// 首页固定最左、我的固定最右；设置入口在「我的」，不能移除。
    var isFixed: Bool {
        self == .home || self == .me
    }

    var accessibilityIdentifier: String {
        "main-tab-\(rawValue)"
    }

    /// 纠正存储或编辑结果：首页在前、我的在后、去重、最多 5 项。
    static func normalized(_ items: [MainTabItem]) -> [MainTabItem] {
        var seen: Set<MainTabItem> = [.home, .me]
        var middle: [MainTabItem] = []
        for item in items where seen.insert(item).inserted {
            middle.append(item)
        }
        return [.home] + middle.prefix(maximumCount - 2) + [.me]
    }
}

final class AppNavigationLayoutSettings {
    static let didChangeNotification = Notification.Name("AppNavigationLayoutSettings.didChange")
    static let tabItemsDidChangeNotification = Notification.Name("AppNavigationLayoutSettings.tabItemsDidChange")
    static let shared = AppNavigationLayoutSettings()

    /// 从这个版本起，升级后弹一次布局选择页。
    static let choicePromptVersion = "1.2.0"

    private enum Keys {
        static let layout = "appNavigationLayout.layout"
        static let hasConfirmedChoice = "appNavigationLayout.hasConfirmedChoice"
        static let tabItems = "appNavigationLayout.tabItems"
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

    /// 多 Tab 模式底部栏；切回阅读模式时保留。
    var tabItems: [MainTabItem] {
        guard let rawValues = userDefaults.stringArray(forKey: Keys.tabItems) else {
            return MainTabItem.defaultItems
        }
        return MainTabItem.normalized(rawValues.compactMap(MainTabItem.init(rawValue:)))
    }

    func setTabItems(_ items: [MainTabItem]) {
        let normalized = MainTabItem.normalized(items)
        guard normalized != tabItems else { return }
        userDefaults.set(normalized.map(\.rawValue), forKey: Keys.tabItems)
        NotificationCenter.default.post(name: Self.tabItemsDidChangeNotification, object: self)
    }

    func markChoiceConfirmed() {
        userDefaults.set(true, forKey: Keys.hasConfirmedChoice)
    }

    func needsChoicePrompt(currentVersion: String) -> Bool {
        guard hasConfirmedChoice == false else { return false }
        return currentVersion.compare(Self.choicePromptVersion, options: .numeric) != .orderedAscending
    }
}
