import Foundation

/// 一次成功拉取的结果，同时作为离线缓存保存。
nonisolated struct ProbeSnapshot: Codable, Equatable, Sendable {
    var nodes: [ProbeNode]
    var statuses: [String: ProbeStatus]
    var fetchedAt: Date
}

/// 列表里的一台服务器，带上所属探针和显示名称。
nonisolated struct ProbeListEntry: Equatable, Sendable {
    let instanceID: UUID
    let instanceName: String
    let server: ProbeServer
    let displayName: String
    /// 数据来自缓存且已过期，或最近一次请求失败。
    let isStale: Bool
    /// 在面板（含用户拖动排序）中的位置，用于“面板顺序”排序。
    let panelIndex: Int

    var id: String { "\(instanceID.uuidString)/\(server.node.id)" }

    var alertPercent: Double? {
        guard !isStale, server.availability == .online, let metrics = server.status?.metrics else { return nil }
        return [metrics.cpuPercent, metrics.memPercent, metrics.diskPercent].compactMap { $0 }.max()
    }

    var isAlerting: Bool { (alertPercent ?? 0) >= ProbeUsageLevel.warningThreshold }
}

nonisolated enum ProbeUsageLevel: Equatable, Sendable {
    case normal, warning, critical

    static let warningThreshold = 70.0
    static let criticalThreshold = 90.0

    init(percent: Double?) {
        guard let percent else { self = .normal; return }
        self = percent >= Self.criticalThreshold ? .critical : percent >= Self.warningThreshold ? .warning : .normal
    }
}

nonisolated enum ProbeListFilter: String, CaseIterable, Sendable {
    case all, offline, alert

    var title: String {
        switch self {
        case .all: return "全部"
        case .offline: return "离线"
        case .alert: return "告警"
        }
    }
}

nonisolated enum ProbeListSort: String, CaseIterable, Sendable {
    case problemsFirst, expiry, cpu, memory, network, name

    var title: String {
        switch self {
        case .problemsFirst: return "异常优先"
        case .expiry: return "到期时间从近到远"
        case .cpu: return "CPU 从高到低"
        case .memory: return "内存从高到低"
        case .network: return "网速从高到低"
        case .name: return "名称"
        }
    }
}

nonisolated struct ProbeListSection: Equatable, Sendable {
    let id: String
    let title: String
    let entries: [ProbeListEntry]

    var onlineCount: Int { entries.filter { $0.server.availability == .online }.count }
    var offlineCount: Int { entries.filter { $0.server.availability == .offline }.count }
    var alertCount: Int { entries.filter(\.isAlerting).count }
}

nonisolated struct ProbeListSummary: Equatable, Sendable {
    var total = 0
    var online = 0
    var offline = 0
    var alerts = 0
    var netInRate: Int64 = 0
    var netOutRate: Int64 = 0

    init(entries: [ProbeListEntry]) {
        total = entries.count
        for entry in entries {
            switch entry.server.availability {
            case .online:
                online += 1
                // 过期数据不计入实时网速。
                if !entry.isStale, let metrics = entry.server.status?.metrics {
                    netInRate += metrics.netInRate ?? 0
                    netOutRate += metrics.netOutRate ?? 0
                }
            case .offline: offline += 1
            case .unknown: break
            }
            if entry.isAlerting { alerts += 1 }
        }
    }
}

