import UIKit

extension ProbeFetchError {
    var message: String {
        switch self {
        case .privateSite: return "面板开启了私有站点，游客无法读取。请在面板后台关闭“私有站点”。"
        case .unauthorized: return "面板拒绝访问，可能未对游客公开。"
        case .nodeNotFound: return "节点不存在或对游客隐藏。"
        case .unsupported: return "面板版本过旧或类型不匹配，暂不支持。"
        case .unreachable: return "无法连接面板，请检查地址和网络。"
        case .decoding: return "面板返回的数据无法识别。"
        }
    }

    static func from(_ error: Error) -> ProbeFetchError {
        error as? ProbeFetchError ?? .unreachable
    }
}

/// 顶部一张卡片对应一个探针。列表和筛选都跟着当前选中的卡片。
struct ProbeCard: Equatable {
    var id: UUID
    var name: String
    var summary: ProbeListSummary
    var updated: String
    var hasError: Bool
    var isSelected: Bool
    /// 类型和地址，例如 “Komari · status.example.com”。
    var subtitle: String = ""
    var averageCPU: Double?
    var averageMemory: Double?
    var averageDisk: Double?
    /// 卡片底部“现在该看哪台”：有离线显示离线的，否则显示最忙的。
    var spotlight: ProbeCardSpotlight?
}

struct ProbeCardSpotlight: Equatable {
    enum Kind: Equatable { case offline, busiest }

    var kind: Kind
    var entryID: String
    var title: String
    /// 离线时是最后上报时间，最忙时是最高的那项指标，例如 “CPU 46%”。
    var detail: String
    var percent: Double?

    static func pick(from items: [ProbeListEntry], now: Date) -> ProbeCardSpotlight? {
        let offline = items.filter { !$0.isStale && $0.server.availability == .offline }
        // 多台离线时显示最近掉线的那台，通常最值得先看。
        if let first = offline.max(by: { ($0.server.status?.sampledAt ?? .distantPast) < ($1.server.status?.sampledAt ?? .distantPast) }) {
            var parts = first.server.status?.sampledAt.map { [ProbeFormat.relative($0, now: now)] } ?? []
            if offline.count > 1 { parts.append("共 \(offline.count) 台") }
            let detail = parts.joined(separator: " · ")
            return ProbeCardSpotlight(kind: .offline, entryID: first.id, title: Self.title(first), detail: detail, percent: nil)
        }
        // 最忙：取 CPU / 内存 / 硬盘里用量最高的那一项。
        var best: (ProbeListEntry, String, Double)?
        for entry in items where !entry.isStale && entry.server.availability == .online {
            guard let metrics = entry.server.status?.metrics else { continue }
            let values: [(String, Double?)] = [("CPU", metrics.cpuPercent), ("内存", metrics.memPercent), ("硬盘", metrics.diskPercent)]
            for case let (name, value?) in values where value > (best?.2 ?? -1) {
                best = (entry, name, value)
            }
        }
        guard let (entry, name, value) = best else { return nil }
        return ProbeCardSpotlight(kind: .busiest, entryID: entry.id, title: Self.title(entry),
                                  detail: "\(name) \(ProbeFormat.percent(value, decimals: value < 10 ? 1 : 0))%", percent: value)
    }

    private static func title(_ entry: ProbeListEntry) -> String {
        [entry.server.node.region, entry.displayName].compactMap { $0 }.joined(separator: " ")
    }
}

/// 探针列表的状态：多探针并发刷新、缓存兜底、筛选排序，以及可见行的趋势数据。
@MainActor
final class ProbeMonitorViewModel {
    /// 自动刷新间隔，用户在列表页右上角菜单里选择。
    var refreshInterval: TimeInterval { store.refreshInterval }

    /// 超过这个时间没刷新成功，就把数据视为过期（灰显、不计入告警）。
    /// 至少 90 秒，并且不短于三个刷新周期，避免间隔调大后还没到刷新时间就先过期。
    var staleInterval: TimeInterval { max(90, refreshInterval * 3) }

    struct InstanceState {
        var snapshot: ProbeSnapshot?
        var lastError: ProbeFetchError?
    }

    let store: ProbeInstanceStore
    private let service: ProbeFetching
    private let now: () -> Date

