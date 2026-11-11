import SwiftUI
import WidgetKit

@main
struct ProbeWidgetBundle: WidgetBundle {
    var body: some Widget {
        ProbeOverviewWidget()
        ProbeServerWidget()
        ProbeAttentionWidget()
    }
}

// MARK: - 总览 / 关注列表

struct ProbeDigestEntry: TimelineEntry {
    let date: Date
    let data: ProbeWidgetData
    let digest: ProbeWidgetDigest
}

struct ProbeDigestProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ProbeDigestEntry {
        ProbeWidgetSample.digestEntry
    }

    func snapshot(for configuration: ProbeScopeIntent, in context: Context) async -> ProbeDigestEntry {
        if context.isPreview { return ProbeWidgetSample.digestEntry }
        return await entry(for: configuration)
    }

    func timeline(for configuration: ProbeScopeIntent, in context: Context) async -> Timeline<ProbeDigestEntry> {
        let entry = await entry(for: configuration)
        return Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(ProbeWidgetLoader.refreshInterval)))
    }

    private func entry(for configuration: ProbeScopeIntent) async -> ProbeDigestEntry {
        let now = Date()
        let data = await ProbeWidgetSource.load(instanceID: configuration.probe?.id, now: now)
        return ProbeDigestEntry(date: now, data: data, digest: ProbeWidgetDigest(entries: data.entries, now: now))
    }
}

struct ProbeOverviewWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ProbeOverview", intent: ProbeScopeIntent.self, provider: ProbeDigestProvider()) { entry in
            ProbeOverviewView(entry: entry)
                .containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
        }
        .configurationDisplayName("服务器总览")
        .description("在线数量、离线和告警，以及最近到期的服务器。")
        .supportedFamilies([.systemSmall])
    }
}

struct ProbeAttentionWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ProbeAttention", intent: ProbeScopeIntent.self, provider: ProbeDigestProvider()) { entry in
            ProbeAttentionView(entry: entry)
                .containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
        }
        .configurationDisplayName("需要关注")
        .description("离线、负载过高、快到期和流量快用完的服务器。")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - 单台

struct ProbeServerEntry: TimelineEntry {
    enum State {
        case ready(ProbeListEntry)
        /// 选过的服务器已经不在面板上。
        case missing
        case noData(ProbeWidgetData.State)
    }

    let date: Date
    let state: State
    let updatedAt: Date?
    let trend: [Double]
}

struct ProbeServerProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ProbeServerEntry {
        ProbeWidgetSample.serverEntry
    }

    func snapshot(for configuration: ProbeServerIntent, in context: Context) async -> ProbeServerEntry {
        if context.isPreview { return ProbeWidgetSample.serverEntry }
        return await entry(for: configuration, withTrend: false)
    }

    func timeline(for configuration: ProbeServerIntent, in context: Context) async -> Timeline<ProbeServerEntry> {
        let entry = await entry(for: configuration, withTrend: true)
        return Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(ProbeWidgetLoader.refreshInterval)))
    }

    private func entry(for configuration: ProbeServerIntent, withTrend: Bool) async -> ProbeServerEntry {
        let now = Date()
        let picked = configuration.server
        let data = await ProbeWidgetSource.load(instanceID: picked?.instanceID, now: now)
        guard data.state == .ready, let first = data.entries.first else {
            return ProbeServerEntry(date: now, state: .noData(data.state == .ready ? .noProbe : data.state), updatedAt: nil, trend: [])
        }
        let entry: ProbeListEntry
        if let picked {
            guard let found = data.entries.first(where: { $0.id == picked.id }) else {
                return ProbeServerEntry(date: now, state: .missing, updatedAt: data.updatedAt, trend: [])
            }
            entry = found
        } else {
            entry = first
        }
        let trend = withTrend && !entry.isStale
            ? await ProbeWidgetSource.cpuTrend(instanceID: entry.instanceID, nodeID: entry.server.node.id)
            : []
        return ProbeServerEntry(date: now, state: .ready(entry), updatedAt: data.updatedAt, trend: trend)
    }
}

struct ProbeServerWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ProbeServer", intent: ProbeServerIntent.self, provider: ProbeServerProvider()) { entry in
            ProbeServerView(entry: entry)
                .containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
        }
        .configurationDisplayName("单台服务器")
        .description("一台服务器的 CPU 趋势、内存、硬盘和到期。长按可选择服务器。")
        .supportedFamilies([.systemSmall])
    }
}
