//
//  CurrentAccountRefresher.swift
//  nodeseek
//
//  Created by Codex on 2026/5/1.
//

import Foundation

protocol CurrentAccountRefreshing: Sendable {
    func cachedAccount() async -> AccountResponse?

    @discardableResult
    func refreshIfNeeded(force: Bool, maxAge: TimeInterval) async -> AccountResponse?
}

actor CurrentAccountRefresher: CurrentAccountRefreshing {
    @MainActor
    static let shared: CurrentAccountRefresher = {
        let service = NodeSeekService(htmlClient: HiddenWebViewHTMLClient.isolated())
        return CurrentAccountRefresher(service: service, store: .shared)
    }()

    private let service: NodeSeekService
    private let store: CurrentAccountStore
    private var inFlightTask: Task<AccountResponse?, Never>?

    init(service: NodeSeekService, store: CurrentAccountStore = .shared) {
        self.service = service
        self.store = store
    }

    func cachedAccount() async -> AccountResponse? {
        await store.snapshot()?.account
    }

    @discardableResult
    func refreshIfNeeded(force: Bool = false, maxAge: TimeInterval) async -> AccountResponse? {
        if !force, await store.shouldRefresh(maxAge: maxAge) == false {
            let account = await store.snapshot()?.account
            AppLog.debug(.account, "refresher: skip, cache fresh -> \(account.debugSummary)")
            return account
        }

        if let inFlightTask {
            AppLog.debug(.account, "refresher: join in-flight task")
            return await inFlightTask.value
        }

        AppLog.debug(.account, "refresher: start loadAccount force=\(force) maxAge=\(Int(maxAge))")
        let task = Task<AccountResponse?, Never> {
            do {
                let result = try await service.loadAccount()
                switch result {
                case .value(let account):
                    await store.save(account)
                    AppLog.debug(.account, "refresher: save -> \(account.debugSummary)")
                    return account
                case .challenge:
                    let account = await store.snapshot()?.account
                    AppLog.debug(.account, "refresher: challenge -> cached \(account.debugSummary)")
                    return account
                }
            } catch {
                let account = await store.snapshot()?.account
                AppLog.debug(.account, "refresher: error \(error.localizedDescription) -> cached \(account.debugSummary)")
                return account
            }
        }
        inFlightTask = task
        let account = await task.value
        inFlightTask = nil
        return account
    }
}

extension Notification.Name {
    static let nodeSeekLoginSessionDidClose = Notification.Name("nodeSeekLoginSessionDidClose")
    static let nodeSeekNotificationReadStateDidChange = Notification.Name("nodeSeekNotificationReadStateDidChange")
    static let nodeSeekNotificationUnreadCountDidUpdate = Notification.Name("nodeSeekNotificationUnreadCountDidUpdate")
}

private extension Optional where Wrapped == AccountResponse {
    nonisolated var debugSummary: String {
        switch self {
        case .some(let account):
            account.debugSummary
        case .none:
            "nil"
        }
    }
}

private extension AccountResponse {
    nonisolated var debugSummary: String {
        "loggedIn=\(isLoggedIn) name=\(displayName) avatar=\(avatarURL?.path ?? "nil") profile=\(profileURL?.path ?? "nil") stats=\(stats.joined(separator: "|"))"
    }
}
