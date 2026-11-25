//
//  AccountSwitchCoordinatorTests.swift
//  nodeseekTests
//

import Foundation
import Testing
import UIKit
@testable import nodeseek

@MainActor
@Suite(.serialized)
struct AccountSwitchCoordinatorTests {
    private func makeCookie(
        name: String,
        value: String,
        domain: String = "www.nodeseek.com",
        path: String = "/",
        expires: Date? = Date(timeIntervalSinceNow: 3600)
    ) throws -> HTTPCookie {
        var props: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path,
        ]
        if let expires {
            props[.expires] = expires
        }
        return try #require(HTTPCookie(properties: props))
    }

    private func makeIsolatedEnvironment() throws -> (
        defaults: UserDefaults,
        vaultStore: AccountVaultStore,
        cookieVault: InMemoryAccountCookieVault,
        webStore: FakeAccountWebCookieStore,
        urlStorage: HTTPCookieStorage,
        bridge: CookieBridge,
        cookieSession: NodeSeekCookieSession,
        currentAccountStore: CurrentAccountStore
    ) {
        let suite = "accounts-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let vaultStore = AccountVaultStore(userDefaults: defaults)
        let cookieVault = InMemoryAccountCookieVault()
        let webStore = FakeAccountWebCookieStore()
        let urlStorage = try #require(URLSessionConfiguration.ephemeral.httpCookieStorage)
        let bridge = CookieBridge(webCookieStore: webStore, urlCookieStorage: urlStorage)
        let cookieSession = NodeSeekCookieSession(bridge: bridge, webCookieStore: webStore)
        let currentAccountStore = CurrentAccountStore(userDefaults: defaults, storageKey: "current-account")
        return (defaults, vaultStore, cookieVault, webStore, urlStorage, bridge, cookieSession, currentAccountStore)
    }

    @Test func replaceAccountCookiesClearsBothStoresAndPreservesCloudflareWithoutRevival() async throws {
        let env = try makeIsolatedEnvironment()

        let aSession = try makeCookie(name: "session", value: "a-sess", domain: "www.nodeseek.com")
        let aSmac = try makeCookie(name: "smac", value: "a-smac", domain: ".nodeseek.com")
        let cfClearance = try makeCookie(name: "cf_clearance", value: "cf-ok", domain: ".nodeseek.com")
        let colorscheme = try makeCookie(name: "colorscheme", value: "dark", domain: ".nodeseek.com")

        for c in [aSession, aSmac, cfClearance, colorscheme] {
            env.urlStorage.setCookie(c)
            await env.webStore.setCookie(c)
        }

        let bSession = try makeCookie(name: "session", value: "b-sess", domain: "www.nodeseek.com")
        let bPjwt = try makeCookie(name: "pjwt", value: "b-jwt", domain: "www.nodeseek.com")

        await env.bridge.replaceAccountSessionCookies(with: [bSession, bPjwt])

        // 切换后再跑一次双向同步，验证 A 的旧 Cookie 不会从任何一边“复活”。
        await env.bridge.syncWebViewCookiesToURLSession()
        await env.bridge.syncURLSessionCookiesToWebView()

        let urlCookies = env.urlStorage.cookies ?? []
        let webCookies = await env.webStore.allCookies()

        #expect(urlCookies.first(where: { $0.name == "session" })?.value == "b-sess")
        #expect(urlCookies.first(where: { $0.name == "pjwt" })?.value == "b-jwt")
        #expect(urlCookies.contains(where: { $0.name == "smac" }) == false)
        #expect(urlCookies.first(where: { $0.name == "cf_clearance" })?.value == "cf-ok")
        #expect(urlCookies.first(where: { $0.name == "colorscheme" })?.value == "dark")

        #expect(webCookies.first(where: { $0.name == "session" })?.value == "b-sess")
        #expect(webCookies.first(where: { $0.name == "pjwt" })?.value == "b-jwt")
        #expect(webCookies.contains(where: { $0.name == "smac" }) == false)
        #expect(webCookies.first(where: { $0.name == "cf_clearance" })?.value == "cf-ok")
    }

    @Test func switchToAccountBacksUpAInvalidatesCachesSendsBothNotificationsAndAbortsOnVaultFailure() async throws {
        let env = try makeIsolatedEnvironment()
        let nc = NotificationCenter()
        var cacheClearCount = 0
        var hiddenInvalidatedCount = 0
        var rootResetCount = 0
        var didChangeCount = 0
        var loginCloseCount = 0

        let obs1 = nc.addObserver(forName: .nodeSeekAccountSessionDidChange, object: nil, queue: nil) { _ in
            didChangeCount += 1
        }
        let obs2 = nc.addObserver(forName: .nodeSeekLoginSessionDidClose, object: nil, queue: nil) { _ in
            loginCloseCount += 1
        }
        defer {
            nc.removeObserver(obs1)
            nc.removeObserver(obs2)
        }

        let accountA = SavedAccount(
            uid: 101,
            displayName: "Alpha",
            profileURL: URL(string: "https://www.nodeseek.com/space/101")!
        )
        let accountB = SavedAccount(
            uid: 202,
            displayName: "Beta",
            profileURL: URL(string: "https://www.nodeseek.com/space/202")!
        )
        env.vaultStore.upsert(accountA, setActive: true)
        env.vaultStore.upsert(accountB, setActive: false)
        await env.currentAccountStore.save(accountA.toAccountResponse())

        let aCookie = try makeCookie(name: "session", value: "alpha-fresh")
        let bCookie = try makeCookie(name: "session", value: "beta-token")
        env.urlStorage.setCookie(aCookie)
        await env.webStore.setCookie(aCookie)
        env.cookieVault.saveCookies([bCookie], forUID: 202)

        let coordinator = AccountSwitchCoordinator(
            vaultStore: env.vaultStore,
            cookieVault: env.cookieVault,
            cookieSession: env.cookieSession,
            currentAccountStore: env.currentAccountStore,
            clearSessionCaches: { cacheClearCount += 1 },
            invalidateHiddenWebViews: { hiddenInvalidatedCount += 1 },
            notificationCenter: nc
        )
        coordinator.registerRootResetHandler { completion in
            rootResetCount += 1
            completion(nil)
        }

        // Keychain 备份失败时必须中止切号，不破坏 A。
        env.cookieVault.shouldFailSave = true
        let failResult = await coordinator.switchToAccount(uid: 202)
        if case .failed = failResult {
            // expected
        } else {
            Issue.record("expected switch failure when saving A fails")
        }
        #expect(env.vaultStore.activeUID == 101)
        #expect(env.urlStorage.cookies?.first(where: { $0.name == "session" })?.value == "alpha-fresh")

        // 恢复 Keychain 后正常切到 B。
        env.cookieVault.shouldFailSave = false
        let okResult = await coordinator.switchToAccount(uid: 202)
        if case let .switched(target) = okResult {
            #expect(target.uid == 202)
        } else {
            Issue.record("expected switched to 202, got \(okResult)")
        }
        #expect(env.vaultStore.activeUID == 202)
        #expect(env.cookieVault.loadCookies(forUID: 101)?.first?.value == "alpha-fresh")
        #expect(env.urlStorage.cookies?.first(where: { $0.name == "session" })?.value == "beta-token")
        #expect(await env.currentAccountStore.snapshot()?.account.displayName == "Beta")
        #expect(cacheClearCount == 1)
        #expect(hiddenInvalidatedCount == 1)
        #expect(rootResetCount == 1)
        #expect(didChangeCount == 1)
        #expect(loginCloseCount == 1)
    }

    @Test func staleAdoptRequestCannotOverwriteAnotherAccountsKeychainSnapshot() async throws {
        let env = try makeIsolatedEnvironment()
        let accountA = SavedAccount(uid: 101, displayName: "A", profileURL: URL(string: "https://www.nodeseek.com/space/101")!)
        let accountB = SavedAccount(uid: 202, displayName: "B", profileURL: URL(string: "https://www.nodeseek.com/space/202")!)
        env.vaultStore.upsert(accountA, setActive: false)
        env.vaultStore.upsert(accountB, setActive: true)

        let aCookie = try makeCookie(name: "session", value: "a-original")
        let bCookie = try makeCookie(name: "session", value: "b-active")
        env.cookieVault.saveCookies([aCookie], forUID: 101)
        env.urlStorage.setCookie(bCookie)
        await env.webStore.setCookie(bCookie)

        let oldSessionID = await env.currentAccountStore.sessionID
        _ = await env.currentAccountStore.replaceSnapshot(accountB.toAccountResponse())

        let coordinator = AccountSwitchCoordinator(
            vaultStore: env.vaultStore,
            cookieVault: env.cookieVault,
            cookieSession: env.cookieSession,
            currentAccountStore: env.currentAccountStore,
            clearSessionCaches: {},
            invalidateHiddenWebViews: {}
        )

        // 迟到响应带旧 sessionID 或跨号 UID 均不能覆写 A 的 Keychain 快照。
        await coordinator.adoptCurrentSessionIfNeeded(account: accountA.toAccountResponse(), requestSessionID: oldSessionID)
        let currentSessionID = await env.currentAccountStore.sessionID
        await coordinator.adoptCurrentSessionIfNeeded(account: accountA.toAccountResponse(), requestSessionID: currentSessionID)

        #expect(env.cookieVault.loadCookies(forUID: 101)?.first?.value == "a-original")
    }

    @Test func confirmedLoggedOutMarksExpiredWithoutDeletingSnapshotOrActiveCookies() async throws {
        let env = try makeIsolatedEnvironment()
        let accountA = SavedAccount(uid: 101, displayName: "A", profileURL: URL(string: "https://www.nodeseek.com/space/101")!)
        env.vaultStore.upsert(accountA, setActive: true)
        let aCookie = try makeCookie(name: "session", value: "keep-me")
        env.cookieVault.saveCookies([aCookie], forUID: 101)
        env.urlStorage.setCookie(aCookie)
        await env.webStore.setCookie(aCookie)

        let sessionID = await env.currentAccountStore.replaceSnapshot(accountA.toAccountResponse())
        let coordinator = AccountSwitchCoordinator(
            vaultStore: env.vaultStore,
            cookieVault: env.cookieVault,
            cookieSession: env.cookieSession,
            currentAccountStore: env.currentAccountStore,
            clearSessionCaches: {},
            invalidateHiddenWebViews: {}
        )

        await coordinator.handleConfirmedLoggedOut(requestSessionID: sessionID)

        #expect(env.vaultStore.account(uid: 101)?.credentialState == .expired)
        #expect(env.cookieVault.loadCookies(forUID: 101)?.first?.value == "keep-me")
        #expect(env.urlStorage.cookies?.first(where: { $0.name == "session" })?.value == "keep-me")
    }

    @Test func launchPreparationCleansReinstallOrphansAndAdoptsLegacyAccountWithoutLogout() async throws {
        let env = try makeIsolatedEnvironment()
        // 模拟重装后残留的孤儿 Keychain。
        let orphanCookie = try makeCookie(name: "session", value: "orphan")
        env.cookieVault.saveCookies([orphanCookie], forUID: 999)

        // 模拟老版本升级已有的单账号快照与活跃 Cookie。
        let legacyAccount = AccountResponse(
            displayName: "LegacyUser",
            isLoggedIn: true,
            profileURL: URL(string: "https://www.nodeseek.com/space/777")
        )
        await env.currentAccountStore.save(legacyAccount)
        let legacyCookie = try makeCookie(name: "session", value: "legacy-live")
        env.urlStorage.setCookie(legacyCookie)
        await env.webStore.setCookie(legacyCookie)

        let coordinator = AccountSwitchCoordinator(
            vaultStore: env.vaultStore,
            cookieVault: env.cookieVault,
            cookieSession: env.cookieSession,
            currentAccountStore: env.currentAccountStore,
            clearSessionCaches: {},
            invalidateHiddenWebViews: {}
        )

        await coordinator.prepareAtLaunch()

        #expect(env.cookieVault.loadCookies(forUID: 999) == nil)
        #expect(env.vaultStore.activeUID == 777)
        #expect(env.vaultStore.account(uid: 777)?.displayName == "LegacyUser")
        #expect(env.cookieVault.loadCookies(forUID: 777)?.first?.value == "legacy-live")
        #expect(env.urlStorage.cookies?.first(where: { $0.name == "session" })?.value == "legacy-live")
    }

    @Test func logoutDeletesCurrentSnapshotPreservesOtherAccountsAndCloudflareCookies() async throws {
        let env = try makeIsolatedEnvironment()
        let accountA = SavedAccount(uid: 101, displayName: "A", profileURL: URL(string: "https://www.nodeseek.com/space/101")!)
        let accountB = SavedAccount(uid: 202, displayName: "B", profileURL: URL(string: "https://www.nodeseek.com/space/202")!)
        env.vaultStore.upsert(accountA, setActive: true)
        env.vaultStore.upsert(accountB, setActive: false)
        await env.currentAccountStore.save(accountA.toAccountResponse())

        let aCookie = try makeCookie(name: "session", value: "a-live")
        let bCookie = try makeCookie(name: "session", value: "b-saved")
        let cfCookie = try makeCookie(name: "cf_clearance", value: "cf-stay", domain: ".nodeseek.com")
        env.cookieVault.saveCookies([aCookie], forUID: 101)
        env.cookieVault.saveCookies([bCookie], forUID: 202)
        for c in [aCookie, cfCookie] {
            env.urlStorage.setCookie(c)
            await env.webStore.setCookie(c)
        }

        let coordinator = AccountSwitchCoordinator(
            vaultStore: env.vaultStore,
            cookieVault: env.cookieVault,
            cookieSession: env.cookieSession,
            currentAccountStore: env.currentAccountStore,
            clearSessionCaches: {},
            invalidateHiddenWebViews: {}
        )

        let outcome = await coordinator.logoutCurrentAccount()
        #expect(outcome.remainingAccountCount == 1)
        #expect(env.vaultStore.activeUID == nil)
        #expect(env.vaultStore.account(uid: 101) == nil)
        #expect(env.cookieVault.loadCookies(forUID: 101) == nil)
        #expect(env.cookieVault.loadCookies(forUID: 202)?.first?.value == "b-saved")
        #expect(await env.currentAccountStore.snapshot() == nil)
        #expect(env.urlStorage.cookies?.contains(where: { $0.name == "session" }) == false)
        #expect(env.urlStorage.cookies?.first(where: { $0.name == "cf_clearance" })?.value == "cf-stay")
    }

    @Test func autoCheckInRunsSequentiallyAcrossMultipleAccountsAndWritesRefreshedCookies() async throws {
        let suite = "multi-checkin-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settingsStore = AutoCheckInSettingsStore(userDefaults: defaults, storageKey: "settings")
        settingsStore.setEnabled(true)
        settingsStore.setCheckInAllAccounts(true)
        let stateStore = AutoCheckInStateStore(userDefaults: defaults, storageKey: "state")

        let automator = FakeMultiCheckInAutomator()
        let updatedBCookie = try makeCookie(name: "session", value: "b-rotated")
        automator.isolatedResults[202] = IsolatedAutoCheckInResult(
            outcome: .submitted(message: "签到成功 +5"),
            isLoggedOut: false,
            hitChallenge: false,
            updatedAccountCookies: [updatedBCookie]
        )
        automator.isolatedResults[303] = IsolatedAutoCheckInResult(
            outcome: .failed("unauthorized"),
            isLoggedOut: true,
            hitChallenge: false,
            updatedAccountCookies: []
        )

        let multiProvider = FakeMultiCheckInProvider(
            accounts: [
                SavedAccount(uid: 202, displayName: "Beta", profileURL: URL(string: "https://www.nodeseek.com/space/202")!),
                SavedAccount(uid: 303, displayName: "Gamma", profileURL: URL(string: "https://www.nodeseek.com/space/303")!),
            ],
            cookiesByUID: [
                202: [try makeCookie(name: "session", value: "b-old")],
                303: [try makeCookie(name: "session", value: "c-expired")],
            ]
        )
        let toastPresenter = FakeToastPresenter()
        let coordinator = AutoCheckInCoordinator(
            settingsStore: settingsStore,
            stateStore: stateStore,
            webAutomator: automator,
            accountStatus: FakeAccountStatusProvider(uid: 101, name: "Alpha"),
            multiAccountProvider: multiProvider,
            toastPresenter: toastPresenter,
            dayIdentifierProvider: { "2026-11-25" },
            triggerDelayInterval: 0,
            multiAccountDelayInterval: 0,
            delay: { _ in }
        )

        let outcome = await coordinator.runIfNeeded(presentationContext: UIViewController(), trigger: .postListAppear)
        if case .submitted = outcome {
            // expected
        } else {
            Issue.record("expected submitted outcome, got \(outcome)")
        }

        #expect(stateStore.isCompleted(forUID: 101, on: "2026-11-25") == true)
        #expect(stateStore.isCompleted(forUID: 202, on: "2026-11-25") == true)
        #expect(stateStore.isCompleted(forUID: 303, on: "2026-11-25") == false)
        #expect(multiProvider.updatedCookiesByUID[202]?.first?.value == "b-rotated")
        #expect(multiProvider.expiredUIDs == [303])
        #expect(toastPresenter.shownToasts.count == 1)
        #expect(toastPresenter.shownToasts.first?.message.contains("2") == true)
    }
}

