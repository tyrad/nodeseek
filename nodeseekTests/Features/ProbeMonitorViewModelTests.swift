import CoreLocation
import XCTest
@testable import nodeseek

@MainActor
final class ProbeMonitorViewModelTests: XCTestCase {
    private final class StubService: ProbeFetching, @unchecked Sendable {
        var result: Result<ProbeSnapshot, ProbeFetchError>

        init(result: Result<ProbeSnapshot, ProbeFetchError>) {
            self.result = result
        }

        func testConnection(baseURL: URL, adapterID: String) async throws -> ProbeConnectionInfo {
            ProbeConnectionInfo(version: nil, nodes: [])
        }

        var byInstance: [UUID: Result<ProbeSnapshot, ProbeFetchError>] = [:]

        func snapshot(for instance: ProbeInstance, reloadNodes: Bool) async throws -> ProbeSnapshot {
            if let specific = byInstance[instance.id] { return try specific.get() }
            return try result.get()
        }

        func history(for instance: ProbeInstance, nodeID: String, hours: Int) async throws -> [ProbeHistoryPoint] { [] }
        var forgottenIDs: [UUID] = []
        func forget(instanceID: UUID) async { forgottenIDs.append(instanceID) }
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testRefreshAppliesOrderHiddenAndAliases() async {
        let store = makeStore()
        var instance = ProbeInstance(name: "Prod", baseURL: URL(string: "https://p.example")!, adapterID: "komari")
        instance.hiddenNodeIDs = ["c"]
        instance.nodeOrder = ["b"]
        instance.aliases = ["a": "Alpha"]
        store.upsert(instance)
        let viewModel = ProbeMonitorViewModel(store: store, service: StubService(result: .success(snapshot(at: now))), now: { self.now })

        await viewModel.refresh()

        XCTAssertEqual(viewModel.entries.map(\.displayName), ["b", "Alpha"])
        XCTAssertEqual(viewModel.entries.map(\.panelIndex), [0, 1])
        XCTAssertNotNil(store.snapshot(for: instance.id))
    }

    func testFailedRefreshKeepsCachedSnapshotAsStale() async {
        let store = makeStore()
        let instance = ProbeInstance(name: "Prod", baseURL: URL(string: "https://p.example")!, adapterID: "komari")
        store.upsert(instance)
        store.saveSnapshot(snapshot(at: now), for: instance.id)
        let service = StubService(result: .failure(.unreachable))
        let viewModel = ProbeMonitorViewModel(store: store, service: service, now: { self.now })
        XCTAssertFalse(viewModel.entries.contains(where: \.isStale))

        await viewModel.refresh()

        XCTAssertEqual(viewModel.entries.count, 3)
        XCTAssertTrue(viewModel.entries.allSatisfy(\.isStale))
        XCTAssertEqual(viewModel.failedInstances.map(\.1), [.unreachable])
        XCTAssertEqual(viewModel.summary.alerts, 0)
    }

    func testOldCacheIsStaleBeforeFirstRefresh() {
        let store = makeStore()
        let instance = ProbeInstance(name: "Prod", baseURL: URL(string: "https://p.example")!, adapterID: "komari")
        store.upsert(instance)
        store.saveSnapshot(snapshot(at: now.addingTimeInterval(-600)), for: instance.id)
        let viewModel = ProbeMonitorViewModel(store: store, service: StubService(result: .failure(.unreachable)), now: { self.now })
        XCTAssertTrue(viewModel.entries.allSatisfy(\.isStale))
    }

