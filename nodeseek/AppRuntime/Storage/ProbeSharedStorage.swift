import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// App 与小组件共用的探针存储，放在 App Group 里。
enum ProbeSharedStorage {
    nonisolated static let appGroupID = "group.com.mistj.nodeseek"
    nonisolated private static let migratedKey = "probe.migratedToAppGroup.v1"

    /// 签名里带了 App Group 才算共享；没有时 suite 只会落在本进程，等于没共享。
    nonisolated static var isAvailable: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil
    }

    /// App 用共享存储（没有 App Group 权限时退回本机存储）；小组件只读共享存储。
    nonisolated static func currentProcessDefaults() -> UserDefaults {
        if Bundle.main.bundleURL.pathExtension == "appex" { return widgetDefaults() }
        guard isAvailable, let group = UserDefaults(suiteName: appGroupID) else { return .standard }
        return group
    }

    nonisolated static func widgetDefaults() -> UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    /// App 还没迁移过（升级后没打开过 App）时，小组件提示先打开一次。
    nonisolated static func hasMigrated(_ defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: migratedKey)
    }

    /// App 启动时立即把旧版存在本机的探针配置和缓存搬到 App Group，不等进探针页；
    /// 第一次搬完通知小组件刷新，否则它要等下一次定时刷新才看得到数据。
    @MainActor
    static func prepareAtLaunch(legacy: UserDefaults = .standard) {
        guard isAvailable, let group = UserDefaults(suiteName: appGroupID) else { return }
        guard migrate(from: legacy, to: group) else { return }
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// 只搬一次，返回这次是否真的搬了。旧数据保留在本机存储里不删，万一要回退版本还能用。
    @discardableResult
    nonisolated static func migrate(from legacy: UserDefaults, to group: UserDefaults) -> Bool {
        guard !group.bool(forKey: migratedKey) else { return false }
        for (key, value) in legacy.dictionaryRepresentation() where key.hasPrefix("probe.") && group.object(forKey: key) == nil {
            group.set(value, forKey: key)
        }
        group.set(true, forKey: migratedKey)
        return true
    }
}
