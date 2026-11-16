//
//  SeekMailUnreadMonitor.swift
//  nodeseek
//

import UIKit

/// 回到前台时检查新邮件：入口显示全部邮箱的未读数，有新邮件时通知打开着的列表刷新。
/// 不做后台轮询，两次检查至少隔 30 秒。
final class SeekMailUnreadMonitor {
    static let shared = SeekMailUnreadMonitor(keyStore: SeekMailAPIKeyStore.shared)

    /// 未读数变化后发出，入口据此更新角标。
    static let didChangeNotification = Notification.Name("SeekMailUnreadMonitor.didChange")
    /// 增量查询发现新邮件后发出，打开着的列表据此刷新。
    static let newMailNotification = Notification.Name("SeekMailUnreadMonitor.newMail")

    static let minimumInterval: TimeInterval = 30
    static let fullSyncInterval: TimeInterval = 24 * 60 * 60

    private let keyStore: SeekMailAPIKeyStoring
    private let provider: SeekMailProvider<SeekMailAPI>
    private let defaults: UserDefaults
    private let notificationCenter: NotificationCenter
    private let now: () -> Date
    private var lastCheck: Date?
    private var task: Task<Void, Never>?
    private var started = false

    /// nil 表示没绑定 Key 或还没查过，入口不显示数字。
    private(set) var totalUnread: Int?

    private enum Key {
        static let maxID = "seekMail.unread.maxID"
        static let lastFullSync = "seekMail.unread.lastFullSync"
    }

    init(keyStore: SeekMailAPIKeyStoring,
         transport: SeekMailProvider<SeekMailAPI>.Transport? = nil,
         defaults: UserDefaults = .standard,
         notificationCenter: NotificationCenter = .default,
         now: @escaping () -> Date = Date.init) {
        self.keyStore = keyStore
        if let transport {
            provider = SeekMailProvider(apiKey: { [keyStore] in keyStore.apiKey() }, transport: transport)
        } else {
            provider = SeekMailProvider(apiKey: { [keyStore] in keyStore.apiKey() })
        }
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        self.now = now
    }

    /// 各入口加载时调用，重复调用无副作用。
    func start() {
        guard started == false else { return }
        started = true
        notificationCenter.addObserver(self, selector: #selector(appDidBecomeActive),
                                       name: UIApplication.didBecomeActiveNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(keyDidChange),
                                       name: SeekMailAPIKeyStore.didChangeNotification, object: nil)
        check(force: true)
    }

    @objc private func appDidBecomeActive() {
        check()
    }

    /// 换 Key 或移除 Key：旧账号的数字和增量位置都作废。
    @objc private func keyDidChange() {
        defaults.removeObject(forKey: Key.maxID)
        defaults.removeObject(forKey: Key.lastFullSync)
        check(force: true)
    }

    /// force 用于 Key 变化或离开邮箱页（刚读过邮件，数字要跟上），不受 30 秒限制。
    func check(force: Bool = false) {
        guard keyStore.hasAPIKey else {
            task?.cancel()
            setTotal(nil)
            return
        }
        let current = now()
        if force == false, let lastCheck, current.timeIntervalSince(lastCheck) < Self.minimumInterval { return }
        lastCheck = current
        task?.cancel()
        task = Task { [weak self] in
            await self?.performCheck(at: current)
        }
    }

    private func performCheck(at date: Date) async {
        do {
            let counts = try await provider.unreadCounts()
            setTotal(counts.total)
            try await checkNewMail(at: date)
        } catch is CancellationError {
        } catch {
            // 检查失败不打扰用户，保留上次的数字；Key 失效时清掉
            if case .unauthorized? = error as? SeekMailError { setTotal(nil) }
        }
    }

    /// 用 after_id 只拿新邮件；每天做一次不带 after_id 的完整同步，校正最大 ID。
    private func checkNewMail(at date: Date) async throws {
        let storedMaxID = (defaults.object(forKey: Key.maxID) as? NSNumber)?.int64Value
        let lastFull = defaults.object(forKey: Key.lastFullSync) as? Date
        let needsFullSync = storedMaxID == nil || lastFull.map { date.timeIntervalSince($0) >= Self.fullSyncInterval } ?? true
        let page = try await provider.unreadMails(limit: 50, afterID: needsFullSync ? nil : storedMaxID)
        let maxID = page.mails.map(\.id).max()
        if needsFullSync {
            defaults.set(date, forKey: Key.lastFullSync)
            // 完整同步只更新位置；第一次查询没有旧位置可比，不算新邮件
            let next = max(maxID ?? 0, storedMaxID ?? 0)
            if next > 0 { defaults.set(NSNumber(value: next), forKey: Key.maxID) }
            if let storedMaxID, let maxID, maxID > storedMaxID { postNewMail(page.mails.filter { $0.id > storedMaxID }) }
            return
        }
        guard let maxID else { return }
        defaults.set(NSNumber(value: max(maxID, storedMaxID ?? 0)), forKey: Key.maxID)
        postNewMail(page.mails)
    }

    private func postNewMail(_ mails: [SeekUnreadMail]) {
        guard mails.isEmpty == false else { return }
        notificationCenter.post(name: Self.newMailNotification, object: self, userInfo: ["count": mails.count])
    }

    private func setTotal(_ value: Int?) {
        guard value != totalUnread else { return }
        totalUnread = value
        notificationCenter.post(name: Self.didChangeNotification, object: self)
    }

    /// 入口上显示的文字：0 或未知时不显示。
    static func badgeText(_ count: Int?) -> String? {
        guard let count, count > 0 else { return nil }
        return count > 99 ? "99+" : "\(count)"
    }
}