@MainActor
private final class FakeAccountWebCookieStore: WebCookieStore {
    private var cookies: [HTTPCookie] = []

    func allCookies() async -> [HTTPCookie] { cookies }

    func setCookie(_ cookie: HTTPCookie) async {
        cookies.removeAll {
            $0.name == cookie.name && $0.domain == cookie.domain && $0.path == cookie.path
        }
        cookies.append(cookie)
    }

    func deleteCookie(_ cookie: HTTPCookie) async {
        cookies.removeAll {
            $0.name == cookie.name && $0.domain == cookie.domain && $0.path == cookie.path
        }
    }
}

@MainActor
private final class FakeAccountStatusProvider: AutoCheckInAccountStatusProviding {
    let uid: Int
    let name: String
    let sid = UUID()

    init(uid: Int, name: String) {
        self.uid = uid
        self.name = name
    }

    func isLoggedIn() async -> Bool? { true }
    func activeUID() async -> Int? { uid }
    func activeDisplayName() async -> String? { name }
    func sessionID() async -> UUID? { sid }
}

@MainActor
private final class FakeMultiCheckInProvider: AutoCheckInMultiAccountProviding {
    let accounts: [SavedAccount]
    let cookiesByUID: [Int: [HTTPCookie]]
    var updatedCookiesByUID: [Int: [HTTPCookie]] = [:]
    var expiredUIDs: [Int] = []

