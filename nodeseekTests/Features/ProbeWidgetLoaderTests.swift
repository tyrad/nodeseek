import XCTest
@testable import nodeseek

/// 小组件刷新：复用 App 刚写的缓存、请求失败退回缓存、选过的探针被删后显示全部，以及点按后的页面跳转。
@MainActor
final class ProbeWidgetLoaderTests: XCTestCase {
    private final class CountingService: ProbeFetching, @unchecked Sendable {
        var results: [UUID: Result<ProbeSnapshot, ProbeFetchError>] = [:]
        private(set) var requested: [UUID] = []

        func testConnection(baseURL: URL, adapterID: String) async throws -> ProbeConnectionInfo {
            ProbeConnectionInfo(version: nil, nodes: [])
        }

        func snapshot(for instance: ProbeInstance, reloadNodes: Bool) async throws -> ProbeSnapshot {
            requested.append(instance.id)
            return try (results[instance.id] ?? .failure(.unreachable)).get()
        }

        func history(for instance: ProbeInstance, nodeID: String, hours: Int) async throws -> [ProbeHistoryPoint] {
            [ProbeHistoryPoint(date: Date(), metrics: ProbeMetrics(cpuPercent: 3)), ProbeHistoryPoint(date: Date(), metrics: ProbeMetrics())]
        }

        func forget(instanceID: UUID) async {}
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeStore() -> ProbeInstanceStore {
        let suite = "probe-widget-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return ProbeInstanceStore(defaults: defaults)
    }

    private func instance(_ name: String) -> ProbeInstance {
        ProbeInstance(name: name, baseURL: URL(string: "https://\(name).example.com")!, adapterID: "komari")
    }

    private func snapshot(_ node: String, at date: Date) -> ProbeSnapshot {
        let probeNode = ProbeNode(id: node, name: node, region: nil, group: nil, os: nil, cpuCores: 1, memTotal: 100, diskTotal: 100, weight: 0)
        let status = ProbeStatus(nodeID: node, online: true, sampledAt: date, metrics: ProbeMetrics(cpuPercent: 5))
        return ProbeSnapshot(nodes: [probeNode], statuses: [node: status], fetchedAt: date)
    }

    func testNoProbe() async {
        let data = await ProbeWidgetLoader.load(store: makeStore(), service: CountingService(), now: now)
        XCTAssertEqual(data.state, .noProbe)
    }

    func testReusesFreshCacheWithoutRequest() async {
        let store = makeStore(), service = CountingService()
        let home = instance("home")
        store.upsert(home)
        store.saveSnapshot(snapshot("a", at: now.addingTimeInterval(-60)), for: home.id)

        let data = await ProbeWidgetLoader.load(store: store, service: service, now: now)
        XCTAssertTrue(service.requested.isEmpty, "App 一分钟前刚刷新过，不再请求")
        XCTAssertEqual(data.entries.map(\.displayName), ["a"])
        XCTAssertFalse(data.isCached)
    }

    func testFetchesAndSavesWhenCacheIsOld() async {
        let store = makeStore(), service = CountingService()
        let home = instance("home")
        store.upsert(home)
        store.saveSnapshot(snapshot("old", at: now.addingTimeInterval(-3600)), for: home.id)
        service.results[home.id] = .success(snapshot("new", at: now))

        let data = await ProbeWidgetLoader.load(store: store, service: service, now: now)
        XCTAssertEqual(service.requested, [home.id])
        XCTAssertEqual(data.entries.map(\.displayName), ["new"])
        XCTAssertEqual(data.updatedAt, now)
        XCTAssertEqual(store.snapshot(for: home.id)?.nodes.first?.id, "new", "新数据写回共享存储，App 打开时也能用")
    }

    func testFailureFallsBackToCacheMarkedStale() async {
        let store = makeStore(), service = CountingService()
        let home = instance("home"), office = instance("office")
        store.upsert(home)
        store.upsert(office)
        store.saveSnapshot(snapshot("h", at: now.addingTimeInterval(-3600)), for: home.id)
        store.saveSnapshot(snapshot("o", at: now.addingTimeInterval(-3600)), for: office.id)
        service.results[office.id] = .success(snapshot("o", at: now))

        let partial = await ProbeWidgetLoader.load(store: store, service: service, now: now)
        XCTAssertEqual(partial.entries.map(\.isStale), [true, false], "只有连不上的那个探针标成旧数据")
        XCTAssertFalse(partial.isCached)
        XCTAssertEqual(partial.updatedAt, now.addingTimeInterval(-3600), "取最旧的那次更新时间")

        service.results = [:]
        store.saveSnapshot(snapshot("o", at: now.addingTimeInterval(-3600)), for: office.id)
        let none = await ProbeWidgetLoader.load(store: store, service: service, now: now)
        XCTAssertTrue(none.isCached, "全部连不上时整体显示缓存样式")
    }

    func testPickedProbeAndDeletedProbeFallsBackToAll() async {
        let store = makeStore(), service = CountingService()
        let home = instance("home"), office = instance("office")
        store.upsert(home)
        store.upsert(office)
        store.saveSnapshot(snapshot("h", at: now), for: home.id)
        store.saveSnapshot(snapshot("o", at: now), for: office.id)

        let picked = await ProbeWidgetLoader.load(store: store, service: service, instanceID: office.id, now: now)
        XCTAssertEqual(picked.entries.map(\.displayName), ["o"])
        let deleted = await ProbeWidgetLoader.load(store: store, service: service, instanceID: UUID(), now: now)
        XCTAssertEqual(deleted.entries.map(\.displayName), ["h", "o"])
    }

    func testCPUTrendSkipsMissingValues() async {
        let trend = await ProbeWidgetLoader.cpuTrend(instance: instance("home"), nodeID: "a", service: CountingService())
        XCTAssertEqual(trend, [3])
    }

    // MARK: - 点按跳转

    func testWidgetLinkOpensListThenDetailAndReusesList() throws {
        let navigation = UINavigationController(rootViewController: UIViewController())
        let viewModel = ProbeMonitorViewModel(store: makeStore(), service: CountingService(), now: { self.now })
        let make = { ProbeMonitorViewController(viewModel: viewModel) }

        ProbeMonitorViewController.show(ProbeWidgetLink(), in: navigation, animated: false, makeMonitor: make)
        XCTAssertEqual(navigation.viewControllers.count, 2)
        XCTAssertTrue(navigation.topViewController is ProbeMonitorViewController)

        let node = try XCTUnwrap(ProbeWidgetLink(entryID: "\(UUID().uuidString)/n1"))
        ProbeMonitorViewController.show(node, in: navigation, animated: false, makeMonitor: make)
        XCTAssertEqual(navigation.viewControllers.count, 3)
        XCTAssertTrue(navigation.topViewController is ProbeServerDetailViewController)

        // 再点一次：回到已有的探针页再进详情，不会越压越深。
        ProbeMonitorViewController.show(node, in: navigation, animated: false, makeMonitor: make)
        XCTAssertEqual(navigation.viewControllers.count, 3)
    }
}
