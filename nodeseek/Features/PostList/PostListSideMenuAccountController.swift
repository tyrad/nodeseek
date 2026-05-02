//
//  PostListSideMenuAccountController.swift
//  nodeseek
//
//  Created by Codex on 2026/5/1.
//

import Foundation

@MainActor
final class PostListSideMenuAccountController {
    private static let guestAccount = AccountResponse(displayName: "游客", isLoggedIn: false)

    var canRefresh: () -> Bool = { true }
    var isSideMenuVisible: () -> Bool = { false }
    var onAccountChanged: ((AccountResponse) -> Void)?
    #if DEBUG
    var onDebugTextChanged: ((String) -> Void)?
    #endif

    private let currentAccountStore: CurrentAccountStore
    private let accountRefresher: any CurrentAccountRefreshing
    private let refreshMaxAge: TimeInterval
    private var latestAccount = AccountResponse(displayName: "游客", isLoggedIn: false)
    private var shouldForceRefreshOnNextShow = false
    private var refreshTask: Task<Void, Never>?
    private var loginCloseObserver: NSObjectProtocol?
    #if DEBUG
    private var accountDebugObserver: NSObjectProtocol?
    private var accountDebugLines: [String] = []
    #endif

    var isLoggedIn: Bool {
        latestAccount.isLoggedIn
    }

    init(
        currentAccountStore: CurrentAccountStore = .shared,
        accountRefresher: (any CurrentAccountRefreshing)? = nil,
        refreshMaxAge: TimeInterval = 60
    ) {
        self.currentAccountStore = currentAccountStore
        self.accountRefresher = accountRefresher ?? CurrentAccountRefresher.shared
        self.refreshMaxAge = refreshMaxAge
    }

    deinit {
        refreshTask?.cancel()
        if let loginCloseObserver {
            NotificationCenter.default.removeObserver(loginCloseObserver)
        }
        #if DEBUG
        if let accountDebugObserver {
            NotificationCenter.default.removeObserver(accountDebugObserver)
        }
        #endif
    }

    func start() {
        observeSessionChanges()
        loadStoredAccount()
    }

    func refreshIfNeeded(force: Bool = false) {
        guard canRefresh() else {
            appendDebug("ui: refresh skipped, no window")
            return
        }
        guard refreshTask == nil else {
            appendDebug("ui: refresh skipped, task running")
            return
        }
        let effectiveForce = force || shouldForceRefreshOnNextShow
        appendDebug("ui: refresh requested force=\(effectiveForce)")
        shouldForceRefreshOnNextShow = false
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { refreshTask = nil }
            let account = await accountRefresher.refreshIfNeeded(
                force: effectiveForce,
                maxAge: refreshMaxAge
            )
            guard !Task.isCancelled else { return }
            if let account {
                appendDebug("ui: refresh result loggedIn=\(account.isLoggedIn) name=\(account.displayName)")
                publish(account)
                return
            }
            let snapshot = await currentAccountStore.snapshot()
            appendDebug("ui: refresh result nil, fallback stored=\(snapshot?.account.displayName ?? "nil")")
            publish(snapshot?.account ?? Self.guestAccount)
        }
    }

    #if DEBUG
    var debugText: String {
        "账号调试日志\n" + accountDebugLines.joined(separator: "\n")
    }
    #endif

    private func observeSessionChanges() {
        loginCloseObserver = NotificationCenter.default.addObserver(
            forName: .nodeSeekLoginSessionDidClose,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.appendDebug("ui: login session closed, mark stale")
                self.shouldForceRefreshOnNextShow = true
                let currentAccountStore = self.currentAccountStore
                await currentAccountStore.markStale()
                if self.isSideMenuVisible() {
                    self.refreshIfNeeded(force: true)
                }
            }
        }

        #if DEBUG
        accountDebugObserver = NotificationCenter.default.addObserver(
            forName: .nodeSeekCurrentAccountDebugMessage,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let message = notification.userInfo?[AppLog.accountDebugMessageKey] as? String
            Task { @MainActor [weak self, message] in
                guard let self, let message else { return }
                self.appendDebug(message)
            }
        }
        #endif
    }

    private func loadStoredAccount() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let snapshot = await currentAccountStore.snapshot()
            if let snapshot {
                appendDebug("ui: stored loggedIn=\(snapshot.account.isLoggedIn) name=\(snapshot.account.displayName) age=\(Int(Date().timeIntervalSince(snapshot.updatedAt)))s")
            } else {
                appendDebug("ui: stored nil")
            }
            publish(snapshot?.account ?? Self.guestAccount)
        }
    }

    private func publish(_ account: AccountResponse) {
        appendDebug("ui: render loggedIn=\(account.isLoggedIn) name=\(account.displayName)")
        latestAccount = account
        onAccountChanged?(account)
    }

    private func appendDebug(_ message: String) {
        #if DEBUG
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        accountDebugLines.append("\(formatter.string(from: Date())) \(message)")
        accountDebugLines = Array(accountDebugLines.suffix(12))
        onDebugTextChanged?(debugText)
        #endif
    }
}