    func testHideAndAliasPersist() async {
        let store = makeStore()
        let instance = ProbeInstance(name: "Prod", baseURL: URL(string: "https://p.example")!, adapterID: "komari")
        store.upsert(instance)
        let viewModel = ProbeMonitorViewModel(store: store, service: StubService(result: .success(snapshot(at: now))), now: { self.now })
        await viewModel.refresh()

        viewModel.setAlias("  香港  ", for: viewModel.entries[0])
        XCTAssertEqual(viewModel.entries[0].displayName, "香港")
        viewModel.setAlias("", for: viewModel.entries[0])
        XCTAssertEqual(viewModel.entries[0].displayName, "a")
        viewModel.hide(viewModel.entries[1])
        XCTAssertEqual(store.instance(id: instance.id)?.hiddenNodeIDs, ["b"])
        XCTAssertEqual(viewModel.entries.map(\.displayName), ["a", "c"])
    }

    func testSelectingAProbeShowsOnlyThatProbesServers() async {
        let store = makeStore()
        let home = ProbeInstance(name: "家里", baseURL: URL(string: "https://home.example")!, adapterID: "komari")
        let room = ProbeInstance(name: "机房", baseURL: URL(string: "https://room.example")!, adapterID: "monitor")
        store.upsert(home)
        store.upsert(room)
        let service = StubService(result: .success(snapshot(at: now)))
        service.byInstance[room.id] = .success(snapshot(at: now, ids: ["edge"], online: false))
        let viewModel = ProbeMonitorViewModel(store: store, service: service, now: { self.now })

        await viewModel.refresh()

        XCTAssertEqual(viewModel.selectedInstanceID, home.id)
        XCTAssertEqual(viewModel.entries.count, 4)
        XCTAssertEqual(viewModel.visibleEntries.map(\.instanceID), Array(repeating: home.id, count: 3))
        XCTAssertEqual(viewModel.summary.total, 3)
        XCTAssertEqual(viewModel.summary.offline, 0)
        XCTAssertEqual(viewModel.cards.map(\.name), ["家里", "机房"])
        XCTAssertEqual(viewModel.cards.map(\.isSelected), [true, false])
        XCTAssertEqual(viewModel.filterCounts[.all], 3)
        XCTAssertEqual(viewModel.sections.flatMap(\.entries).map(\.instanceName), ["家里", "家里", "家里"])

        viewModel.query = "edge"
        XCTAssertTrue(viewModel.sections.isEmpty)

        viewModel.query = ""
        viewModel.selectInstance(room.id)
        XCTAssertEqual(viewModel.visibleEntries.map(\.displayName), ["edge"])
        XCTAssertEqual(viewModel.summary.offline, 1)
        XCTAssertEqual(viewModel.filterCounts, [.all: 1, .offline: 1, .alert: 0])
        XCTAssertEqual(viewModel.cards.map(\.isSelected), [false, true])
    }

    func testCardAveragesOnlyCountLiveServersAndSpotlightsOffline() async {
        let store = makeStore()
        let home = ProbeInstance(name: "家里", baseURL: URL(string: "https://home.example")!, adapterID: "komari")
        store.upsert(home)
        var data = snapshot(at: now, ids: ["a", "b", "c", "d"])
        data.statuses["a"]?.metrics = ProbeMetrics(cpuPercent: 10, memUsed: 20, memTotal: 100, diskUsed: 30, diskTotal: 100)
        data.statuses["b"]?.metrics = ProbeMetrics(cpuPercent: 30, memUsed: 80, memTotal: 100, diskUsed: 50, diskTotal: 100)
        data.statuses["c"]?.online = false
        data.statuses["c"]?.sampledAt = now.addingTimeInterval(-3 * 3600)
        data.statuses["d"]?.online = false
        data.statuses["d"]?.sampledAt = now.addingTimeInterval(-600)
        let viewModel = ProbeMonitorViewModel(store: store, service: StubService(result: .success(data)), now: { self.now })

        await viewModel.refresh()

        let card = viewModel.cards[0]
        // 离线机器保留的旧数值（95%）不计入均值。
        XCTAssertEqual(card.averageCPU ?? -1, 20, accuracy: 0.01)
        XCTAssertEqual(card.averageMemory ?? -1, 50, accuracy: 0.01)
        XCTAssertEqual(card.averageDisk ?? -1, 40, accuracy: 0.01)
        XCTAssertEqual(card.spotlight?.kind, .offline)
        XCTAssertEqual(card.spotlight?.title, "d")
        XCTAssertEqual(card.spotlight?.detail, "10 分钟前 · 共 2 台")
        XCTAssertEqual(card.spotlight?.entryID, viewModel.entries.first { $0.displayName == "d" }?.id)
    }

