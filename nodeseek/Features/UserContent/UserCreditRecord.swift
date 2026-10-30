import Foundation

/// 接口每行依次为变动数、变动后余额、理由、时间，没有独立记录 ID。
nonisolated struct UserCreditRecord: Decodable, Equatable, Sendable {
    let diff: Int
    let balance: Int
    let reason: String
    let createdAt: String

    init(diff: Int, balance: Int, reason: String, createdAt: String) {
        self.diff = diff
        self.balance = balance
        self.reason = reason
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        var row = try decoder.unkeyedContainer()
        diff = try row.decode(Int.self)
        balance = try row.decode(Int.self)
        reason = try row.decode(String.self)
        createdAt = try row.decode(String.self)
        guard row.isAtEnd else {
            throw DecodingError.dataCorruptedError(in: row, debugDescription: "鸡腿记录字段数不匹配")
        }
    }

    var changeText: String { diff > 0 ? "+\(diff)" : "\(diff)" }
}

nonisolated struct UserCreditPage: Sendable {
    let records: [UserCreditRecord]
    let total: Int

    // 与网页版一致：每页 20 条，最多展示 100 页。
    var pageCount: Int { min(100, max(0, total / 20 + (total % 20 > 0 ? 1 : 0))) }
}

protocol UserCreditLoading {
    func loadCredits(page: Int) async throws -> UserCreditPage
    func loadProfile(uid: Int) async throws -> UserProfileRecord
}

extension NodeSeekUserContentClient: UserCreditLoading {}

@MainActor
final class UserCreditViewModel {
    let uid: Int
    private let client: any UserCreditLoading
    private var generation = UUID()
    private(set) var records: [UserCreditRecord] = []
    private(set) var profile: UserProfileRecord?
    private(set) var loadedPage = 0
    private(set) var hasMore = false
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?
    private(set) var failedRefresh = false
    var onChange: (() -> Void)?

    init(uid: Int, profile: UserProfileRecord? = nil, client: any UserCreditLoading) {
        self.uid = uid
        self.profile = profile?.uid == uid ? profile : nil
        self.client = client
    }

    func load(refresh: Bool) async {
        guard refresh || (!isLoading && hasMore) else { return }
        let token = UUID()
        generation = token
        let requestedPage = refresh ? 1 : loadedPage + 1
        isLoading = true
        errorMessage = nil
        failedRefresh = false
        onChange?()
        do {
            let page = try await client.loadCredits(page: requestedPage)
            guard generation == token, !Task.isCancelled else { return }
            guard page.total >= 0, !page.records.isEmpty || requestedPage > page.pageCount else {
                throw UserContentClientError.unsuccessfulResponse
            }
            // 无记录 ID，不能以相同理由或时间去重，否则会丢掉真实流水。
            records = refresh ? page.records : records + page.records
            loadedPage = requestedPage
            hasMore = requestedPage < page.pageCount
            hasLoaded = true
        } catch {
            guard generation == token, !Task.isCancelled else { return }
            failedRefresh = refresh
            errorMessage = records.isEmpty ? "鸡腿明细加载失败" : "加载失败，点按重试"
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