    private(set) var states: [UUID: InstanceState] = [:]
    private(set) var entries: [ProbeListEntry] = []
    private(set) var sections: [ProbeListSection] = []
    private(set) var isRefreshing = false
    /// 当前选中的探针。只有一个探针时就是它；新增探针后切到新的那张卡。
    private(set) var selectedInstanceID: UUID?
    /// key 为 entry.id，值为最近一小时的 CPU 百分比。
    private(set) var trends: [String: [Double]] = [:]
    private var trendTasks: Set<String> = []
    private var refreshTask: Task<Void, Never>?

    var filter: ProbeListFilter = .all { didSet { rearrange() } }
    var query = "" { didSet { rearrange() } }
    var sort: ProbeListSort {
        get { store.sort }
        set { store.sort = newValue; rearrange() }
    }
    var collapsedSectionIDs: Set<String> = []

    /// 列表内容变化时回调（列表页使用）；其他页面监听 `didUpdateNotification`。
    var onChange: (() -> Void)?
    static let didUpdateNotification = Notification.Name("ProbeMonitorViewModel.didUpdate")
    var onTrendChange: ((String) -> Void)?

    init(store: ProbeInstanceStore = .shared, service: ProbeFetching = ProbeService.shared, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.service = service
        self.now = now
        for instance in store.instances {
            states[instance.id] = InstanceState(snapshot: store.snapshot(for: instance.id))
        }
        selectedInstanceID = store.instances.first?.id
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        center.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        rebuild()
    }

    var instances: [ProbeInstance] { store.instances }
    var selectedInstance: ProbeInstance? {
        if let selectedInstanceID, let instance = instances.first(where: { $0.id == selectedInstanceID }) {
            return instance
        }
        return instances.first
    }

    /// 当前卡片下的服务器。筛选和搜索再在这个范围内做。
    var visibleEntries: [ProbeListEntry] {
        guard let id = selectedInstance?.id else { return [] }
        return entries.filter { $0.instanceID == id }
    }

    var summary: ProbeListSummary { ProbeListSummary(entries: visibleEntries) }

    var cards: [ProbeCard] {
        let selected = selectedInstance?.id
        let date = now()
        return instances.map { instance in
            let state = states[instance.id]
            let hasError = state?.lastError != nil
            let updated: String
            if hasError {
                updated = "连接失败"
            } else if let fetched = state?.snapshot?.fetchedAt {
                updated = ProbeFormat.relative(fetched, now: date)
            } else {
                updated = isRefreshing ? "加载中" : "尚未加载"
            }
            let items = entries.filter { $0.instanceID == instance.id }
            // 均值只算在线且数据未过期的服务器，离线时保留的旧数值会拉偏结果。
            let live = items.filter { !$0.isStale && $0.server.availability == .online }.compactMap { $0.server.status?.metrics }
            let typeName = ProbeAdapterRegistry.shared.engine(id: instance.adapterID)?.spec.name ?? instance.adapterID
            let host = instance.baseURL.host ?? ""
            let subtitle = host.isEmpty || host == instance.name.lowercased() ? typeName : "\(typeName) · \(host)"
            return ProbeCard(
                id: instance.id,
                name: instance.name,
                summary: ProbeListSummary(entries: items),
                updated: updated,
                hasError: hasError,
                isSelected: instance.id == selected,
                subtitle: subtitle,
                averageCPU: Self.average(live.compactMap(\.cpuPercent)),
                averageMemory: Self.average(live.compactMap(\.memPercent)),
                averageDisk: Self.average(live.compactMap(\.diskPercent)),
                spotlight: ProbeCardSpotlight.pick(from: items, now: date)
            )
        }
    }

    private static func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    var usesCompactList: Bool {
        store.prefersCompactList ?? (visibleEntries.count > ProbeServerList.compactThreshold)
    }

    func setCompact(_ compact: Bool) {
        store.prefersCompactList = compact
        notify()
    }

    var filterCounts: [ProbeListFilter: Int] {
        let summary = summary
        return [.all: summary.total, .offline: summary.offline, .alert: summary.alerts]
    }

    /// 当前探针最近一次成功的时间。
    var lastUpdated: Date? {
        guard let id = selectedInstance?.id else { return nil }
        return states[id]?.snapshot?.fetchedAt
    }

    func fetchedAt(for instanceID: UUID) -> Date? {
        states[instanceID]?.snapshot?.fetchedAt
    }

