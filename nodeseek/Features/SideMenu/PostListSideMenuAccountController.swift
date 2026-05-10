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

    private let currentAccountStore: CurrentAccountStore
    private let accountRefresher: any CurrentAccountRefreshing
    private let refreshMaxAge: TimeInterval
    private var latestAccount = AccountResponse(displayName: "游客", isLoggedIn: false)
    private var shouldForceRefreshOnNextShow = false
    private var refreshTask: Task<Void, Never>?
    private var loginCloseObserver: NSObjectProtocol?

    var isLoggedIn: Bool {
        latestAccount.isLoggedIn
    }

    var profileURL: URL? {
        latestAccount.profileURL
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
    }

    func start() {
        observeSessionChanges()
        loadStoredAccount()
    }

    func refreshIfNeeded(force: Bool = false) {
        guard canRefresh() else {
            return
        }
        guard refreshTask == nil else {
            return
        }
        let effectiveForce = force || shouldForceRefreshOnNextShow
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
                publish(account)
                return
            }
            let snapshot = await currentAccountStore.snapshot()
            publish(snapshot?.account ?? Self.guestAccount)
        }
    }

    private func observeSessionChanges() {
        loginCloseObserver = NotificationCenter.default.addObserver(
            forName: .nodeSeekLoginSessionDidClose,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.shouldForceRefreshOnNextShow = true
                let currentAccountStore = self.currentAccountStore
                await currentAccountStore.markStale()
                if self.isSideMenuVisible() {
                    self.refreshIfNeeded(force: true)
                }
            }
        }
    }

    private func loadStoredAccount() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let snapshot = await currentAccountStore.snapshot()
            publish(snapshot?.account ?? Self.guestAccount)
        }
    }

    private func publish(_ account: AccountResponse) {
        latestAccount = account
        onAccountChanged?(account)
    }
}
