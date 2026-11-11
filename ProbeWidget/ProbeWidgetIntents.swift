import AppIntents
import Foundation
import WidgetKit

// MARK: - 选探针

/// 长按编辑小组件时可选的探针。
struct ProbeScopeEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "探针"
    static let defaultQuery = ProbeScopeQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct ProbeScopeQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [ProbeScopeEntity] {
        await Self.all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ProbeScopeEntity] {
        await Self.all()
    }

    @MainActor
    private static func all() -> [ProbeScopeEntity] {
        ProbeWidgetSource.store.instances.map { ProbeScopeEntity(id: $0.id, name: $0.name) }
    }
}

struct ProbeScopeIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "选择探针"
    static let description = IntentDescription("不选时显示全部探针。")

    @Parameter(title: "探针")
    var probe: ProbeScopeEntity?
}

// MARK: - 选服务器

/// 长按编辑单台小组件时可选的服务器，来自 App 最近一次的缓存。
struct ProbeServerEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "服务器"
    static let defaultQuery = ProbeServerQuery()

    /// 形如 “探针 UUID/节点 ID”，与列表条目的 id 一致。
    let id: String
    let name: String
    let probeName: String
    let flag: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\([flag, name].compactMap { $0 }.joined(separator: " "))", subtitle: "\(probeName)")
    }

    var instanceID: UUID? { ProbeWidgetLink(entryID: id)?.instanceID }
}

struct ProbeServerQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ProbeServerEntity] {
        await Self.all().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [ProbeServerEntity] {
        let keyword = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = await Self.all()
        guard !keyword.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(keyword) || $0.probeName.localizedCaseInsensitiveContains(keyword) }
    }

    func suggestedEntities() async throws -> [ProbeServerEntity] {
        await Self.all()
    }

    @MainActor
    private static func all() -> [ProbeServerEntity] {
        let store = ProbeWidgetSource.store
        return store.instances.flatMap { instance -> [ProbeServerEntity] in
            guard let snapshot = store.snapshot(for: instance.id) else { return [] }
            return ProbeListEntry.entries(instance: instance, snapshot: snapshot, isStale: true).map {
                ProbeServerEntity(id: $0.id, name: $0.displayName, probeName: instance.name, flag: $0.flag)
            }
        }
    }
}

struct ProbeServerIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "选择服务器"
    static let description = IntentDescription("不选时显示第一台服务器。")

    @Parameter(title: "服务器")
    var server: ProbeServerEntity?
}