    init(accounts: [SavedAccount], cookiesByUID: [Int: [HTTPCookie]]) {
        self.accounts = accounts
        self.cookiesByUID = cookiesByUID
    }

    func otherValidAccounts(excluding activeUID: Int?) -> [SavedAccount] {
        accounts.filter { $0.uid != activeUID }
    }

    func cookies(forUID uid: Int) -> [HTTPCookie]? {
        cookiesByUID[uid]
    }

    func cloudflareCookies() async -> [HTTPCookie] { [] }

    func updateCookies(_ cookies: [HTTPCookie], forUID uid: Int) {
        updatedCookiesByUID[uid] = cookies
    }

    func markExpired(uid: Int) {
        expiredUIDs.append(uid)
    }
}

@MainActor
private final class FakeMultiCheckInAutomator: AutoCheckInWebAutomating {
    var isolatedResults: [Int: IsolatedAutoCheckInResult] = [:]

    func fetchBoardState(runID: String) async throws -> AutoCheckInBoardState {
        AutoCheckInBoardState(ok: true, isCheckedIn: false, message: nil, reason: "loaded", statusCode: 200, responseKeys: ["record"])
    }

    func submit(mode: AutoCheckInMode, runID: String) async throws -> AutoCheckInSubmitResult {
        AutoCheckInSubmitResult(ok: true, statusCode: 200, success: true, message: "鸡腿 +5", current: 105, reason: "submitted")
    }

    func runIsolatedCheckIn(
        accountCookies: [HTTPCookie],
        cloudflareCookies: [HTTPCookie],
        mode: AutoCheckInMode,
        runID: String
    ) async -> IsolatedAutoCheckInResult {
        for (uid, result) in isolatedResults where runID.contains("-u\(uid)") {
            return result
        }
        return IsolatedAutoCheckInResult(outcome: .alreadyCheckedIn, isLoggedOut: false, hitChallenge: false, updatedAccountCookies: [])
    }
}

@MainActor
private final class FakeToastPresenter: AutoCheckInToastPresenting {
    var shownToasts: [AutoCheckInToast] = []

    func show(_ toast: AutoCheckInToast, from presentationContext: UIViewController) -> Bool {
        shownToasts.append(toast)
        return true
    }
}