    /// 当前卡片对应的失败说明。其它探针的失败留在各自卡片上。
    var selectedErrorMessage: String? {
        guard let id = selectedInstance?.id else { return nil }
        return states[id]?.lastError?.message
    }

    var failedInstances: [(ProbeInstance, ProbeFetchError)] {
        instances.compactMap { instance in states[instance.id]?.lastError.map { (instance, $0) } }
    }

    func selectInstance(_ id: UUID) {
        guard id != selectedInstanceID, instances.contains(where: { $0.id == id }) else { return }
        selectedInstanceID = id
        rearrange()
        notify()
    }

    func entry(id: String) -> ProbeListEntry? {
        entries.first { $0.id == id }
    }

    func instance(id: UUID) -> ProbeInstance? {
        store.instance(id: id)
    }

    // MARK: - 刷新

    /// 配置变更后同步状态：新增的探针加载缓存，删除的探针清理。
    func reloadInstances() {
        let known = Set(states.keys)
        let ids = Set(instances.map(\.id))
        states = states.filter { ids.contains($0.key) }
        for instance in instances where states[instance.id] == nil {
            states[instance.id] = InstanceState(snapshot: store.snapshot(for: instance.id))
        }
        // 刚添加的探针切到前台；删掉当前卡片时回到剩下的第一张。
        let added = instances.last { !known.contains($0.id) }
        if let selectedInstanceID, !ids.contains(selectedInstanceID) {
            self.selectedInstanceID = nil
        }
        if let added {
            selectedInstanceID = added.id
        } else if selectedInstanceID == nil {
            selectedInstanceID = instances.first?.id
        }
        rebuild()
    }

    func refresh(reloadNodes: Bool = false) async {
        if let refreshTask {
            await refreshTask.value
            return
        }
        let task = Task { await performRefresh(reloadNodes: reloadNodes) }
        refreshTask = task
        await task.value
        // 进后台时会丢弃在途的刷新，这里只清理自己这一次。
        if refreshTask == task { refreshTask = nil }
    }

    private func performRefresh(reloadNodes: Bool) async {
        let targets = instances
        guard !targets.isEmpty else { return }
        let generation = backgroundGeneration
        isRefreshing = true
        let service = service
        let results = await withTaskGroup(of: (UUID, Result<ProbeSnapshot, ProbeFetchError>?).self) { group in
            for instance in targets {
                group.addTask {
                    do {
                        return (instance.id, .success(try await service.snapshot(for: instance, reloadNodes: reloadNodes)))
                    } catch is CancellationError {
                        return (instance.id, nil)
                    } catch {
                        return (instance.id, .failure(ProbeFetchError.from(error)))
                    }
                }
            }
            var collected: [(UUID, Result<ProbeSnapshot, ProbeFetchError>?)] = []
            for await result in group { collected.append(result) }
            return collected
        }
        for (id, result) in results {
            guard store.instance(id: id) != nil, let result else { continue }
            switch result {
            case .success(let snapshot):
                states[id] = InstanceState(snapshot: snapshot, lastError: nil)
                store.saveSnapshot(snapshot, for: id)
            case .failure(let error):
                // 请求途中切到了后台：失败是系统中断连接造成的，不算面板连不上。
                guard generation == backgroundGeneration else { continue }
                states[id, default: InstanceState()].lastError = error
            }
        }
        isRefreshing = false
        rebuild()
        notify()
    }

    /// 页面可见时按设定间隔刷新。列表和详情页都会调用，用计数保证页面切换时不中断。
    private var autoRefreshTask: Task<Void, Never>?
    private var autoRefreshClients = 0
    private var isInBackground = false
    /// 每次进后台加一，用来识别被系统中断的请求。
    private var backgroundGeneration = 0

    func startAutoRefresh() {
        autoRefreshClients += 1
        startLoopIfNeeded()
    }

    func stopAutoRefresh() {
        autoRefreshClients = max(0, autoRefreshClients - 1)
        guard autoRefreshClients == 0 else { return }
        stopLoop()
    }

    func setRefreshInterval(_ interval: TimeInterval) {
        guard interval != store.refreshInterval else { return }
        store.refreshInterval = interval
        rebuild()
        notify()
        // 重新开始计时，新间隔立即生效。
        if autoRefreshTask != nil {
            stopLoop()
            startLoopIfNeeded()
        }
    }

