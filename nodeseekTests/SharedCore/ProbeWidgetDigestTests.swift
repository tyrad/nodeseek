import XCTest
#if SWIFT_PACKAGE
@testable import NodeSeekCore
#else
@testable import nodeseek
#endif

/// 小组件的整理逻辑：在线数、关注列表的取舍和顺序、最近到期，以及点按链接。
final class ProbeWidgetDigestTests: XCTestCase {
    private let calendar = Calendar.current
    private let instanceID = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!

    private func entry(_ id: String, online: Bool? = true, cpu: Double = 5, mem: Int64 = 10, stale: Bool = false,
                       expires: Date? = nil, trafficLimit: Int64? = nil, used: Int64 = 0, sampledAt: Date? = nil,
                       index: Int = 0) -> ProbeListEntry {
        let plan = (expires != nil || trafficLimit != nil) ? ProbePlan(expiresAt: expires, trafficLimit: trafficLimit, trafficMode: .sum) : nil
        let node = ProbeNode(id: id, name: id, region: "JP", group: nil, os: nil, cpuCores: 1,
                             memTotal: 100, diskTotal: 100, weight: 0, plan: plan)
        let metrics = ProbeMetrics(cpuPercent: cpu, memUsed: mem, memTotal: 100, diskUsed: 10, diskTotal: 100,
                                   trafficIn: used, trafficOut: 0)
        let status = online.map { ProbeStatus(nodeID: id, online: $0, sampledAt: sampledAt, metrics: metrics) }
        return ProbeListEntry(instanceID: instanceID, instanceName: "测试", server: ProbeServer(node: node, status: status),
                              displayName: id, isStale: stale, panelIndex: index)
    }

    func testAttentionOrderAndCounts() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 10)))
        let entries = [
            entry("traffic", trafficLimit: 100, used: 95, index: 0),
            entry("expiry", expires: now.addingTimeInterval(3 * 86_400), index: 1),
            entry("busy", mem: 93, index: 2),
            entry("down", online: false, sampledAt: now.addingTimeInterval(-7200), index: 3),
            entry("calm", cpu: 30, expires: now.addingTimeInterval(200 * 86_400), index: 4),
            entry("warm", mem: 80, index: 5),
        ]
        let digest = ProbeWidgetDigest(entries: entries, now: now, calendar: calendar)
        XCTAssertEqual(digest.total, 6)
        XCTAssertEqual(digest.online, 5)
        XCTAssertEqual(digest.offline, 1)
        XCTAssertEqual(digest.alerts, 1, "80% 只是 App 里的黄色，小组件只把 ≥90% 算告警")
        XCTAssertEqual(digest.attention.map(\.name), ["down", "busy", "expiry", "traffic"])
        XCTAssertEqual(digest.attention.map(\.value), ["离线 2 小时", "内存 93%", "3 天后到期", "流量 95%"])
        XCTAssertEqual(digest.nearestExpiry?.name, "expiry")
        XCTAssertEqual(digest.nearestExpiryLevel, .warning)
        XCTAssertEqual(digest.quiet.first?.name, "calm", "全部正常时 CPU 最高的排前")
    }

    func testExpiryItemsSortBySoonest() {
        let now = Date()
        let digest = ProbeWidgetDigest(entries: [
            entry("five", expires: now.addingTimeInterval(5 * 86_400 + 3600), index: 0),
            entry("three", expires: now.addingTimeInterval(3 * 86_400 + 3600), index: 1),
            entry("four", expires: now.addingTimeInterval(4 * 86_400 + 3600), index: 2),
        ], now: now)
        XCTAssertEqual(digest.attention.map(\.name), ["three", "four", "five"], "到期按剩余天数排，不按面板顺序")
    }

    func testOneServerAppearsOnceWithItsWorstProblem() {
        let now = Date()
        let digest = ProbeWidgetDigest(entries: [
            entry("both", online: false, expires: now.addingTimeInterval(-86_400)),
        ], now: now)
        XCTAssertEqual(digest.attention.count, 1)
        XCTAssertEqual(digest.attention.first?.kind, .offline)
    }

    func testStaleEntriesSkipLiveProblemsButKeepExpiry() {
        let now = Date()
        let digest = ProbeWidgetDigest(entries: [
            entry("old-down", online: false, stale: true),
            entry("old-busy", mem: 99, stale: true),
            entry("old-expiry", stale: true, expires: now.addingTimeInterval(2 * 86_400)),
        ], now: now)
        XCTAssertEqual(digest.online, 0)
        XCTAssertEqual(digest.offline, 0)
        XCTAssertEqual(digest.attention.map(\.name), ["old-expiry"])
    }

    func testLongTermPlansAreNotNearestExpiry() {
        let now = Date()
        let digest = ProbeWidgetDigest(entries: [entry("forever", expires: now.addingTimeInterval(80 * 365 * 86_400))], now: now)
        XCTAssertNil(digest.nearestExpiry)
        XCTAssertTrue(digest.attention.isEmpty)
    }

    func testOfflineText() {
        let now = Date()
        XCTAssertEqual(ProbeWidgetDigest.offlineText(since: nil, now: now), "离线")
        XCTAssertEqual(ProbeWidgetDigest.offlineText(since: now.addingTimeInterval(-30), now: now), "离线 1 分钟")
        XCTAssertEqual(ProbeWidgetDigest.offlineText(since: now.addingTimeInterval(-3 * 86_400), now: now), "离线 3 天")
    }

    func testWidgetLinkRoundTrip() throws {
        let link = ProbeWidgetLink(instanceID: instanceID, nodeID: "node/1")
        XCTAssertEqual(ProbeWidgetLink(url: link.url), link)
        XCTAssertEqual(ProbeWidgetLink(url: try XCTUnwrap(URL(string: "nsconnect://probe"))), ProbeWidgetLink())
        XCTAssertEqual(ProbeWidgetLink(url: try XCTUnwrap(URL(string: "nsconnect://probe?node=1"))), ProbeWidgetLink(), "缺探针时只进列表")
        XCTAssertNil(ProbeWidgetLink(url: try XCTUnwrap(URL(string: "https://probe"))))
        XCTAssertNil(ProbeWidgetLink(url: try XCTUnwrap(URL(string: "nsconnect://post/1"))))
    }

    func testWidgetLinkFromEntryID() {
        let link = ProbeWidgetLink(entryID: "\(instanceID.uuidString)/node/1")
        XCTAssertEqual(link?.instanceID, instanceID)
        XCTAssertEqual(link?.nodeID, "node/1", "节点 ID 里的斜杠保留")
        XCTAssertNil(ProbeWidgetLink(entryID: "not-a-uuid/1"))
        XCTAssertNil(ProbeWidgetLink(entryID: "\(instanceID.uuidString)/"))
        XCTAssertNil(ProbeWidgetLink(entryID: instanceID.uuidString))
    }
}
