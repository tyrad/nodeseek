import XCTest
#if SWIFT_PACKAGE
@testable import NodeSeekCore
#else
@testable import nodeseek
#endif

final class ProbeServerListTests: XCTestCase {
    private let prod = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    private let home = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!

    func testProblemsFirstPutsOfflineThenAlertsByUsage() {
        let entries = [
            entry("ok", cpu: 5, index: 0),
            entry("mem88", cpu: 10, mem: 88, index: 1),
            entry("down", online: false, index: 2),
            entry("cpu93", cpu: 93, index: 3),
            entry("nodata", status: false, index: 4),
        ]
        let names = ProbeServerList.arrange(entries, filter: .all, sort: .problemsFirst, query: "")
            .flatMap(\.entries).map(\.displayName)
        XCTAssertEqual(names, ["down", "cpu93", "mem88", "nodata", "ok"])
    }

    func testFiltersAndSearchProduceSingleFlatSection() {
        let entries = [
            entry("TYO-03", cpu: 93, group: "生产", index: 0),
            entry("HK-01", cpu: 1, group: "生产", region: "🇭🇰", index: 1),
            entry("SG-01", online: false, group: "测试", index: 2),
        ]
        let alerts = ProbeServerList.arrange(entries, filter: .alert, sort: .problemsFirst, query: "")
        XCTAssertEqual(alerts.map(\.title), ["告警"])
        XCTAssertEqual(alerts.first?.entries.map(\.displayName), ["TYO-03"])
        XCTAssertEqual(ProbeServerList.arrange(entries, filter: .offline, sort: .problemsFirst, query: "").first?.entries.map(\.displayName), ["SG-01"])
        XCTAssertEqual(ProbeServerList.arrange(entries, filter: .all, sort: .problemsFirst, query: "🇭🇰").first?.entries.map(\.displayName), ["HK-01"])
        XCTAssertEqual(ProbeServerList.arrange(entries, filter: .all, sort: .problemsFirst, query: "测试").first?.title, "搜索结果")
        XCTAssertTrue(ProbeServerList.arrange(entries, filter: .all, sort: .problemsFirst, query: "nothing").isEmpty)
    }

    func testGroupsByPanelGroupAndInstance() {
        let entries = [
            entry("a", group: "生产", index: 0),
            entry("b", group: "测试", index: 1),
            entry("c", group: "生产", index: 2),
            entry("nas", instance: home, instanceName: "家里 NAS", index: 0),
        ]
        let sections = ProbeServerList.arrange(entries, filter: .all, sort: .problemsFirst, query: "")
        XCTAssertEqual(sections.map(\.title), ["生产 · NS Probe", "测试 · NS Probe", "家里 NAS"])
        XCTAssertEqual(sections[0].entries.map(\.displayName), ["a", "c"])
        // 只有一个探针时不重复写探针名。
        let single = ProbeServerList.arrange(Array(entries.prefix(3)), filter: .all, sort: .problemsFirst, query: "")
        XCTAssertEqual(single.map(\.title), ["生产", "测试"])
    }

    func testSortsByNameAndMetrics() {
        let entries = [entry("b-10", cpu: 5, mem: 90, index: 0), entry("a-2", cpu: 50, mem: 10, index: 1), entry("a-10", cpu: 20, mem: 30, index: 2)]
        func names(_ sort: ProbeListSort) -> [String] {
            ProbeServerList.arrange(entries, filter: .all, sort: sort, query: "").flatMap(\.entries).map(\.displayName)
        }
        XCTAssertEqual(names(.name), ["a-2", "a-10", "b-10"])
        XCTAssertEqual(names(.cpu), ["a-2", "a-10", "b-10"])
        XCTAssertEqual(names(.memory), ["b-10", "a-10", "a-2"])
    }

    func testStaleDataNeverCountsAsAlertOrLiveTraffic() {
        let stale = entry("old", cpu: 95, net: 1000, stale: true, index: 0)
        XCTAssertFalse(stale.isAlerting)
        let summary = ProbeListSummary(entries: [stale, entry("live", cpu: 95, net: 500, index: 1), entry("down", online: false, index: 2)])
        XCTAssertEqual(summary.total, 3)
        XCTAssertEqual(summary.online, 2)
        XCTAssertEqual(summary.offline, 1)
        XCTAssertEqual(summary.alerts, 1)
        XCTAssertEqual(summary.netInRate, 500)
    }

    func testUsageLevels() {
        XCTAssertEqual(ProbeUsageLevel(percent: 69.9), .normal)
        XCTAssertEqual(ProbeUsageLevel(percent: 70), .warning)
        XCTAssertEqual(ProbeUsageLevel(percent: 90), .critical)
        XCTAssertEqual(ProbeUsageLevel(percent: nil), .normal)
    }

    func testFormatting() {
        XCTAssertEqual(ProbeFormat.percent(10.54), "10.5")
        XCTAssertEqual(ProbeFormat.percent(nil), "—")
        XCTAssertEqual(ProbeFormat.rate(319_090), "312K")
        XCTAssertEqual(ProbeFormat.rate(4_300_000), "4.10M")
        XCTAssertEqual(ProbeFormat.rate(512), "512B")
        XCTAssertEqual(ProbeFormat.bytes(4_115_853_312), "3.83G")
        XCTAssertEqual(ProbeFormat.bytes(354_386_652_918), "330G")
        XCTAssertEqual(ProbeFormat.uptime(5_680_265), "65D 17H")
        XCTAssertEqual(ProbeFormat.uptime(0), "—")
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(ProbeFormat.relative(now.addingTimeInterval(-30), now: now), "刚刚")
        XCTAssertEqual(ProbeFormat.relative(now.addingTimeInterval(-180), now: now), "3 分钟前")
        XCTAssertEqual(ProbeFormat.relative(now.addingTimeInterval(-7200), now: now), "2 小时前")
    }

    private func entry(
        _ name: String, online: Bool = true, status: Bool = true, cpu: Double = 1, mem: Double = 10,
        net: Int64 = 0, group: String? = nil, region: String? = nil, stale: Bool = false,
        instance: UUID? = nil, instanceName: String = "NS Probe", index: Int
    ) -> ProbeListEntry {
        let node = ProbeNode(id: name, name: name, region: region, group: group, os: nil, cpuCores: nil,
                             memTotal: 100, diskTotal: 100, weight: 0)
        let metrics = ProbeMetrics(cpuPercent: cpu, memUsed: Int64(mem), memTotal: 100, diskUsed: 10, diskTotal: 100,
                                   netInRate: net, netOutRate: 0)
        let probeStatus = status ? ProbeStatus(nodeID: name, online: online, sampledAt: nil, metrics: metrics) : nil
        return ProbeListEntry(instanceID: instance ?? prod, instanceName: instanceName,
                              server: ProbeServer(node: node, status: probeStatus), displayName: name,
                              isStale: stale, panelIndex: index)
    }
}
