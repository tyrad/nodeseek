import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// 探针配置和最后一次成功快照的本地存储。只保存面板地址、显示偏好和监控数据，不保存任何凭证。
/// App 和小组件通过 App Group 共用同一份数据，见 `ProbeSharedStorage`。
@MainActor
final class ProbeInstanceStore {
    static let shared = ProbeInstanceStore(defaults: ProbeSharedStorage.currentProcessDefaults())
    static let didChangeNotification = Notification.Name("ProbeInstanceStore.didChange")

    private enum Key {
        static let instances = "probe.instances.v1"
        static let snapshotPrefix = "probe.snapshot.v1."
        static let density = "probe.list.density"
        static let sort = "probe.list.sort"
        static let refreshInterval = "probe.refresh.interval"
    }

    private let defaults: UserDefaults
    private(set) var instances: [ProbeInstance]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Key.instances),
           let decoded = try? JSONDecoder().decode([ProbeInstance].self, from: data) {
            instances = decoded
        } else {
            instances = []
        }
    }

    func instance(id: UUID) -> ProbeInstance? {
        instances.first { $0.id == id }
    }

    func upsert(_ instance: ProbeInstance) {
        if let index = instances.firstIndex(where: { $0.id == instance.id }) {
            instances[index] = instance
        } else {
            instances.append(instance)
        }
        persist()
    }

    func remove(id: UUID) {
        instances.removeAll { $0.id == id }
        defaults.removeObject(forKey: Key.snapshotPrefix + id.uuidString)
        persist()
    }

    func snapshot(for id: UUID) -> ProbeSnapshot? {
        guard let data = defaults.data(forKey: Key.snapshotPrefix + id.uuidString) else { return nil }
        return try? JSONDecoder().decode(ProbeSnapshot.self, from: data)
    }

    func saveSnapshot(_ snapshot: ProbeSnapshot, for id: UUID) {
        guard instance(id: id) != nil, let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Key.snapshotPrefix + id.uuidString)
    }

    /// nil 表示按数量自动选择。
    var prefersCompactList: Bool? {
        get { defaults.object(forKey: Key.density) as? Bool }
        set { defaults.set(newValue, forKey: Key.density) }
    }

    var sort: ProbeListSort {
        get { defaults.string(forKey: Key.sort).flatMap(ProbeListSort.init(rawValue:)) ?? .problemsFirst }
        set { defaults.set(newValue.rawValue, forKey: Key.sort) }
    }

    static let refreshIntervalOptions: [TimeInterval] = [3, 5, 10, 30, 60]
    static let defaultRefreshInterval: TimeInterval = 10

    /// 自动刷新间隔（秒），只接受预设档位。
    var refreshInterval: TimeInterval {
        get {
            let value = defaults.double(forKey: Key.refreshInterval)
            return Self.refreshIntervalOptions.contains(value) ? value : Self.defaultRefreshInterval
        }
        set { defaults.set(newValue, forKey: Key.refreshInterval) }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(instances) {
            defaults.set(data, forKey: Key.instances)
        }
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        // 增删改探针后小组件立即跟着变，不用等下一次定时刷新。
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
