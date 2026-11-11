import Foundation

/// 探针节点的静态信息，低频获取并缓存。
nonisolated struct ProbeNode: Codable, Equatable, Sendable {
    let id: String
    var name: String
    /// 地区展示。Komari 是国旗 emoji，极简探针是国家代码。
    var region: String?
    var group: String?
    var os: String?
    var cpuCores: Int?
    var memTotal: Int64?
    var diskTotal: Int64?
    /// 节点排序权重，越小越靠前。
    var weight: Int
    // 以下为面板可选填写的信息，旧缓存里没有，因此都是可选。
    var virtualization: String? = nil
    var arch: String? = nil
    var tags: [String]? = nil
    /// 面板写给访客看的公开备注。
    var remark: String? = nil
    var plan: ProbePlan? = nil
}

/// 某个时刻的运行指标。指标全部可选：拿不到时界面显示“—”，不能当作 0。
nonisolated struct ProbeMetrics: Codable, Equatable, Sendable {
    var cpuPercent: Double?
    var memUsed: Int64?
    var memTotal: Int64?
    var diskUsed: Int64?
    var diskTotal: Int64?
    var swapUsed: Int64?
    var swapTotal: Int64?
    /// 字节/秒。
    var netInRate: Int64?
    var netOutRate: Int64?
    /// 累计流量（字节）。
    var netTotalIn: Int64?
    var netTotalOut: Int64?
    var load1: Double?
    var load5: Double?
    var load15: Double?
    /// 秒。
    var uptime: Int64?
    var processCount: Int?
    var connectionCount: Int?
    /// 流量配额统计用的下行 / 上行字节数（本月或自上次重置以来）。
    var trafficIn: Int64? = nil
    var trafficOut: Int64? = nil

    var memPercent: Double? { Self.percent(memUsed, memTotal) }
    var diskPercent: Double? { Self.percent(diskUsed, diskTotal) }

    private static func percent(_ used: Int64?, _ total: Int64?) -> Double? {
        guard let used, let total, total > 0 else { return nil }
        return Double(used) / Double(total) * 100
    }
}

/// 面板对某节点给出的最新状态。
nonisolated struct ProbeStatus: Codable, Equatable, Sendable {
    let nodeID: String
    /// 面板判定的在线状态。Komari 在 agent 断开约 30–40 秒后才置为 false。
    var online: Bool
    /// 探针采样时间；离线后保持为最后一次上报的时间。
    var sampledAt: Date?
    var metrics: ProbeMetrics
}

/// 历史曲线上的一个点。Komari 历史记录里的内存总量为 0，内存百分比需要结合节点总量计算。
nonisolated struct ProbeHistoryPoint: Codable, Equatable, Sendable {
    let date: Date
    var metrics: ProbeMetrics
}

/// 用户添加的一个探针面板。只保存地址和展示偏好，不保存凭证。
nonisolated struct ProbeInstance: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    var name: String
    var baseURL: URL
    /// 对应适配器配置的 id，例如 "komari"。
    var adapterID: String
    /// 用户隐藏的节点；新出现的节点默认显示。
    var hiddenNodeIDs: Set<String>
    /// 用户拖动后的顺序；未出现在这里的节点按面板顺序排在后面。
    var nodeOrder: [String]
    /// 本机显示用的别名，不修改面板上的名称。
    var aliases: [String: String]

    init(id: UUID = UUID(), name: String, baseURL: URL, adapterID: String,
         hiddenNodeIDs: Set<String> = [], nodeOrder: [String] = [], aliases: [String: String] = [:]) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.adapterID = adapterID
        self.hiddenNodeIDs = hiddenNodeIDs
        self.nodeOrder = nodeOrder
        self.aliases = aliases
    }
}

/// 节点合并静态信息与最新状态后的可用性。
nonisolated enum ProbeAvailability: Equatable, Sendable {
    case online
    /// 面板明确报告离线，附带的指标是最后一次上报的值。
    case offline
    /// 节点在列表里，但最新状态中没有它。常见于面板重启后、该节点尚未重新上报（多半已离线），
    /// 只能显示“暂无数据”，不能断言离线。
    case unknown
}

nonisolated struct ProbeServer: Equatable, Sendable {
    var node: ProbeNode
    var status: ProbeStatus?

    var availability: ProbeAvailability {
        guard let status else { return .unknown }
        return status.online ? .online : .offline
    }

    /// 合并节点列表与最新状态。结果按权重、名称排序；最新状态里出现但不在节点列表中的条目会被忽略。
    static func merge(nodes: [ProbeNode], statuses: [String: ProbeStatus]) -> [ProbeServer] {
        nodes
            .sorted { ($0.weight, $0.name) < ($1.weight, $1.name) }
            .map { ProbeServer(node: $0, status: statuses[$0.id]) }
    }
}

/// 请求探针失败的原因，只保留可展示的类别，不携带响应体或地址。
nonisolated enum ProbeFetchError: String, Codable, Error, Equatable, Sendable {
    /// 面板开启了私有站点，游客无法读取。
    case privateSite
    /// 401/403 或权限不足。
    case unauthorized
    /// 面板开启了 Cloudflare Turnstile 人机验证，App 无法完成验证。
    case humanVerification
    /// 指定节点不存在或对游客隐藏。
    case nodeNotFound
    /// 面板版本不支持该接口（例如没有 rpc2）。
    case unsupported
    /// 面板不可达，或反向代理返回 5xx。
    case unreachable
    /// 响应格式不符合预期。
    case decoding
}