    func testSpotlightShowsBusiestMetricWhenAllOnline() {
        let id = UUID()
        let entries = [
            sampleEntry(instance: id, name: "a", online: true, cpu: 12, net: 0),
            sampleEntry(instance: id, name: "b", online: true, cpu: 46, net: 0),
        ]
        let spotlight = ProbeCardSpotlight.pick(from: entries, now: now)
        XCTAssertEqual(spotlight?.kind, .busiest)
        XCTAssertEqual(spotlight?.title, "b")
        XCTAssertEqual(spotlight?.detail, "CPU 46%")
        XCTAssertNil(ProbeCardSpotlight.pick(from: [], now: now))
    }

    func testAddingAProbeSelectsItAndRemovingTheSelectionFallsBack() async {
        let store = makeStore()
        let home = ProbeInstance(name: "家里", baseURL: URL(string: "https://home.example")!, adapterID: "komari")
        store.upsert(home)
        let viewModel = ProbeMonitorViewModel(store: store, service: StubService(result: .success(snapshot(at: now))), now: { self.now })
        await viewModel.refresh()

        let room = ProbeInstance(name: "机房", baseURL: URL(string: "https://room.example")!, adapterID: "monitor")
        store.upsert(room)
        viewModel.reloadInstances()
        XCTAssertEqual(viewModel.selectedInstanceID, room.id)
        XCTAssertEqual(viewModel.cards.last?.updated, "尚未加载")

        store.remove(id: room.id)
        viewModel.reloadInstances()
        XCTAssertEqual(viewModel.selectedInstanceID, home.id)
        XCTAssertEqual(viewModel.summary.total, 3)
    }

    func testSelectedCardOwnsTheErrorMessage() async {
        let store = makeStore()
        let home = ProbeInstance(name: "家里", baseURL: URL(string: "https://home.example")!, adapterID: "komari")
        let room = ProbeInstance(name: "机房", baseURL: URL(string: "https://room.example")!, adapterID: "monitor")
        store.upsert(home)
        store.upsert(room)
        let service = StubService(result: .success(snapshot(at: now)))
        service.byInstance[room.id] = .failure(.unauthorized)
        let viewModel = ProbeMonitorViewModel(store: store, service: service, now: { self.now })

        await viewModel.refresh()

        XCTAssertNil(viewModel.selectedErrorMessage)
        XCTAssertEqual(viewModel.cards[1].updated, "连接失败")
        XCTAssertTrue(viewModel.cards[1].hasError)
        viewModel.selectInstance(room.id)
        XCTAssertEqual(viewModel.selectedErrorMessage, "面板拒绝访问，可能未对游客公开。")
        XCTAssertTrue(viewModel.visibleEntries.isEmpty)
    }

    func testCompactModeUsesTheSelectedProbe() async {
        let store = makeStore()
        let home = ProbeInstance(name: "家里", baseURL: URL(string: "https://home.example")!, adapterID: "komari")
        let room = ProbeInstance(name: "机房", baseURL: URL(string: "https://room.example")!, adapterID: "monitor")
        store.upsert(home)
        store.upsert(room)
        let service = StubService(result: .success(snapshot(at: now, ids: (0..<9).map { "n\($0)" })))
        service.byInstance[room.id] = .success(snapshot(at: now, ids: ["edge"]))
        let viewModel = ProbeMonitorViewModel(store: store, service: service, now: { self.now })
        await viewModel.refresh()

        XCTAssertTrue(viewModel.usesCompactList)
        viewModel.selectInstance(room.id)
        XCTAssertFalse(viewModel.usesCompactList)
        viewModel.setCompact(true)
        XCTAssertTrue(viewModel.usesCompactList)
    }