nonisolated enum ProbeServerList {
    /// 超过这个数量默认使用紧凑列表。
    static let compactThreshold = 8

    /// 按筛选、搜索、排序和分组整理列表。筛选或搜索时不分组，直接给出一个结果分组。
    static func arrange(
        _ entries: [ProbeListEntry],
        filter: ProbeListFilter,
        sort: ProbeListSort,
        query: String
    ) -> [ProbeListSection] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var matched = entries.filter { entry in
            switch filter {
            case .all: return true
            case .offline: return entry.server.availability == .offline
            case .alert: return entry.isAlerting
            }
        }
        if !keyword.isEmpty {
            matched = matched.filter { entry in
                [entry.displayName, entry.server.node.name, entry.server.node.region, entry.server.node.group, entry.instanceName]
                    .compactMap { $0 }
                    .contains { $0.localizedCaseInsensitiveContains(keyword) }
            }
        }
        let sorted = matched.sorted { lhs, rhs in
            if sort == .name {
                let order = lhs.displayName.localizedStandardCompare(rhs.displayName)
                if order != .orderedSame { return order == .orderedAscending }
            }
            let left = sortKey(lhs, sort), right = sortKey(rhs, sort)
            if left != right { return left.lexicographicallyPrecedes(right) }
            if lhs.instanceName != rhs.instanceName { return lhs.instanceName < rhs.instanceName }
            return lhs.panelIndex < rhs.panelIndex
        }
        if filter != .all || !keyword.isEmpty {
            let title = keyword.isEmpty ? filter.title : "搜索结果"
            return sorted.isEmpty ? [] : [ProbeListSection(id: "result", title: title, entries: sorted)]
        }
        // 先按探针，再按面板里的分组；分组顺序取组内第一台服务器的位置，保证异常组排在前面。
        var order: [String] = []
        var buckets: [String: (title: String, entries: [ProbeListEntry])] = [:]
        let multipleInstances = Set(entries.map(\.instanceID)).count > 1
        for entry in sorted {
            let group = entry.server.node.group
            let key = "\(entry.instanceID.uuidString)/\(group ?? "")"
            let title: String
            if let group {
                title = multipleInstances ? "\(group) · \(entry.instanceName)" : group
            } else {
                title = entry.instanceName
            }
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = (title, [])
            }
            buckets[key]?.entries.append(entry)
        }
        return order.compactMap { key in buckets[key].map { ProbeListSection(id: key, title: $0.title, entries: $0.entries) } }
    }

    /// 元组越小越靠前。
    private static func sortKey(_ entry: ProbeListEntry, _ sort: ProbeListSort) -> [Double] {
        let metrics = entry.isStale ? nil : entry.server.status?.metrics
        let panel = Double(entry.panelIndex)
        switch sort {
        case .problemsFirst:
            let rank: Double
            switch entry.server.availability {
            case .offline: rank = 0
            case .online: rank = entry.isAlerting ? 1 : 3
            case .unknown: rank = 2
            }
            // 告警组内用量高的在前。
            return [rank, rank == 1 ? -(entry.alertPercent ?? 0) : 0]
        case .expiry:
            // 已过期的日期最早，自然排最前；长期有效的日期很远，排在后面；没填到期日的排最后。
            guard let expiresAt = entry.server.node.plan?.expiresAt else { return [1, 0] }
            return [0, expiresAt.timeIntervalSince1970]
        case .cpu: return [-(metrics?.cpuPercent ?? -1)]
        case .memory: return [-(metrics?.memPercent ?? -1)]
        case .network: return [-Double((metrics?.netInRate ?? -1) + (metrics?.netOutRate ?? 0))]
        case .name: return [panel]
        }
    }
}

/// 数字格式化，App 与小组件保持一致。
nonisolated enum ProbeFormat {
    static func percent(_ value: Double?, decimals: Int = 1) -> String {
        guard let value else { return "—" }
        return String(format: "%.\(decimals)f", min(max(value, 0), 100))
    }

    /// 速率：312K、1.3M。单位 B/s。
    static func rate(_ bytesPerSecond: Int64?) -> String {
        guard let value = bytesPerSecond else { return "—" }
        return compactBytes(value)
    }

    /// 容量：412M、3.83G、354G。
    static func bytes(_ value: Int64?) -> String {
        guard let value else { return "—" }
        return compactBytes(value)
    }

    private static func compactBytes(_ value: Int64) -> String {
        let units = ["B", "K", "M", "G", "T", "P"]
        var number = Double(max(value, 0))
        var index = 0
        while number >= 1000, index < units.count - 1 {
            number /= 1024
            index += 1
        }
        if index == 0 { return "\(Int(number))B" }
        let text = number >= 100 ? String(format: "%.0f", number) : number >= 10 ? String(format: "%.1f", number) : String(format: "%.2f", number)
        return text + units[index]
    }

    /// 运行时间：65D 18H、3H 12M。
    static func uptime(_ seconds: Int64?) -> String {
        guard let seconds, seconds > 0 else { return "—" }
        let days = seconds / 86_400, hours = seconds % 86_400 / 3600, minutes = seconds % 3600 / 60
        if days > 0 { return "\(days)D \(hours)H" }
        if hours > 0 { return "\(hours)H \(minutes)M" }
        return "\(minutes)M"
    }

    /// 相对时间：刚刚、3 分钟前、2 小时前、3 天前。
    static func relative(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "—" }
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "刚刚" }
        if seconds < 3600 { return "\(Int(seconds / 60)) 分钟前" }
        if seconds < 86_400 { return "\(Int(seconds / 3600)) 小时前" }
        return "\(Int(seconds / 86_400)) 天前"
    }
}
