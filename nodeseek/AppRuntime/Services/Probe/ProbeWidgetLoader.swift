import Foundation

/// 小组件一次刷新拿到的数据。
struct ProbeWidgetData: Sendable {
    enum State: Sendable {
        case ready
        /// 还没添加探针。
        case noProbe
        /// 升级后还没打开过 App，探针配置还没搬到共享存储。
        case needsAppLaunch
    }

    var state: State
    var entries: [ProbeListEntry] = []
    /// 用到的快照里最旧的那次更新时间。
    var updatedAt: Date?
    /// 全部探针都没拿到新数据，只能显示缓存。
    var isCached = false
}

/// 小组件自己联网刷新；失败时退回 App 或上次留下的缓存。App 与小组件共用，便于单测。
enum ProbeWidgetLoader {
    /// 系统一般按这个间隔叫醒小组件，实际时间由系统决定。
    static let refreshInterval: TimeInterval = 20 * 60
    /// App 刚刷新过的缓存直接用，省一次请求。
    static let reuseInterval: TimeInterval = 5 * 60
    /// 超过这个时间的缓存不再判断离线和负载。
    static let staleInterval: TimeInterval = 30 * 60

    /// 选了某个探针就只看它；它被删了就退回全部。
    @MainActor
    static func load(store: ProbeInstanceStore, service: ProbeFetching, instanceID: UUID? = nil, now: Date = Date()) async -> ProbeWidgetData {
        var instances = store.instances
        if let instanceID, let picked = store.instance(id: instanceID) {
            instances = [picked]
        }
        guard !instances.isEmpty else { return ProbeWidgetData(state: .noProbe) }

        let cached = Dictionary(uniqueKeysWithValues: instances.map { ($0.id, store.snapshot(for: $0.id)) })
        let needsFetch = instances.filter { instance in
            guard let snapshot = cached[instance.id] ?? nil else { return true }
            return now.timeIntervalSince(snapshot.fetchedAt) > reuseInterval
        }
        let fetched = await withTaskGroup(of: (UUID, ProbeSnapshot?).self) { group in
            for instance in needsFetch {
                group.addTask { (instance.id, try? await service.snapshot(for: instance, reloadNodes: true)) }
            }
            var result: [UUID: ProbeSnapshot] = [:]
            for await (id, snapshot) in group {
                if let snapshot { result[id] = snapshot }
            }
            return result
        }
        for (id, snapshot) in fetched {
            store.saveSnapshot(snapshot, for: id)
        }

        let failed = Set(needsFetch.map(\.id)).subtracting(fetched.keys)
        var entries: [ProbeListEntry] = []
        var dates: [Date] = []
        for instance in instances {
            guard let snapshot = fetched[instance.id] ?? cached[instance.id] ?? nil else { continue }
            let isStale = failed.contains(instance.id) || now.timeIntervalSince(snapshot.fetchedAt) > staleInterval
            entries += ProbeListEntry.entries(instance: instance, snapshot: snapshot, isStale: isStale)
            dates.append(snapshot.fetchedAt)
        }
        return ProbeWidgetData(
            state: .ready,
            entries: entries,
            updatedAt: dates.min(),
            isCached: !entries.isEmpty && entries.allSatisfy(\.isStale)
        )
    }

    /// 单台小组件的 CPU 趋势：最近 1 小时。拿不到就不画。
    static func cpuTrend(instance: ProbeInstance, nodeID: String, service: ProbeFetching) async -> [Double] {
        let points = (try? await service.history(for: instance, nodeID: nodeID, hours: 1)) ?? []
        return points.compactMap(\.metrics.cpuPercent)
    }
}
