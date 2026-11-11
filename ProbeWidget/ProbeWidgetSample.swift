import Foundation

/// 小组件库里的预览和占位用的假数据。
enum ProbeWidgetSample {
    private static let instance = ProbeInstance(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                                                name: "示例探针", baseURL: URL(string: "https://example.com")!, adapterID: "komari")

    private static func server(_ id: String, _ name: String, region: String, online: Bool = true,
                               cpu: Double, mem: Double, disk: Double, expiresIn days: Int? = nil, price: Double? = nil) -> (ProbeNode, ProbeStatus) {
        let plan = days.map { ProbePlan(expiresAt: Date().addingTimeInterval(Double($0) * 86_400 + 3600), price: price, currency: "¥", cycle: .months(12)) }
        let node = ProbeNode(id: id, name: name, region: region, group: nil, os: nil, cpuCores: 2,
                             memTotal: 100, diskTotal: 100, weight: 0, plan: plan)
        let metrics = ProbeMetrics(cpuPercent: cpu, memUsed: Int64(mem), memTotal: 100, diskUsed: Int64(disk), diskTotal: 100)
        return (node, ProbeStatus(nodeID: id, online: online, sampledAt: Date().addingTimeInterval(online ? 0 : -7200), metrics: metrics))
    }

    static let entries: [ProbeListEntry] = {
        let servers = [
            server("1", "US-01", region: "US", online: false, cpu: 0, mem: 40, disk: 30),
            server("2", "JP-02", region: "JP", cpu: 4.1, mem: 93, disk: 56, expiresIn: 347),
            server("3", "HK-01", region: "HK", cpu: 1.2, mem: 41, disk: 22, expiresIn: 3, price: 99),
            server("4", "SG-01", region: "SG", cpu: 2.7, mem: 35, disk: 48),
        ]
        let snapshot = ProbeSnapshot(nodes: servers.map(\.0),
                                     statuses: Dictionary(uniqueKeysWithValues: servers.map { ($0.0.id, $0.1) }),
                                     fetchedAt: Date())
        return ProbeListEntry.entries(instance: instance, snapshot: snapshot, isStale: false)
    }()

    static var digestEntry: ProbeDigestEntry {
        let data = ProbeWidgetData(state: .ready, entries: entries, updatedAt: Date())
        return ProbeDigestEntry(date: Date(), data: data, digest: ProbeWidgetDigest(entries: entries))
    }

    static var serverEntry: ProbeServerEntry {
        ProbeServerEntry(date: Date(), state: .ready(entries[1]), updatedAt: Date(),
                         trend: [22, 20, 23, 18, 21, 12, 19, 20, 9, 17, 15, 18, 16])
    }
}
