//
//  PostListSideMenuAccountControllerTests.swift
//  nodeseekTests
//

import Foundation
import Testing
@testable import nodeseek

@MainActor
struct PostListSideMenuAccountControllerTests {
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