    private func startLoopIfNeeded() {
        guard autoRefreshClients > 0, !isInBackground, autoRefreshTask == nil else { return }
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                guard let interval = self?.refreshInterval else { return }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    private func stopLoop() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    @objc private func appDidEnterBackground() {
        isInBackground = true
        backgroundGeneration += 1
        stopLoop()
        // 在途的刷新回来后结果会被丢弃，不再让回到前台的第一次刷新等它。
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// 回到前台立即刷新一次，再按间隔继续。
    @objc private func appWillEnterForeground() {
        isInBackground = false
        startLoopIfNeeded()
    }

    private func notify() {
        onChange?()
        NotificationCenter.default.post(name: Self.didUpdateNotification, object: self)
    }

    // MARK: - 趋势

    /// 列表滚动到某行时调用，只为可见行请求历史数据；服务层有缓存和并发合并。
    func loadTrend(for entry: ProbeListEntry) {
        guard trendTasks.insert(entry.id).inserted, let instance = store.instance(id: entry.instanceID) else { return }
        let service = service
        Task { [weak self] in
            let points = (try? await service.history(for: instance, nodeID: entry.server.node.id, hours: 1)) ?? []
            guard let self else { return }
            trendTasks.remove(entry.id)
            let values = points.compactMap(\.metrics.cpuPercent)
            guard trends[entry.id] != values else { return }
            trends[entry.id] = values
            onTrendChange?(entry.id)
        }
    }

    func history(for entry: ProbeListEntry, hours: Int) async throws -> [ProbeHistoryPoint] {
        guard let instance = store.instance(id: entry.instanceID) else { return [] }
        return try await service.history(for: instance, nodeID: entry.server.node.id, hours: hours)
    }

    // MARK: - 编辑

    func setAlias(_ alias: String?, for entry: ProbeListEntry) {
        guard var instance = store.instance(id: entry.instanceID) else { return }
        let trimmed = alias?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        instance.aliases[entry.server.node.id] = trimmed.isEmpty || trimmed == entry.server.node.name ? nil : trimmed
        store.upsert(instance)
        rebuild()
        notify()
    }

    func hide(_ entry: ProbeListEntry) {
        guard var instance = store.instance(id: entry.instanceID) else { return }
        instance.hiddenNodeIDs.insert(entry.server.node.id)
        store.upsert(instance)
        rebuild()
        notify()
    }

    func toggleSection(_ id: String) {
        if collapsedSectionIDs.remove(id) == nil { collapsedSectionIDs.insert(id) }
        notify()
    }

    /// 分组只属于一个探针时返回它，用于分组头的“编辑探针”菜单。
    func instanceID(forSection section: ProbeListSection) -> UUID? {
        let ids = Set(section.entries.map(\.instanceID))
        return ids.count == 1 ? ids.first : nil
    }

    // MARK: - 整理

    private func rebuild() {
        let date = now()
        entries = instances.flatMap { instance -> [ProbeListEntry] in
            guard let state = states[instance.id], let snapshot = state.snapshot else { return [] }
            let isStale = state.lastError != nil || date.timeIntervalSince(snapshot.fetchedAt) > staleInterval
            return Self.orderedServers(snapshot: snapshot, instance: instance).enumerated().map { index, server in
                ProbeListEntry(
                    instanceID: instance.id,
                    instanceName: instance.name,
                    server: server,
                    displayName: instance.aliases[server.node.id] ?? server.node.name,
                    isStale: isStale,
                    panelIndex: index
                )
            }
        }
        rearrange()
    }

    private func rearrange() {
        sections = ProbeServerList.arrange(visibleEntries, filter: filter, sort: sort, query: query)
    }

    /// 先按用户拖动的顺序，没排过的节点按面板顺序接在后面；隐藏的节点不显示。
    static func orderedServers(snapshot: ProbeSnapshot, instance: ProbeInstance) -> [ProbeServer] {
        let servers = ProbeServer.merge(nodes: snapshot.nodes, statuses: snapshot.statuses)
            .filter { !instance.hiddenNodeIDs.contains($0.node.id) }
        let position = Dictionary(instance.nodeOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return servers.enumerated().sorted { lhs, rhs in
            let left = position[lhs.element.node.id] ?? Int.max, right = position[rhs.element.node.id] ?? Int.max
            return left != right ? left < right : lhs.offset < rhs.offset
        }.map(\.element)
    }
}
