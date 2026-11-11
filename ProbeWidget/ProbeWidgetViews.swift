import SwiftUI
import WidgetKit

/// 配色：全部黑白灰，只有状态小图标带一点低饱和的红和橙。着色模式下颜色会被系统抹掉，靠图标形状区分。
enum ProbeWidgetStyle {
    static let critical = Color("ProbeCritical")
    static let warning = Color("ProbeWarning")

    static func symbol(_ kind: ProbeWidgetDigest.Item.Kind) -> String {
        switch kind {
        case .offline: return "xmark"
        case .alert: return "exclamationmark"
        case .expiry: return "clock"
        case .traffic: return "chart.pie.fill"
        case .normal: return "checkmark"
        }
    }

    static func color(_ kind: ProbeWidgetDigest.Item.Kind) -> Color {
        switch kind {
        case .offline: return critical
        case .alert, .expiry, .traffic: return warning
        case .normal: return .secondary
        }
    }

    static func color(_ level: ProbePlanSummary.Level) -> Color {
        switch level {
        case .normal: return .secondary
        case .warning: return warning
        case .critical: return critical
        }
    }

    static let caption = Font.system(size: 11, weight: .semibold)
}

/// 右上角的更新时间。小组件不会每分钟重绘，写“5 分钟前”会一直停住，所以写成具体时刻。
private struct UpdatedTime: View {
    let date: Date?
    var cached = false

    var body: some View {
        if let date {
            HStack(spacing: 2) {
                if cached { Image(systemName: "clock.arrow.circlepath") }
                Text(date, format: .dateTime.hour().minute())
            }
            .font(.system(size: 10.5, weight: .medium).monospacedDigit())
            .foregroundStyle(.tertiary)
        }
    }
}

/// 没有数据时的统一提示。
private struct ProbeWidgetMessage: View {
    let state: ProbeWidgetData.State

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "server.rack")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(ProbeWidgetLink().url)
    }

    private var title: String {
        switch state {
        case .needsAppLaunch: return "打开 App 一次"
        case .noProbe, .ready: return "还没有探针"
        }
    }

    private var detail: String {
        switch state {
        case .needsAppLaunch: return "更新后需要先打开 App，小组件才能读到探针。"
        case .noProbe, .ready: return "在 App 的探针页添加后显示。"
        }
    }
}

// MARK: - 小 · 总览

struct ProbeOverviewView: View {
    let entry: ProbeDigestEntry

    var body: some View {
        if entry.data.state != .ready || entry.data.entries.isEmpty {
            ProbeWidgetMessage(state: entry.data.state)
        } else {
            content.widgetURL(ProbeWidgetLink().url)
        }
    }

    private var digest: ProbeWidgetDigest { entry.digest }
    private var cached: Bool { entry.data.isCached }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("在线服务器").font(ProbeWidgetStyle.caption).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                UpdatedTime(date: entry.data.updatedAt, cached: cached)
            }
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(digest.online)").font(.system(size: 42, weight: .heavy).monospacedDigit())
                Text("/\(digest.total)").font(.system(size: 20, weight: .bold).monospacedDigit()).foregroundStyle(.secondary)
            }
            .foregroundStyle(cached ? .secondary : .primary)
            .padding(.top, 6)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            pills.padding(.top, 8)
            Spacer(minLength: 4)
            footer
        }
    }

    @ViewBuilder
    private var pills: some View {
        if cached {
            ProbePill(symbol: nil, text: "缓存数据", tint: .secondary)
        } else if digest.offline == 0 && digest.alerts == 0 {
            ProbePill(symbol: "checkmark", text: "全部正常", tint: .secondary)
        } else {
            HStack(spacing: 5) {
                if digest.offline > 0 { ProbePill(symbol: "xmark", text: "离线 \(digest.offline)", tint: ProbeWidgetStyle.critical) }
                if digest.alerts > 0 { ProbePill(symbol: "exclamationmark", text: "告警 \(digest.alerts)", tint: ProbeWidgetStyle.warning) }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if cached {
            Text("连不上面板，点按重试").font(ProbeWidgetStyle.caption).foregroundStyle(.secondary)
        } else if let expiry = digest.nearestExpiry {
            HStack(spacing: 3) {
                Image(systemName: "clock")
                    .foregroundStyle(ProbeWidgetStyle.color(digest.nearestExpiryLevel))
                    .widgetAccentable()
                Text(expiry.name).foregroundStyle(.primary)
                Text(expiry.value).foregroundStyle(.secondary)
            }
            .font(ProbeWidgetStyle.caption)
            .lineLimit(1)
        }
    }
}

struct ProbePill: View {
    let symbol: String?
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 3) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 9, weight: .heavy)).foregroundStyle(tint).widgetAccentable()
            }
            Text(text).font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

// MARK: - 中 · 关注列表

struct ProbeAttentionView: View {
    let entry: ProbeDigestEntry
    private let maxRows = 4

    var body: some View {
        if entry.data.state != .ready || entry.data.entries.isEmpty {
            ProbeWidgetMessage(state: entry.data.state)
        } else {
            content.widgetURL(ProbeWidgetLink().url)
        }
    }

    private var digest: ProbeWidgetDigest { entry.digest }

