import Foundation

nonisolated enum UserConnectionKind: String, CaseIterable, Sendable {
    case following = "follow"
    case followers = "fans"

    var title: String { self == .following ? "关注" : "被关注" }
    var emptyText: String { self == .following ? "还没有关注任何人" : "暂无被关注用户" }
}

nonisolated struct UserConnectionRecord: Decodable, Equatable, Sendable {
    let uid: Int
    let name: String
    let rank: Int?
    let coin: Int?
    let stardust: Int?
    let bio: String?
    let postCount: Int?
    let commentCount: Int?
    let fans: Int?

    enum CodingKeys: String, CodingKey {
        case uid = "member_id"
        case name = "member_name"
        case rank, coin, stardust, bio, fans
        case postCount = "nPost"
        case commentCount = "nComment"
    }
}

protocol UserConnectionsLoading {
    func loadConnections(kind: UserConnectionKind) async throws -> [UserConnectionRecord]
}

extension NodeSeekUserContentClient: UserConnectionsLoading {}

@MainActor
final class UserConnectionsViewModel {
    struct State {
        var records: [UserConnectionRecord] = []
        var hasLoaded = false
        var isLoading = false
        var errorMessage: String?
        var showsSkeleton: Bool { !hasLoaded && errorMessage == nil }
    }

    private let client: any UserConnectionsLoading
    private var states: [UserConnectionKind: State] = [:]
    private var generations: [UserConnectionKind: UUID] = [:]
    var onChange: ((UserConnectionKind) -> Void)?

    init(client: any UserConnectionsLoading) { self.client = client }

    func state(for kind: UserConnectionKind) -> State { states[kind] ?? State() }

    func load(_ kind: UserConnectionKind, refresh: Bool = false) async {
        var state = state(for: kind)
        guard refresh || (!state.isLoading && !state.hasLoaded) else { return }
        let token = UUID()
        generations[kind] = token
        state.isLoading = true
        state.errorMessage = nil
        states[kind] = state
        onChange?(kind)
        do {
            let records = try await client.loadConnections(kind: kind)
            guard generations[kind] == token, !Task.isCancelled else { return }
            state.records = records
            state.hasLoaded = true
        } catch {
            guard generations[kind] == token, !Task.isCancelled else { return }
            state.errorMessage = "\(kind.title)列表加载失败"
        }
        state.isLoading = false
        states[kind] = state
        onChange?(kind)
    }
}
