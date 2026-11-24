//
//  HotListRepository.swift
//  nodeseek
//

import Foundation

nonisolated struct HotListSnapshot: Equatable, Sendable {
    let kind: HotListKind
    let response: HotListResponse
    let fetchedAt: Date
}

/// 热榜缓存与请求节流：有效期内切换榜单不发请求，下拉刷新过于频繁时直接返回缓存，避免每个用户高频请求第三方服务。
actor HotListRepository {
    typealias Loader = @Sendable (URL) async throws -> Data

    /// 下拉刷新的最小间隔。
    static let minimumRefreshInterval: TimeInterval = 15

    private let settings: HotListSourceSettings
    private let loader: Loader
    private let now: @Sendable () -> Date
    /// 按实际请求地址缓存，用户改地址后自然不会命中旧数据。
    private var snapshots: [URL: HotListSnapshot] = [:]
    private(set) var lastSuccessAt: Date?
    private(set) var lastAttemptFailed = false

    init(
        settings: HotListSourceSettings,
        loader: @escaping Loader,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.settings = settings
        self.loader = loader
        self.now = now
    }

    func cachedSnapshot(for kind: HotListKind) -> HotListSnapshot? {
        snapshots[settings.url(for: kind)]
    }

    /// `userInitiated` 为下拉刷新：跳过有效期判断，但仍受最小刷新间隔限制。
    func load(_ kind: HotListKind, userInitiated: Bool = false) async throws -> HotListSnapshot {
        let url = settings.url(for: kind)
        if let cached = snapshots[url] {
            let age = now().timeIntervalSince(cached.fetchedAt)
            let lifetime = userInitiated ? Self.minimumRefreshInterval : kind.cacheLifetime
            if age >= 0, age < lifetime {
                return cached
            }
        }

        do {
            let response = try HotListDecoder.decode(try await loader(url))
            let snapshot = HotListSnapshot(kind: kind, response: response, fetchedAt: now())
            snapshots[url] = snapshot
            lastSuccessAt = snapshot.fetchedAt
            lastAttemptFailed = false
            return snapshot
        } catch {
            lastAttemptFailed = true
            throw error
        }
    }

    /// 设置页保存前校验地址：只解码不写缓存。
    func validate(_ url: URL) async throws -> HotListResponse {
        try HotListDecoder.decode(try await loader(url))
    }
}
