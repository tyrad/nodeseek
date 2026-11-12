import Foundation

extension ProbeServer {
    /// 先按用户拖动的顺序，没排过的节点按面板顺序接在后面；隐藏的节点不显示。App 和小组件共用。
    nonisolated static func ordered(snapshot: ProbeSnapshot, instance: ProbeInstance) -> [ProbeServer] {
        let servers = merge(nodes: snapshot.nodes, statuses: snapshot.statuses)
            .filter { !instance.hiddenNodeIDs.contains($0.node.id) }
        let position = Dictionary(instance.nodeOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return servers.enumerated().sorted { lhs, rhs in
            let left = position[lhs.element.node.id] ?? Int.max, right = position[rhs.element.node.id] ?? Int.max
            return left != right ? left < right : lhs.offset < rhs.offset
        }.map(\.element)
    }
}

extension ProbeListEntry {
    /// 一个探针快照展开成列表条目。
    nonisolated static func entries(instance: ProbeInstance, snapshot: ProbeSnapshot, isStale: Bool) -> [ProbeListEntry] {
        ProbeServer.ordered(snapshot: snapshot, instance: instance).enumerated().map { index, server in
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

    /// 地区对应的国旗，认不出时为空。
    nonisolated var flag: String? {
        ProbeGeo.countryCode(from: server.node.region).map(ProbeGeo.flag(for:))
    }
}

/// 小组件点按后打开 App 的链接：nsconnect://probe 进列表，带 instance 和 node 时进这台服务器的详情。
nonisolated struct ProbeWidgetLink: Equatable, Sendable {
    static let scheme = "nsconnect"
    static let host = "probe"

    var instanceID: UUID?
    var nodeID: String?

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        if let instanceID, let nodeID {
            components.queryItems = [
                URLQueryItem(name: "instance", value: instanceID.uuidString),
                URLQueryItem(name: "node", value: nodeID),
            ]
        }
        return components.url ?? URL(string: "\(Self.scheme)://\(Self.host)")!
    }

    init(instanceID: UUID? = nil, nodeID: String? = nil) {
        self.instanceID = instanceID
        self.nodeID = nodeID
    }

    /// 列表条目 id（“探针 UUID/节点 ID”）拆开；节点 ID 本身可能带斜杠，只按第一个斜杠拆。
    init?(entryID: String) {
        guard let slash = entryID.firstIndex(of: "/"),
              let instance = UUID(uuidString: String(entryID[..<slash])) else { return nil }
        let node = String(entryID[entryID.index(after: slash)...])
        guard !node.isEmpty else { return nil }
        self.init(instanceID: instance, nodeID: node)
    }

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, url.host?.lowercased() == Self.host else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let instance = items.first { $0.name == "instance" }?.value.flatMap(UUID.init(uuidString:))
        let node = items.first { $0.name == "node" }?.value.flatMap { $0.isEmpty ? nil : $0 }
        // 两个参数要么都有，要么都没有，缺一个就只进列表。
        if let instance, let node {
            self.init(instanceID: instance, nodeID: node)
        } else {
            self.init()
        }
    }
}

/// 小组件要显示的内容：在线数、需要关注的服务器、最近到期。只做整理，不碰网络和存储，方便单测。
nonisolated struct ProbeWidgetDigest: Equatable, Sendable {
    nonisolated struct Item: Equatable, Sendable, Identifiable {
        enum Kind: Int, Equatable, Sendable {
            case offline, alert, expiry, traffic, normal
        }

        let entryID: String
        let instanceID: UUID
        let nodeID: String
        let name: String
        let flag: String?
        let kind: Kind
        /// 右侧的状态文字：“离线 2 小时”“内存 93%”“3 天后到期”“流量 92%”“CPU 4.1%”。
        let value: String
        var id: String { entryID }
    }

    /// 关注列表里的告警只算 ≥90%，比 App 列表的 70% 更严，小组件只提真正要处理的事。
    static let alertThreshold = ProbeUsageLevel.criticalThreshold
    static let expiryWarningDays = 7
    static let trafficThreshold = 90.0

    var total = 0
    var online = 0
    var offline = 0
    var alerts = 0
    /// 关注列表，已按 离线 → 告警 → 到期 → 流量 排好，一台服务器只出现一次。
    var attention: [Item] = []
    /// 全部正常时展示的几台：CPU 最高的在前。
    var quiet: [Item] = []
    /// 最近一台有到期日的服务器（不含长期有效）。
    var nearestExpiry: Item?
    var nearestExpiryLevel: ProbePlanSummary.Level = .normal

    init(entries: [ProbeListEntry], now: Date = Date(), calendar: Calendar = .current) {
        total = entries.count
        var expiryCandidates: [(entry: ProbeListEntry, days: Int, summary: ProbePlanSummary)] = []
        for entry in entries {
            let summary = ProbePlanSummary(plan: entry.server.node.plan, metrics: entry.server.status?.metrics, now: now, calendar: calendar)
            if let plan = entry.server.node.plan, !plan.isLongTerm(now: now),
               let days = plan.daysLeft(now: now, calendar: calendar), let summary {
                expiryCandidates.append((entry, days, summary))
            }
            if let item = Self.attentionItem(entry, summary: summary, now: now) {
                attention.append(item)
            }
            guard !entry.isStale else { continue }
            switch entry.server.availability {
            case .online:
                online += 1
                if (entry.alertPercent ?? 0) >= Self.alertThreshold { alerts += 1 }
            case .offline:
                offline += 1
            case .unknown:
                break
            }
        }
        // 同类按面板顺序；到期按剩余天数，最急的在前。
        let daysLeft = Dictionary(expiryCandidates.map { ($0.entry.id, $0.days) }, uniquingKeysWith: { first, _ in first })
        func rank(_ item: Item, _ offset: Int) -> (Int, Int, Int) {
            (item.kind.rawValue, item.kind == .expiry ? daysLeft[item.entryID] ?? .max : 0, offset)
        }
        attention = attention.enumerated()
            .sorted { rank($0.element, $0.offset) < rank($1.element, $1.offset) }
            .map(\.element)

        if let nearest = expiryCandidates.min(by: { $0.days < $1.days }) {
            nearestExpiry = Self.item(nearest.entry, kind: .expiry, value: nearest.summary.expiry ?? "")
            nearestExpiryLevel = nearest.summary.expiryLevel
        }

        quiet = entries
            .filter { !$0.isStale && $0.server.availability == .online }
            .sorted { ($0.server.status?.metrics.cpuPercent ?? -1) > ($1.server.status?.metrics.cpuPercent ?? -1) }
            .map { entry in
                let cpu = entry.server.status?.metrics.cpuPercent
                return Self.item(entry, kind: .normal, value: "CPU \(ProbeFormat.percent(cpu))%")
            }
    }

    private static func attentionItem(_ entry: ProbeListEntry, summary: ProbePlanSummary?, now: Date) -> Item? {
        // 缓存数据不判断离线和负载，免得把过时的状态当成问题；到期和流量与刷新无关，照常提示。
        if !entry.isStale {
            if entry.server.availability == .offline {
                return item(entry, kind: .offline, value: offlineText(since: entry.server.status?.sampledAt, now: now))
            }
            if entry.server.availability == .online, let metrics = entry.server.status?.metrics {
                let candidates: [(String, Double?)] = [("CPU", metrics.cpuPercent), (NSLocalizedString("内存", tableName: "ProbeWidget", comment: ""), metrics.memPercent), (NSLocalizedString("硬盘", tableName: "ProbeWidget", comment: ""), metrics.diskPercent)]
                if let worst = candidates.compactMap({ name, value in value.map { (name, $0) } }).max(by: { $0.1 < $1.1 }),
                   worst.1 >= alertThreshold {
                    return item(entry, kind: .alert, value: "\(worst.0) \(ProbeFormat.percent(worst.1, decimals: 0))%")
                }
            }
        }
        if let summary, let expiry = summary.expiry, summary.expiryLevel != .normal {
            return item(entry, kind: .expiry, value: expiry)
        }
        if let traffic = summary?.traffic, traffic.isOver || traffic.percent >= trafficThreshold {
            let value = traffic.isOver
                ? String(format: NSLocalizedString("流量超出 %@", tableName: "ProbeWidget", comment: ""), ProbeFormat.bytes(traffic.used - traffic.limit))
                : String(format: NSLocalizedString("流量 %@%%", tableName: "ProbeWidget", comment: ""), ProbeFormat.percent(traffic.percent, decimals: 0))
            return item(entry, kind: .traffic, value: value)
        }
        return nil
    }

    private static func item(_ entry: ProbeListEntry, kind: Item.Kind, value: String) -> Item {
        Item(entryID: entry.id, instanceID: entry.instanceID, nodeID: entry.server.node.id,
             name: entry.displayName, flag: entry.flag, kind: kind, value: value)
    }

    /// “离线 2 小时”；不知道从什么时候开始离线时只写“离线”。
    static func offlineText(since: Date?, now: Date) -> String {
        guard let since else { return NSLocalizedString("离线", tableName: "ProbeWidget", comment: "") }
        let seconds = max(0, now.timeIntervalSince(since))
        if seconds < 3600 { return String(format: NSLocalizedString("离线 %ld 分钟", tableName: "ProbeWidget", comment: ""), max(1, Int(seconds / 60))) }
        if seconds < 86_400 { return String(format: NSLocalizedString("离线 %ld 小时", tableName: "ProbeWidget", comment: ""), Int(seconds / 3600)) }
        return String(format: NSLocalizedString("离线 %ld 天", tableName: "ProbeWidget", comment: ""), Int(seconds / 86_400))
    }
}
