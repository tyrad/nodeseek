//
//  PostListSideMenuAccountControllerTests.swift
//  nodeseekTests
//

import Foundation
import Testing
@testable import nodeseek

@MainActor
struct PostListSideMenuAccountControllerTests {
    @Test func hiddenPagePublishesStoredIdentityOnLoginAndLogout() async throws {
        let suite = "side-menu-session-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CurrentAccountStore(userDefaults: defaults)
        let member = AccountResponse(displayName: "测试账号", isLoggedIn: true)
        let refresher = ForceOnlyAccountRefresher(forcedAccount: member)
        let controller = PostListSideMenuAccountController(currentAccountStore: store, accountRefresher: refresher)
        var lastAccount: AccountResponse?
        controller.onAccountChanged = { lastAccount = $0 }
        controller.start()

        func expectPublished(_ expected: AccountResponse) async throws {
            for _ in 0..<100 where lastAccount != expected {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            #expect(lastAccount == expected)
        }
        let guest = AccountResponse(displayName: "游客", isLoggedIn: false)
        try await expectPublished(guest)
        await store.save(member)
        NotificationCenter.default.post(name: .nodeSeekLoginSessionDidClose, object: nil)
        try await expectPublished(member)
        await store.clear()
        NotificationCenter.default.post(name: .nodeSeekLoginSessionDidClose, object: nil)
        try await expectPublished(guest)
        #expect(refresher.forcedCallCount() == 0)
    }

    @Test func refreshNowWaitsForForcedAccountEvenWhenNormalRefreshIsRunning() async throws {
        let defaults = try #require(UserDefaults(suiteName: "side-menu-account-\(UUID().uuidString)"))
        let store = CurrentAccountStore(userDefaults: defaults, storageKey: "account")
        let refresher = ForceOnlyAccountRefresher(
            forcedAccount: AccountResponse(displayName: "mistj", isLoggedIn: true)
        )
        let controller = PostListSideMenuAccountController(
            currentAccountStore: store,
            accountRefresher: refresher
        )
        var published: [AccountResponse] = []
        controller.onAccountChanged = { published.append($0) }

        // 普通刷新只读缓存（这里是游客），下拉刷新要等它结束后再强制刷新一次
        controller.refreshIfNeeded()
        await controller.refreshNow()

        #expect(controller.isLoggedIn)
        #expect(published.last?.displayName == "mistj")
        #expect(refresher.forcedCallCount() == 1)
    }
}

private final class ForceOnlyAccountRefresher: CurrentAccountRefreshing, @unchecked Sendable {
    private let forcedAccount: AccountResponse
    private var forcedCalls = 0

    init(forcedAccount: AccountResponse) {
        self.forcedAccount = forcedAccount
    }

    func forcedCallCount() -> Int {
        forcedCalls
    }

    func cachedAccount() async -> AccountResponse? {
        nil
    }

    func refreshIfNeeded(force: Bool, maxAge: TimeInterval) async -> AccountResponse? {
        guard force else { return nil }
        forcedCalls += 1
        return forcedAccount
    }
}
