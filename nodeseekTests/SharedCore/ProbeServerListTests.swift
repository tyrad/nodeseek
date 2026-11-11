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
    func testRegionNormalizesFlagsAndCountryCodes() {
        XCTAssertEqual(ProbeGeo.countryCode(from: "🇭🇰"), "HK")
        XCTAssertEqual(ProbeGeo.countryCode(from: " jp "), "JP")
        XCTAssertEqual(ProbeGeo.countryCode(from: "UK"), "GB")
        XCTAssertEqual(ProbeGeo.countryCode(from: "🇺🇸 洛杉矶"), "US")
        XCTAssertNil(ProbeGeo.countryCode(from: nil))
        XCTAssertNil(ProbeGeo.countryCode(from: ""))
        XCTAssertNil(ProbeGeo.countryCode(from: "Mars"))
        XCTAssertNil(ProbeGeo.countryCode(from: "XX"))
        XCTAssertEqual(ProbeGeo.flag(for: "SG"), "🇸🇬")
        XCTAssertEqual(ProbeGeo.displayName(for: "HK"), "香港")
        for code in ["HK", "JP", "SG", "US", "DE", "GB", "KR", "TW", "CN", "RU", "NL", "FR"] {
            XCTAssertNotNil(ProbeGeo.coordinate(for: code), code)
        }
        let hongKong = ProbeGeo.coordinate(for: "HK")
        XCTAssertEqual(hongKong?.latitude ?? 0, 22.3, accuracy: 0.5)
        XCTAssertEqual(hongKong?.longitude ?? 0, 114.2, accuracy: 0.5)
    }

    func testCountryGroupsPutProblemsFirstAndUnknownLast() {
        let entries = [
            entry("HK-1", region: "🇭🇰", index: 0),
            entry("HK-2", cpu: 95, region: "🇭🇰", index: 1),
            entry("JP-1", region: "JP", index: 2),
            entry("JP-2", region: "JP", index: 3),
            entry("JP-3", region: "JP", index: 4),
            entry("US-1", online: false, region: "🇺🇸", index: 5),
            entry("none", index: 6),
            entry("old", online: false, region: "🇩🇪", stale: true, index: 7),
        ]
        let groups = ProbeCountryGroup.groups(from: entries)
        // 离线 → 告警 → 暂无数据（过期）→ 正常，“未知地区”最后。
        XCTAssertEqual(groups.map(\.id), ["US", "HK", "DE", "JP", "unknown"])
        XCTAssertEqual(groups.map(\.health), [.offline, .alert, .unknown, .online, .online])
        XCTAssertEqual(groups[1].alertCount, 1)
        XCTAssertEqual(groups[1].entries.map(\.displayName), ["HK-1", "HK-2"])
        XCTAssertEqual(groups[3].entries.count, 3)
        XCTAssertEqual(groups[0].offlineCount, 1)
        // 过期数据不算离线。
        XCTAssertEqual(groups[2].offlineCount, 0)
    }

    func testBuiltinDatacenterDictionaryIsWellFormed() throws {
        let directory = try ProbeDatacenterDirectory(data: BuiltinAdapterLoader.data(named: ProbeDatacenterDirectory.resourceName))
        XCTAssertGreaterThan(directory.cities.count, 100)
        let codes = directory.cities.flatMap(\.codes)
        XCTAssertEqual(codes.count, Set(codes).count, "机场代码不能重复")
        for city in directory.cities {
            XCTAssertTrue((-90...90).contains(city.lat) && (-180...180).contains(city.lon), city.city)
            XCTAssertNotNil(ProbeGeo.coordinate(for: city.country), "\(city.city) 的国家 \(city.country) 不在国家表里")
            XCTAssertEqual(city.names, city.names.map { $0.lowercased() }, "\(city.city) 的写法要用小写")
        }
    }

    func testDatacenterMatchingFromNamesAndGroups() throws {
        // SwiftPM 测试进程没有 App bundle，builtin 会是空字典，所以按源码路径读取同一个文件。
        let directory = try ProbeDatacenterDirectory(data: BuiltinAdapterLoader.data(named: ProbeDatacenterDirectory.resourceName))
        func locate(_ name: String, region: String? = nil, group: String? = nil) -> (String?, String?) {
            let location = directory.locate(entry(name, group: group, region: region, index: 0))
            return (location.country, location.city?.city)
        }
        XCTAssertTrue(locate("US-LAX", region: "🇺🇸") == ("US", "洛杉矶"))
        XCTAssertTrue(locate("JP-TYO") == ("JP", "东京"))
        XCTAssertTrue(locate("lax2") == ("US", "洛杉矶"))
        XCTAssertTrue(locate("圣何塞 CN2") == ("US", "圣何塞"))
        XCTAssertTrue(locate("Tokyo-2") == ("JP", "东京"))
        XCTAssertTrue(locate("DE-FRA-01", region: "🇩🇪") == ("DE", "法兰克福"))
        XCTAssertTrue(locate("node", group: "美西") == ("US", "洛杉矶"))
        // 名字里的城市和国旗冲突时以国旗为准，退回国家。
        XCTAssertTrue(locate("FRA-01", region: "🇫🇷") == ("FR", nil))
        // 只写了国家代码时推断国家；小写或 CN2 线路名不算。
        XCTAssertTrue(locate("HK-01") == ("HK", nil))
        XCTAssertTrue(locate("hk-01") == (nil, nil))
        XCTAssertTrue(locate("CN2-GIA") == (nil, nil))
        // 不把普通单词的一部分当成代码。
        XCTAssertTrue(locate("SEARCH-1") == (nil, nil))
        XCTAssertTrue(locate("LAXITY") == (nil, nil))
        XCTAssertTrue(locate("climate") == (nil, nil))
        XCTAssertEqual(ProbeDatacenterDirectory.tokens(in: "US-LAX2洛杉矶"), ["US", "LAX", "2", "洛杉矶"])
    }