    private var rows: [ProbeWidgetDigest.Item] {
        if !digest.attention.isEmpty { return Array(digest.attention.prefix(maxRows)) }
        // 全部正常：CPU 最高的几台，最后一行留给最近到期。
        let quietCount = digest.nearestExpiry == nil ? maxRows : maxRows - 1
        return Array(digest.quiet.prefix(quietCount))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(digest.attention.isEmpty ? "全部正常" : "需要关注 · \(digest.attention.count)")
                    .font(ProbeWidgetStyle.caption).foregroundStyle(.secondary)
                Spacer(minLength: 6)
                HStack(spacing: 4) {
                    Text("\(digest.online)/\(digest.total) 在线").monospacedDigit()
                    if entry.data.updatedAt != nil {
                        Text("·")
                        UpdatedTime(date: entry.data.updatedAt, cached: entry.data.isCached)
                    }
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.tertiary)
            }
            .padding(.bottom, 4)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider() }
                    Link(destination: ProbeWidgetLink(instanceID: item.instanceID, nodeID: item.nodeID).url) {
                        ProbeAttentionRow(item: item, quiet: digest.attention.isEmpty)
                    }
                }
                if digest.attention.isEmpty, let expiry = digest.nearestExpiry {
                    if !rows.isEmpty { Divider() }
                    Link(destination: ProbeWidgetLink(instanceID: expiry.instanceID, nodeID: expiry.nodeID).url) {
                        ProbeAttentionRow(item: expiry, quiet: true)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct ProbeAttentionRow: View {
    let item: ProbeWidgetDigest.Item
    /// 全部正常时数值改灰，不抢眼。
    let quiet: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: ProbeWidgetStyle.symbol(item.kind))
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(quiet ? Color.secondary : ProbeWidgetStyle.color(item.kind))
                .frame(width: 14)
                .widgetAccentable()
            Text([item.flag, item.name].compactMap { $0 }.joined(separator: " "))
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(item.value)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(quiet ? .secondary : .primary)
                .lineLimit(1)
        }
        .padding(.vertical, 5)
    }
}

// MARK: - 小 · 单台

struct ProbeServerView: View {
    let entry: ProbeServerEntry

    var body: some View {
        switch entry.state {
        case let .noData(state):
            ProbeWidgetMessage(state: state)
        case .missing:
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "questionmark.circle").font(.system(size: 20, weight: .semibold)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("这台服务器已不在面板上").font(.system(size: 13, weight: .semibold))
                Text("长按小组件重新选择。").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .widgetURL(ProbeWidgetLink().url)
        case let .ready(server):
            ProbeServerContent(server: server, updatedAt: entry.updatedAt, trend: entry.trend, now: entry.date)
                .widgetURL(ProbeWidgetLink(instanceID: server.instanceID, nodeID: server.server.node.id).url)
        }
    }
}

private struct ProbeServerContent: View {
    let server: ProbeListEntry
    let updatedAt: Date?
    let trend: [Double]
    let now: Date

    private var metrics: ProbeMetrics? { server.server.status?.metrics }
    private var plan: ProbePlanSummary? { ProbePlanSummary(plan: server.server.node.plan, metrics: metrics, now: now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text([server.flag, server.displayName].compactMap { $0 }.joined(separator: " "))
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                UpdatedTime(date: updatedAt, cached: server.isStale)
            }
            Spacer(minLength: 4)
            if server.isStale || server.server.availability != .online {
                status
            } else {
                cpu
                ProbeMeterRow(title: "内存", percent: metrics?.memPercent).padding(.top, 6)
                ProbeMeterRow(title: "硬盘", percent: metrics?.diskPercent).padding(.top, 4)
            }
            Spacer(minLength: 4)
            footer
        }
    }

    private var cpu: some View {
        HStack(alignment: .bottom, spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text("CPU").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(ProbeFormat.percent(metrics?.cpuPercent)).font(.system(size: 28, weight: .heavy).monospacedDigit())
                    Text("%").font(.system(size: 13, weight: .bold))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
            if trend.count >= 2 {
                ProbeSparkline(values: trend)
                    .stroke(.primary.opacity(0.75), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .frame(height: 26)
                    .padding(.bottom, 4)
            }
        }
    }

    /// 离线或拿不到新数据时不显示负载，免得把过时的数字当成现状。
    private var status: some View {
        VStack(alignment: .leading, spacing: 4) {
            let offline = !server.isStale && server.server.availability == .offline
            Image(systemName: offline ? "xmark" : "clock.arrow.circlepath")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(offline ? ProbeWidgetStyle.critical : .secondary)
                .widgetAccentable()
            Text(offline ? ProbeWidgetDigest.offlineText(since: server.server.status?.sampledAt, now: now)
                         : server.isStale ? "连不上面板" : "暂无数据")
                .font(.system(size: 17, weight: .bold))
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let plan, let expiry = plan.expiry {
            HStack(spacing: 3) {
                if plan.expiryLevel != .normal {
                    Image(systemName: "clock").foregroundStyle(ProbeWidgetStyle.color(plan.expiryLevel)).widgetAccentable()
                }
                Text(expiry).foregroundStyle(.secondary)
            }
            .font(ProbeWidgetStyle.caption)
            .lineLimit(1)
        } else {
            Text(server.instanceName).font(ProbeWidgetStyle.caption).foregroundStyle(.tertiary).lineLimit(1)
        }
    }
}

private struct ProbeMeterRow: View {
    let title: String
    let percent: Double?

    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 10.5)).foregroundStyle(.secondary).frame(width: 26, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(.primary).frame(width: proxy.size.width * min(max((percent ?? 0) / 100, 0), 1))
                }
            }
            .frame(height: 5)
            Text(percent.map { "\(ProbeFormat.percent($0, decimals: 0))%" } ?? "—")
                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                .frame(width: 30, alignment: .trailing)
        }
    }
}

/// 折线按自身的最小、最大值拉伸，只看形状。
struct ProbeSparkline: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count >= 2, let low = values.min(), let high = values.max() else { return path }
        let span = max(high - low, 1)
        for (index, value) in values.enumerated() {
            let x = rect.minX + rect.width * CGFloat(index) / CGFloat(values.count - 1)
            let y = rect.maxY - rect.height * CGFloat((value - low) / span)
            if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }
}