    func testHeroCarouselCentersSelectedCardAndShrinksNeighbours() {
        let home = UUID()
        let room = UUID()
        let carousel = ProbeHeroCarouselView()
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 400))
        carousel.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(carousel)
        NSLayoutConstraint.activate([
            carousel.topAnchor.constraint(equalTo: host.topAnchor),
            carousel.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            carousel.trailingAnchor.constraint(equalTo: host.trailingAnchor),
        ])
        let homeSummary = ProbeListSummary(entries: [
            sampleEntry(instance: home, name: "a", online: true, cpu: 12, net: 1200),
            sampleEntry(instance: home, name: "c", online: false, cpu: nil, net: 0),
        ])
        let roomSummary = ProbeListSummary(entries: [sampleEntry(instance: room, name: "edge", online: true, cpu: 20, net: 400)])
        carousel.setContainerWidth(390, margin: 16)
        carousel.configure([
            ProbeCard(id: home, name: "家里", summary: homeSummary, updated: "刚刚", hasError: false, isSelected: true),
            ProbeCard(id: room, name: "机房", summary: roomSummary, updated: "连接失败", hasError: true, isSelected: false),
        ])
        host.layoutIfNeeded()

        XCTAssertEqual(carousel.cardIDs, [home, room])
        XCTAssertTrue(carousel.pagesAreEnabled)
        // 两侧各露出一截相邻卡片，卡片高度收敛到 170pt 以内。
        let layout = carousel.layout
        XCTAssertEqual(layout.itemSize.width, 390 - 2 * (16 + 10), accuracy: 0.5)
        XCTAssertLessThan(layout.itemSize.height, 170)
        XCTAssertGreaterThan(layout.itemSize.height, 120)
        XCTAssertEqual(carousel.bounds.height, layout.itemSize.height, accuracy: 0.5)
        let first = layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))
        let second = layout.layoutAttributesForItem(at: IndexPath(item: 1, section: 0))
        XCTAssertEqual(first?.transform.a ?? 0, 1, accuracy: 0.01)
        XCTAssertEqual(second?.transform.a ?? 0, 0.88, accuracy: 0.01)
        XCTAssertLessThan(second?.alpha ?? 1, 1)
        XCTAssertEqual(layout.targetContentOffset(forProposedContentOffset: CGPoint(x: 400, y: 0), withScrollingVelocity: .zero).x,
                       layout.pageWidth, accuracy: 0.5)

        carousel.configure([
            ProbeCard(id: home, name: "家里", summary: homeSummary, updated: "刚刚", hasError: false, isSelected: true),
        ])
        host.layoutIfNeeded()
        XCTAssertFalse(carousel.pagesAreEnabled)
        XCTAssertEqual(layout.itemSize.width, 390 - 32, accuracy: 0.5)
        XCTAssertEqual(layout.minScale, 1)
    }

    func testHeroCardSitsOnGlassWithSystemColors() {
        let card = ProbeHeroCardView()
        let model = ProbeCard(id: UUID(), name: "家里", summary: ProbeListSummary(entries: []), updated: "刚刚", hasError: false, isSelected: false)
        card.configure(model, interactive: false)
        XCTAssertNil(card.backgroundColor)
        let glass = card.subviews.compactMap { $0 as? UIVisualEffectView }.first
        XCTAssertNotNil(glass?.effect)
        let title = glass?.contentView.allSubviews.compactMap { $0 as? UILabel }.first { $0.text == "家里" }
        XCTAssertEqual(title?.textColor, .label)
    }

    func testDeleteInstanceRemovesConfigAndSnapshot() async {
        let store = makeStore()
        let home = ProbeInstance(name: "家里", baseURL: URL(string: "https://home.example")!, adapterID: "komari")
        store.upsert(home)
        store.saveSnapshot(snapshot(at: now), for: home.id)
        let service = StubService(result: .success(snapshot(at: now)))
        let viewModel = ProbeMonitorViewModel(store: store, service: service, now: { self.now })

        await viewModel.deleteInstance(id: home.id)

        XCTAssertNil(store.instance(id: home.id))
        XCTAssertNil(store.snapshot(for: home.id))
        XCTAssertEqual(service.forgottenIDs, [home.id])
        viewModel.reloadInstances()
        XCTAssertNil(viewModel.selectedInstanceID)
        XCTAssertTrue(viewModel.cards.isEmpty)
    }

    func testManageMenusOfferEditAndDelete() throws {
        let store = makeStore()
        let home = ProbeInstance(name: "家里", baseURL: URL(string: "https://home.example")!, adapterID: "komari")
        let room = ProbeInstance(name: "机房", baseURL: URL(string: "https://room.example")!, adapterID: "monitor")
        store.upsert(home)
        store.upsert(room)
        store.saveSnapshot(snapshot(at: now), for: home.id)
        let viewModel = ProbeMonitorViewModel(store: store, service: StubService(result: .success(snapshot(at: now))), now: { self.now })
        let controller = ProbeMonitorViewController(viewModel: viewModel)
        controller.loadViewIfNeeded()

        XCTAssertNil(controller.navigationItem.rightBarButtonItems?.first { $0.accessibilityIdentifier == "probe-add" })
        let more = try XCTUnwrap(controller.navigationItem.rightBarButtonItems?.first { $0.accessibilityIdentifier == "probe-more-menu" })
        XCTAssertEqual(more.accessibilityLabel, "更多")
        let actions = menuActions(more.menu)
        XCTAssertEqual(actions.prefix(3).map(\.title), ["添加探针", "编辑当前探针", "删除当前探针"])
        XCTAssertTrue(actions.first { $0.title == "删除当前探针" }?.attributes.contains(.destructive) ?? false)

        let table = try XCTUnwrap(controller.view.view(matchingIdentifier: "probe-monitor-table") as? UITableView)
        let header = try XCTUnwrap(controller.tableView(table, viewForHeaderInSection: 0) as? ProbeSectionHeaderView)
        let headerActions = menuActions(header.menuButton.menu)
        XCTAssertEqual(headerActions.map(\.title), ["编辑探针", "删除探针"])
        XCTAssertTrue(headerActions.last?.attributes.contains(.destructive) ?? false)

        let carousel = try XCTUnwrap(controller.view.view(matchingIdentifier: "probe-hero-carousel")?.superview as? ProbeHeroCarouselView)
        XCTAssertEqual(carousel.contextMenu(at: 0)?.children.compactMap { $0 as? UIAction }.map(\.title), ["编辑当前探针", "删除当前探针"])
        // 旁边那张还没选中，长按不出菜单。
        XCTAssertNil(carousel.contextMenu(at: 1))
    }

    private func menuActions(_ menu: UIMenu?) -> [UIAction] {
        guard let menu else { return [] }
        return menu.children.flatMap { element -> [UIAction] in
            if let action = element as? UIAction { return [action] }
            if let nested = element as? UIMenu { return menuActions(nested) }
            return []
        }
    }

    func testFilterRowCarriesSortMenu() {
        let chips = ProbeFilterChipsView(frame: CGRect(x: 0, y: 0, width: 370, height: 32))
        var picked: ProbeListSort?
        chips.onSort = { picked = $0 }
        chips.configure(selected: .all, counts: [:], sort: .cpu)
        chips.layoutIfNeeded()
        let button = chips.allSubviews.compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "probe-sort-menu" }
        XCTAssertEqual(button?.accessibilityLabel, "排序：CPU 从高到低")
        let actions = button?.menu?.children.compactMap { $0 as? UIAction } ?? []
        XCTAssertEqual(actions.count, ProbeListSort.allCases.count)
        XCTAssertEqual(actions.first { $0.state == .on }?.title, ProbeListSort.cpu.title)
        if #available(iOS 16.0, *) {
            actions.first { $0.title == ProbeListSort.name.title }?.performWithSender(nil, target: nil)
            XCTAssertEqual(picked, .name)
        }
    }

    func testRefreshIntervalPersistsAndWidensStaleWindow() {
        let store = makeStore()
        let viewModel = ProbeMonitorViewModel(store: store, service: StubService(result: .success(snapshot(at: now))), now: { self.now })
        XCTAssertEqual(viewModel.refreshInterval, 10)
        XCTAssertEqual(viewModel.staleInterval, 90)
        viewModel.setRefreshInterval(60)
        XCTAssertEqual(store.refreshInterval, 60)
        XCTAssertEqual(viewModel.staleInterval, 180)
        // 不在档位里的值按默认处理。
        store.refreshInterval = 7
        XCTAssertEqual(store.refreshInterval, 10)
    }

    func testSparklineMapsTouchToNearestSample() {
        let chart = ProbeSparklineView(frame: CGRect(x: 0, y: 0, width: 300, height: 100))
        chart.values = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
        chart.layoutIfNeeded()
        XCTAssertEqual(chart.nearestIndex(toX: -20), 0)
        XCTAssertEqual(chart.nearestIndex(toX: 152), 5)
        XCTAssertEqual(chart.nearestIndex(toX: 400), 10)
    }

    func testCompactModeFollowsCountUnlessUserChooses() async {
        let store = makeStore()
        store.upsert(ProbeInstance(name: "Prod", baseURL: URL(string: "https://p.example")!, adapterID: "komari"))
        let viewModel = ProbeMonitorViewModel(store: store, service: StubService(result: .success(snapshot(at: now))), now: { self.now })
        await viewModel.refresh()
        XCTAssertFalse(viewModel.usesCompactList)
        viewModel.setCompact(true)
        XCTAssertTrue(viewModel.usesCompactList)
    }

    private final class FakeLocator: ProbeLocating {
        var authorization: ProbeLocationAuthorization
        var lastCoordinate: CLLocationCoordinate2D?
        var onAuthorizationChange: (() -> Void)?
        var authorizationRequests = 0
        var pending: [(Result<CLLocationCoordinate2D, Error>) -> Void] = []

        init(_ authorization: ProbeLocationAuthorization) { self.authorization = authorization }
        func requestAuthorization() { authorizationRequests += 1 }
        func requestLocation(completion: @escaping (Result<CLLocationCoordinate2D, Error>) -> Void) { pending.append(completion) }

        func complete(_ result: Result<CLLocationCoordinate2D, Error>) {
            if case .success(let coordinate) = result { lastCoordinate = coordinate }
            pending.forEach { $0(result) }
            pending = []
        }
    }

    private func makeGlobePage(_ locator: FakeLocator) throws -> (ProbeGlobeViewController, UIWindow) {
        let viewModel = ProbeMonitorViewModel(store: makeStore(), service: StubService(result: .success(snapshot(at: now))), now: { self.now })
        let page = ProbeGlobeViewController(viewModel: viewModel, locator: locator)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = page
        window.makeKeyAndVisible()
        addTeardownBlock { window.isHidden = true }
        page.viewDidAppear(false)
        return (page, window)
    }

    func testGlobeAsksForLocationOnceThenLocatesFromButton() throws {
        let locator = FakeLocator(.notDetermined)
        let (page, _) = try makeGlobePage(locator)
        // 第一次进页面自动弹授权框；没拿到位置前按钮是“未定位”。
        XCTAssertEqual(locator.authorizationRequests, 1)
        XCTAssertEqual(page.locateButton.accessibilityValue, "未定位")

        // 用户允许后立刻定位，成功后变成“已定位”。
        locator.authorization = .authorized
        locator.onAuthorizationChange?()
        XCTAssertEqual(page.locateButton.accessibilityValue, "定位中")
        locator.complete(.success(CLLocationCoordinate2D(latitude: 31.2, longitude: 121.5)))
        XCTAssertEqual(page.locateButton.accessibilityValue, "已定位")

        // 点按钮重新定位；失败时保留之前的位置。
        page.locateTapped()
        XCTAssertEqual(locator.pending.count, 1)
        locator.complete(.failure(ProbeLocationProvider.TimeoutError()))
        XCTAssertEqual(page.locateButton.accessibilityValue, "已定位")
    }

    func testGlobeLocatesAutomaticallyWhenAlreadyAuthorized() throws {
        let locator = FakeLocator(.authorized)
        let (page, _) = try makeGlobePage(locator)
        XCTAssertEqual(locator.authorizationRequests, 0)
        XCTAssertEqual(locator.pending.count, 1)
        XCTAssertEqual(page.locateButton.accessibilityValue, "定位中")
        locator.complete(.failure(ProbeLocationProvider.TimeoutError()))
        XCTAssertEqual(page.locateButton.accessibilityValue, "未定位")
    }

    func testGlobeDeniedLocationOffersSettingsInsteadOfAsking() throws {
        let locator = FakeLocator(.denied)
        let (page, _) = try makeGlobePage(locator)
        XCTAssertEqual(locator.authorizationRequests, 0)
        XCTAssertTrue(locator.pending.isEmpty)
        XCTAssertEqual(page.locateButton.accessibilityValue, "定位权限已关闭")
        page.locateTapped()
        let alert = try XCTUnwrap(page.presentedViewController as? UIAlertController)
        XCTAssertEqual(alert.actions.map(\.title), ["取消", "去设置"])
    }

    private func makeStore() -> ProbeInstanceStore {
        let suite = "probe-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return ProbeInstanceStore(defaults: defaults)
    }

    private func sampleEntry(instance: UUID, name: String, online: Bool, cpu: Double?, net: Int64) -> ProbeListEntry {
        let node = ProbeNode(id: name, name: name, region: nil, group: nil, os: nil, cpuCores: 2, memTotal: 100, diskTotal: 100, weight: 0)
        let metrics = ProbeMetrics(cpuPercent: cpu, memUsed: 10, memTotal: 100, netInRate: net, netOutRate: net)
        let status = ProbeStatus(nodeID: name, online: online, sampledAt: nil, metrics: metrics)
        return ProbeListEntry(instanceID: instance, instanceName: "probe", server: ProbeServer(node: node, status: status),
                              displayName: name, isStale: false, panelIndex: 0)
    }

    private func snapshot(at date: Date, ids: [String] = ["a", "b", "c"], online: Bool = true, netIn: Int64? = nil, netOut: Int64? = nil) -> ProbeSnapshot {
        let nodes = ids.enumerated().map { index, id in
            ProbeNode(id: id, name: id, region: nil, group: nil, os: nil, cpuCores: 2, memTotal: 100, diskTotal: 100, weight: index)
        }
        let statuses = Dictionary(uniqueKeysWithValues: nodes.map { node in
            (node.id, ProbeStatus(nodeID: node.id, online: online, sampledAt: date,
                                  metrics: ProbeMetrics(cpuPercent: 95, memUsed: 10, memTotal: 100, netInRate: netIn, netOutRate: netOut)))
        })
        return ProbeSnapshot(nodes: nodes, statuses: statuses, fetchedAt: date)
    }
}

private extension UIView {
    func view(matchingIdentifier identifier: String) -> UIView? {
        if accessibilityIdentifier == identifier { return self }
        for subview in subviews {
            if let match = subview.view(matchingIdentifier: identifier) { return match }
        }
        return nil
    }
}

private extension UIView {
    var allSubviews: [UIView] { subviews + subviews.flatMap(\.allSubviews) }
}
