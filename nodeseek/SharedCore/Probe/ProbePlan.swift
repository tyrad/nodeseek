import Foundation

/// 服务器的套餐信息：到期、价格、流量配额。各家探针写法不同，这里统一成一种；面板没填的项为 nil。
nonisolated struct ProbePlan: Codable, Equatable, Sendable {
    var expiresAt: Date?
    /// 大于 0 是金额，-1 是免费；0 视为未填（Komari、极简探针的默认值都是 0）。
    var price: Double?
    var currency: String?
    var cycle: ProbeBillingCycle?
    /// 流量上限（字节），0 视为不限。
    var trafficLimit: Int64?
    var trafficMode: ProbeTrafficMode?
    /// 每月几号重置流量。
    var trafficResetDay: Int?

    /// 一项都没有时不显示套餐信息。
    var isEmpty: Bool {
        expiresAt == nil && priceAmount == nil && !isFree && trafficLimit == nil
    }

    var isFree: Bool { price == -1 }
    var priceAmount: Double? { price.flatMap { $0 > 0 ? $0 : nil } }

    /// 到期日远在几十年后的，面板通常是用来表示长期有效。
    func isLongTerm(now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSince(now) > 50 * 365 * 86_400
    }

    /// 按本地日历算剩余天数：今天到期为 0，已过期为负数。
    func daysLeft(now: Date = Date(), calendar: Calendar = .current) -> Int? {
        guard let expiresAt else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: expiresAt)).day
    }

    /// 按计费方式算已用流量。
    func trafficUsed(in inbound: Int64?, out outbound: Int64?) -> Int64? {
        (trafficMode ?? .sum).used(in: inbound, out: outbound)
    }

    static func tags(from text: String?) -> [String] {
        guard let text else { return [] }
        return text.components(separatedBy: CharacterSet(charactersIn: ";,，；、|"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

/// 付款周期。Komari 存天数，CF-Server-Monitor 用 month / year 等英文名，极简探针用 monthly 或 12m。
nonisolated enum ProbeBillingCycle: Codable, Equatable, Sendable {
    case once
    case months(Int)
    case days(Int)

    private static let named: [String: Int] = [
        "month": 1, "monthly": 1,
        "quarter": 3, "quarterly": 3,
        "half_year": 6, "semiannual": 6, "semi_annual": 6,
        "year": 12, "yearly": 12, "annual": 12,
        "two_years": 24, "biennial": 24,
        "three_years": 36, "triennial": 36,
        "four_years": 48,
        "five_years": 60, "quinquennial": 60,
    ]

    /// Komari 按天数判断月、季、年的区间，与其官方主题和自动续期逻辑一致。
    private static let dayRanges: [(ClosedRange<Int>, Int)] = [
        (27...32, 1), (87...95, 3), (175...185, 6), (360...370, 12), (720...750, 24), (1080...1150, 36), (1800...1850, 60),
    ]

    init?(raw: String?) {
        guard let text = raw?.trimmingCharacters(in: .whitespaces).lowercased(), !text.isEmpty else { return nil }
        if let value = Double(text) {
            let days = Int(value)
            if days == -1 { self = .once; return }
            guard days > 0 else { return nil }
            if let months = Self.dayRanges.first(where: { $0.0.contains(days) })?.1 {
                self = .months(months)
            } else {
                self = .days(days)
            }
            return
        }
        if ["once", "one_time", "onetime", "lifetime"].contains(text) { self = .once; return }
        if let months = Self.named[text] { self = .months(months); return }
        if text.hasSuffix("m"), let months = Int(text.dropLast()), months > 0 { self = .months(months); return }
        return nil
    }

    /// 价格后面的单位：月、季、年、2 年、45 天；一次性没有单位。
    var unit: String? {
        switch self {
        case .once: return nil
        case let .days(days): return "\(days) 天"
        case let .months(months):
            switch months {
            case 1: return "月"
            case 3: return "季"
            case 6: return "半年"
            case 12: return "年"
            default: return months % 12 == 0 ? "\(months / 12) 年" : "\(months) 个月"
            }
        }
    }
}

/// 流量按哪个方向计费。
nonisolated enum ProbeTrafficMode: String, Codable, Equatable, Sendable {
    case sum, max, min, up, down

    init?(raw: String?) {
        guard let text = raw?.trimmingCharacters(in: .whitespaces).lowercased(), !text.isEmpty else { return nil }
        switch text {
        case "sum", "total", "both": self = .sum
        case "max": self = .max
        case "min": self = .min
        // CF-Server-Monitor 用 ul / dl。
        case "up", "ul", "tx", "out", "upload": self = .up
        case "down", "dl", "rx", "in", "download": self = .down
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .sum: return "双向合计"
        case .max: return "上下行取大"
        case .min: return "上下行取小"
        case .up: return "只计上行"
        case .down: return "只计下行"
        }
    }

    func used(in inbound: Int64?, out outbound: Int64?) -> Int64? {
        switch self {
        case .up: return outbound
        case .down: return inbound
        default:
            guard let inbound, let outbound else { return nil }
            switch self {
            case .max: return Swift.max(inbound, outbound)
            case .min: return Swift.min(inbound, outbound)
            default: return inbound + outbound
            }
        }
    }
}

/// 套餐信息的显示文案，列表和详情共用。
nonisolated struct ProbePlanSummary: Equatable, Sendable {
    enum Level: Equatable, Sendable { case normal, warning, critical }

    struct Traffic: Equatable, Sendable {
        var used: Int64
        var limit: Int64
        var mode: ProbeTrafficMode
        var resetDay: Int?
        var percent: Double { Double(used) / Double(limit) * 100 }
        var isOver: Bool { used > limit }
    }

    /// “152 天后到期”“今天到期”“已过期 3 天”“长期有效”。
    var expiry: String?
    var expiryLevel: Level = .normal
    /// 到期日期本身，详情页用。
    var expiryDate: String?
    /// “¥99/年”“免费”“$12 一次性”。
    var price: String?
    var traffic: Traffic?

    init?(plan: ProbePlan?, metrics: ProbeMetrics?, now: Date = Date(), calendar: Calendar = .current) {
        guard let plan else { return nil }
        if plan.isLongTerm(now: now) {
            expiry = NSLocalizedString("长期有效", tableName: "ProbeWidget", comment: "")
        } else if let days = plan.daysLeft(now: now, calendar: calendar), let date = plan.expiresAt {
            expiry = days > 0 ? String(format: NSLocalizedString("%ld 天后到期", tableName: "ProbeWidget", comment: ""), days) : days == 0 ? NSLocalizedString("今天到期", tableName: "ProbeWidget", comment: "") : String(format: NSLocalizedString("已过期 %ld 天", tableName: "ProbeWidget", comment: ""), -days)
            expiryLevel = days < 0 ? .critical : days <= 7 ? .warning : .normal
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            expiryDate = formatter.string(from: date)
        }
        if plan.isFree {
            price = "免费"
        } else if let amount = plan.priceAmount {
            let text = Self.currencySymbol(plan.currency) + Self.amount(amount)
            switch plan.cycle {
            case .once: price = text + " 一次性"
            case let cycle?: price = text + "/" + (cycle.unit ?? "")
            case nil: price = text
            }
        }
        if let limit = plan.trafficLimit, let used = plan.trafficUsed(in: metrics?.trafficIn, out: metrics?.trafficOut) {
            traffic = Traffic(used: used, limit: limit, mode: plan.trafficMode ?? .sum, resetDay: plan.trafficResetDay)
        }
        if expiry == nil && price == nil && traffic == nil { return nil }
    }

    /// 列表卡片底部的一行。
    var compact: [String] {
        var parts: [String] = []
        if let expiry { parts.append(expiry) }
        if let price { parts.append(price) }
        if let traffic {
            parts.append(traffic.isOver
                ? String(format: NSLocalizedString("流量超出 %@", tableName: "ProbeWidget", comment: ""), ProbeFormat.bytes(traffic.used - traffic.limit))
                : String(format: NSLocalizedString("流量 %@%%", tableName: "ProbeWidget", comment: ""), ProbeFormat.percent(traffic.percent, decimals: 0)))
        }
        return parts
    }

    var trafficLevel: Level {
        guard let traffic else { return .normal }
        if traffic.isOver { return .critical }
        // 与内存、硬盘同一套阈值，和进度条的变色保持一致。
        switch ProbeUsageLevel(percent: traffic.percent) {
        case .normal: return .normal
        case .warning: return .warning
        case .critical: return .critical
        }
    }

    /// 99.00 → 99，49.90 → 49.9。
    static func amount(_ value: Double) -> String {
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// 三字母币种换成常见符号；Komari、CF-Server-Monitor 本来就填符号，原样保留。
    static func currencySymbol(_ currency: String?) -> String {
        guard let currency = currency?.trimmingCharacters(in: .whitespaces), !currency.isEmpty else { return "" }
        let symbols = ["CNY": "¥", "RMB": "¥", "USD": "$", "EUR": "€", "GBP": "£", "JPY": "JP¥", "HKD": "HK$",
                       "TWD": "NT$", "CAD": "C$", "AUD": "A$", "SGD": "S$", "KRW": "₩", "RUB": "₽", "INR": "₹"]
        if let symbol = symbols[currency.uppercased()] { return symbol }
        if currency == "￥" { return "¥" }
        return currency.count == 3 && currency.allSatisfy(\.isLetter) ? currency.uppercased() + " " : currency
    }
}
