import Foundation

/// 小组件读共享存储、用共享的请求服务。升级后 App 还没迁移过时直接提示，不去请求。
enum ProbeWidgetSource {
    @MainActor
    static var store: ProbeInstanceStore { ProbeInstanceStore(defaults: ProbeSharedStorage.widgetDefaults()) }

    @MainActor
    static func load(instanceID: UUID? = nil, now: Date = Date()) async -> ProbeWidgetData {
        guard ProbeSharedStorage.hasMigrated(ProbeSharedStorage.widgetDefaults()) else {
            return ProbeWidgetData(state: .needsAppLaunch)
        }
        return await ProbeWidgetLoader.load(store: store, service: ProbeService.shared, instanceID: instanceID, now: now)
    }

    @MainActor
    static func cpuTrend(instanceID: UUID, nodeID: String) async -> [Double] {
        guard let instance = store.instance(id: instanceID) else { return [] }
        return await ProbeWidgetLoader.cpuTrend(instance: instance, nodeID: nodeID, service: ProbeService.shared)
    }
}
