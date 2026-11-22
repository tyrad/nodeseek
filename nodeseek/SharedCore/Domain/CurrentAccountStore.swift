//
//  CurrentAccountStore.swift
//  nodeseek
//
//  Created by Codex on 2026/5/1.
//

import Foundation

actor CurrentAccountStore {
    nonisolated struct Snapshot: Equatable, Sendable {
        let account: AccountResponse
        let updatedAt: Date
    }

    nonisolated static let shared = CurrentAccountStore()

    nonisolated static let pendingLogoutCleanupKey = "nodeSeekSession.pendingLogoutCleanup"
    private(set) var sessionID: UUID? = UUID()

    private let userDefaults: UserDefaults
    private let storageKey: String
    private var cachedSnapshot: Snapshot?

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "com.nodeseek.current-account"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        self.cachedSnapshot = Self.loadSnapshot(userDefaults: userDefaults, storageKey: storageKey)
    }

    func snapshot() -> Snapshot? {
        cachedSnapshot
    }

    func save(_ account: AccountResponse, updatedAt: Date = Date()) {
        guard sessionID != nil else { return }
        if account.isLoggedIn {
            userDefaults.removeObject(forKey: Self.pendingLogoutCleanupKey)
        }
        let snapshot = Snapshot(account: account, updatedAt: updatedAt)
        cachedSnapshot = snapshot
        persist(snapshot)
    }

    // 退出之前发出的请求即使较晚返回，也不能用旧账号覆盖游客状态。
    @discardableResult
    func save(_ account: AccountResponse, for requestSessionID: UUID?) -> Bool {
        guard let requestSessionID, requestSessionID == sessionID else { return false }
        save(account)
        return true
    }

    func beginLogoutCleanup() {
        userDefaults.set(true, forKey: Self.pendingLogoutCleanupKey)
        sessionID = nil
        clear()
    }

    func finishLogoutCleanup(atLaunch: Bool) {
        if atLaunch {
            userDefaults.removeObject(forKey: Self.pendingLogoutCleanupKey)
        }
        sessionID = UUID()
    }

    func clear() {
        cachedSnapshot = nil
        userDefaults.removeObject(forKey: storageKey)
    }

    func markStale(now: Date = Date.distantPast) {
        guard let snapshot = cachedSnapshot else { return }
        let updated = Snapshot(account: snapshot.account, updatedAt: now)
        cachedSnapshot = updated
        persist(updated)
    }

    func shouldRefresh(maxAge: TimeInterval, now: Date = Date()) -> Bool {
        guard maxAge > 0 else { return true }
        guard let snapshot = cachedSnapshot else { return true }
        return now.timeIntervalSince(snapshot.updatedAt) > maxAge
    }

    private func persist(_ snapshot: Snapshot) {
        let persisted = Persisted(snapshot: snapshot)
        do {
            let data = try JSONEncoder().encode(persisted)
            userDefaults.set(data, forKey: storageKey)
        } catch {
            // 持久化失败不应影响正常使用；下次刷新可纠正。
        }
    }

    private static func loadSnapshot(userDefaults: UserDefaults, storageKey: String) -> Snapshot? {
        guard let data = userDefaults.data(forKey: storageKey) else { return nil }
        do {
            let persisted = try JSONDecoder().decode(Persisted.self, from: data)
            return persisted.snapshot
        } catch {
            return nil
        }
    }
}

private nonisolated struct Persisted: Codable {
    let schemaVersion: Int
    let displayName: String
    let isLoggedIn: Bool
    let avatarURL: String?
    let profileURL: String?
    let stats: [String]
    let notificationURL: String?
    let notificationIconColorCSS: String?
    let updatedAt: TimeInterval

    init(snapshot: CurrentAccountStore.Snapshot) {
        schemaVersion = 3
        displayName = snapshot.account.displayName
        isLoggedIn = snapshot.account.isLoggedIn
        avatarURL = snapshot.account.avatarURL?.absoluteString
        profileURL = snapshot.account.profileURL?.absoluteString
        stats = snapshot.account.stats
        notificationURL = snapshot.account.notification?.url.absoluteString
        notificationIconColorCSS = snapshot.account.notification?.iconColorCSS
        updatedAt = snapshot.updatedAt.timeIntervalSince1970
    }

    var snapshot: CurrentAccountStore.Snapshot {
        let notificationURL = notificationURL.flatMap(URL.init(string:))
        return CurrentAccountStore.Snapshot(
            account: AccountResponse(
                displayName: displayName,
                isLoggedIn: isLoggedIn,
                avatarURL: avatarURL.flatMap(URL.init(string:)),
                profileURL: profileURL.flatMap(URL.init(string:)),
                stats: stats,
                notification: notificationURL.map {
                    AccountNotification(url: $0, iconColorCSS: notificationIconColorCSS)
                }
            ),
            updatedAt: Date(timeIntervalSince1970: updatedAt)
        )
    }
}
