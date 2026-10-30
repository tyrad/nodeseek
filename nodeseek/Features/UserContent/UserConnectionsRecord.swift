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
    /// 当前账号是否已关注此人；被关注列表里可能为 false（未回关）
    var followed: Bool?

    enum CodingKeys: String, CodingKey {
        case uid = "member_id"
        case name = "member_name"
        case rank, coin, stardust, bio, fans, followed
        case postCount = "nPost"
        case commentCount = "nComment"
    }
}

protocol UserConnectionsLoading {
    func loadConnections(kind: UserConnectionKind) async throws -> [UserConnectionRecord]
    func setFollowing(_ follow: Bool, uid: Int) async throws
}

extension NodeSeekUserContentClient: UserConnectionsLoading {}

@MainActor
final class UserConnectionsViewModel {
    struct State {
        var records: [UserConnectionRecord] = []
        var hasLoaded = false
        var isLoading = false
        var errorMessage: String?
        /// 另一个列表里关注状态变了，这个列表下次切过来时静默刷新
        var isStale = false
        var showsSkeleton: Bool { !hasLoaded && errorMessage == nil }
    }

    private let client: any UserConnectionsLoading
    private var states: [UserConnectionKind: State] = [:]
    private var generations: [UserConnectionKind: UUID] = [:]
    private(set) var pendingUIDs: Set<Int> = []
    var onChange: ((UserConnectionKind) -> Void)?

    init(client: any UserConnectionsLoading) { self.client = client }

    func state(for kind: UserConnectionKind) -> State { states[kind] ?? State() }

    func load(_ kind: UserConnectionKind, refresh: Bool = false) async {
        var state = state(for: kind)
        guard refresh || state.isStale || (!state.isLoading && !state.hasLoaded) else { return }
        let token = UUID()
        generations[kind] = token
        state.isLoading = true
        state.isStale = false
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

    /// 切换关注状态，成功后两个列表里同一个人一起更新；失败返回提示文案。
    /// 取消关注后先保留在列表里，方便马上点回来，下次刷新才移除。
    func toggleFollow(uid: Int) async -> String? {
        guard !pendingUIDs.contains(uid) else { return nil }
        let follow = !(currentRecord(uid: uid)?.followed ?? false)
        pendingUIDs.insert(uid)
        notifyAll()
        defer {
            pendingUIDs.remove(uid)
            notifyAll()
        }
        do {
            try await client.setFollowing(follow, uid: uid)
        } catch {
            return error.localizedDescription
        }
        for kind in UserConnectionKind.allCases {
            guard var state = states[kind] else { continue }
            var touched = false
            for index in state.records.indices where state.records[index].uid == uid {
                state.records[index].followed = follow
                touched = true
            }
            // 新关注的人不在「关注」列表里，标记下次切过去时刷新
            if !touched, state.hasLoaded { state.isStale = true }
            states[kind] = state
        }
        return nil
    }

    private func currentRecord(uid: Int) -> UserConnectionRecord? {
        UserConnectionKind.allCases.lazy.compactMap { self.states[$0]?.records.first { $0.uid == uid } }.first
    }

    private func notifyAll() {
        UserConnectionKind.allCases.forEach { onChange?($0) }
    }
}
