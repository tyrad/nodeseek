//
//  AccountVaultStore.swift
//  nodeseek
//

import Foundation

/// 本地已保存多账号元数据仓库，负责列表排序、活跃账号标识与切号中断恢复标记。
final class AccountVaultStore: @unchecked Sendable {
    nonisolated static let shared = AccountVaultStore()
    nonisolated static let didChangeNotification = Notification.Name("AccountVaultStore.didChange")

    private struct StoragePayload: Codable {
        var schemaVersion: Int
        var activeUID: Int?
        var accounts: [SavedAccount]
    }

    private let lock = NSLock()
    private let userDefaults: UserDefaults
    private let storageKey: String
    private let initializedKey: String
    private let pendingSwitchKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "com.nodeseek.account-vault",
        initializedKey: String = "com.nodeseek.account-vault.initialized",
        pendingSwitchKey: String = "com.nodeseek.account-vault.pending-switch"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        self.initializedKey = initializedKey
        self.pendingSwitchKey = pendingSwitchKey
    }

    var isInitialized: Bool {
        lock.withLock {
            userDefaults.bool(forKey: initializedKey) || userDefaults.data(forKey: storageKey) != nil
        }
    }

    func markInitialized() {
        lock.withLock {
            userDefaults.set(true, forKey: initializedKey)
        }
    }

    var activeUID: Int? {
        lock.withLock { loadPayloadLocked().activeUID }
    }

    var accounts: [SavedAccount] {
        lock.withLock {
            let payload = loadPayloadLocked()
            return Self.sortedAccounts(payload.accounts, activeUID: payload.activeUID)
        }
    }

    var activeAccount: SavedAccount? {
        lock.withLock {
            let payload = loadPayloadLocked()
            guard let activeUID = payload.activeUID else { return nil }
            return payload.accounts.first { $0.uid == activeUID }
        }
    }

    var pendingSwitchTargetUID: Int? {
        get {
            lock.withLock {
                guard let number = userDefaults.object(forKey: pendingSwitchKey) as? NSNumber else {
                    return nil
                }
                let value = number.intValue
                return value > 0 ? value : nil
            }
        }
        set {
            lock.withLock {
                if let newValue, newValue > 0 {
                    userDefaults.set(newValue, forKey: pendingSwitchKey)
                } else {
                    userDefaults.removeObject(forKey: pendingSwitchKey)
                }
            }
        }
    }

    func account(uid: Int) -> SavedAccount? {
        lock.withLock {
            loadPayloadLocked().accounts.first { $0.uid == uid }
        }
    }

    func hasOtherAccounts(excluding uid: Int?) -> Bool {
        lock.withLock {
            loadPayloadLocked().accounts.contains { $0.uid != uid }
        }
    }

    func otherValidAccounts(excluding uid: Int?) -> [SavedAccount] {
        lock.withLock {
            let payload = loadPayloadLocked()
            return Self.sortedAccounts(payload.accounts, activeUID: payload.activeUID)
                .filter { $0.uid != uid && $0.credentialState == .valid }
        }
    }

    @discardableResult
    func upsert(_ account: SavedAccount, setActive: Bool) -> SavedAccount {
        let result: SavedAccount = lock.withLock {
            var payload = loadPayloadLocked()
            if let index = payload.accounts.firstIndex(where: { $0.uid == account.uid }) {
                var merged = account
                // 避免刷新时缺少可选头像或统计把已有展示字段抹空。
                if merged.avatarURL == nil {
                    merged.avatarURL = payload.accounts[index].avatarURL
                }
                if merged.stats.isEmpty {
                    merged.stats = payload.accounts[index].stats
                }
                payload.accounts[index] = merged
            } else {
                payload.accounts.append(account)
            }
            if setActive {
                payload.activeUID = account.uid
            }
            persistLocked(payload)
            return payload.accounts.first { $0.uid == account.uid } ?? account
        }
        postDidChange()
        return result
    }

    func setActive(uid: Int?, touchLastUsedAt date: Date? = nil) {
        let changed: Bool = lock.withLock {
            var payload = loadPayloadLocked()
            if let uid {
                guard let index = payload.accounts.firstIndex(where: { $0.uid == uid }) else {
                    return false
                }
                if let date {
                    payload.accounts[index].lastUsedAt = date
                }
            }
            payload.activeUID = uid
            persistLocked(payload)
            return true
        }
        if changed {
            postDidChange()
        }
    }

    func markCredentialState(_ state: AccountCredentialState, for uid: Int) {
        let changed: Bool = lock.withLock {
            var payload = loadPayloadLocked()
            guard let index = payload.accounts.firstIndex(where: { $0.uid == uid }) else {
                return false
            }
            guard payload.accounts[index].credentialState != state else {
                return false
            }
            payload.accounts[index].credentialState = state
            persistLocked(payload)
            return true
        }
        if changed {
            postDidChange()
        }
    }

    @discardableResult
    func remove(uid: Int) -> Bool {
        let removed: Bool = lock.withLock {
            var payload = loadPayloadLocked()
            let before = payload.accounts.count
            payload.accounts.removeAll { $0.uid == uid }
            guard payload.accounts.count != before else { return false }
            if payload.activeUID == uid {
                payload.activeUID = nil
            }
            persistLocked(payload)
            return true
        }
        if removed {
            postDidChange()
        }
        return removed
    }

    private func loadPayloadLocked() -> StoragePayload {
        guard let data = userDefaults.data(forKey: storageKey),
              let payload = try? decoder.decode(StoragePayload.self, from: data) else {
            return StoragePayload(schemaVersion: 1, activeUID: nil, accounts: [])
        }
        return payload
    }

    private func persistLocked(_ payload: StoragePayload) {
        userDefaults.set(true, forKey: initializedKey)
        guard let data = try? encoder.encode(payload) else { return }
        userDefaults.set(data, forKey: storageKey)
    }

    private func postDidChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    private static func sortedAccounts(_ accounts: [SavedAccount], activeUID: Int?) -> [SavedAccount] {
        accounts.sorted { lhs, rhs in
            if lhs.uid == activeUID { return true }
            if rhs.uid == activeUID { return false }
            if lhs.lastUsedAt != rhs.lastUsedAt {
                return lhs.lastUsedAt > rhs.lastUsedAt
            }
            return lhs.uid < rhs.uid
        }
    }
}
