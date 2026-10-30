import Foundation

nonisolated struct UserStardustRecord: Decodable, Equatable, Sendable {
    let id: Int
    let memberID: Int
    let peerID: Int?
    let type: String
    let diff: Int
    let result: Int
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, type, diff, result
        case memberID = "member_id"
        case peerID = "peer_id"
        case createdAt = "created_at"
    }

    var typeText: String {
        switch type {
        case "system": return "系统"
        case "admin": return "管理"
        case "transfer": return "转账"
        case "upvote": return "点赞"
        case "buyCode": return "购买邀请码"
        default: return type
        }
    }

    var changeText: String { diff > 0 ? "+\(diff)" : "\(diff)" }
    // 原站只有转出记录反转流向；扣款不能一概当成向对方转出。
    var isOutgoingTransfer: Bool { type == "transfer" && diff < 0 }
    var validPeerID: Int? { peerID.flatMap { $0 > 0 ? $0 : nil } }
}

nonisolated struct UserStardustPage: Decodable, Sendable {
    let records: [UserStardustRecord]
    let hasMore: Bool
    let cursor: Int?

    enum CodingKeys: String, CodingKey {
        case records, cursor
        case hasMore = "exist_more"
    }
}

protocol UserStardustLoading {
    func loadStardust(uid: Int, beforeID: Int?) async throws -> UserStardustPage
    func loadProfile(uid: Int) async throws -> UserProfileRecord
}

extension NodeSeekUserContentClient: UserStardustLoading {}

/// 首屏、刷新与分页共用状态；失败不推进游标，旧请求不能覆盖刷新结果。
@MainActor
final class UserStardustViewModel {
    let uid: Int
    private let client: any UserStardustLoading
    private var generation = UUID()
    private(set) var records: [UserStardustRecord] = []
    private(set) var profile: UserProfileRecord?
    private(set) var cursor: Int?
    private(set) var hasMore = false
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?
    private(set) var failedRefresh = false
    var onChange: (() -> Void)?

    init(uid: Int, profile: UserProfileRecord? = nil, client: any UserStardustLoading) {
        self.uid = uid
        self.profile = profile?.uid == uid ? profile : nil
        self.client = client
    }

    func load(refresh: Bool) async {
        guard refresh || (!isLoading && hasMore) else { return }
        let token = UUID()
        generation = token
        let beforeID = refresh ? nil : cursor
        isLoading = true
        errorMessage = nil
        failedRefresh = false
        onChange?()
        do {
            let page = try await client.loadStardust(uid: uid, beforeID: beforeID)
            guard generation == token, !Task.isCancelled else { return }
            // 后端异常游标应可重试，不能无限请求同一页或把它误报为全部加载完。
            if page.hasMore {
                guard !page.records.isEmpty, let nextCursor = page.cursor,
                      beforeID.map({ nextCursor < $0 }) ?? true else {
                    throw UserContentClientError.unsuccessfulResponse
                }
            }
            var seen = Set(refresh ? [] : records.map(\.id))
            let additions = page.records.filter { seen.insert($0.id).inserted }
            records = refresh ? additions : records + additions
            cursor = page.cursor
            hasMore = page.hasMore
            hasLoaded = true
        } catch {
            guard generation == token, !Task.isCancelled else { return }
            failedRefresh = refresh
            errorMessage = records.isEmpty ? "星辰记录加载失败" : "加载失败，点按重试"
        }
        isLoading = false
        onChange?()
    }

    func refreshProfile() async {
        guard let loaded = try? await client.loadProfile(uid: uid), !Task.isCancelled else { return }
        profile = loaded
        onChange?()
    }
}
