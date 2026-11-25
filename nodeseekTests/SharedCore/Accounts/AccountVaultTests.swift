//
//  AccountVaultTests.swift
//  nodeseekTests
//

import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import NodeSeekCore
#else
@testable import nodeseek
#endif

struct AccountVaultTests {
    private func makeStore() -> AccountVaultStore {
        let suite = "account-vault-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return AccountVaultStore(userDefaults: defaults)
    }

    private func makeAccount(
        uid: Int,
        name: String,
        lastUsedAt: Date = Date(),
        state: AccountCredentialState = .valid
    ) -> SavedAccount {
        SavedAccount(
            uid: uid,
            displayName: name,
            avatarURL: URL(string: "https://www.nodeseek.com/avatar/\(uid).png"),
            profileURL: URL(string: "https://www.nodeseek.com/space/\(uid)")!,
            stats: ["Lv 3", "鸡腿 100"],
            lastUsedAt: lastUsedAt,
            credentialState: state
        )
    }

    @Test func upsertSortsActiveFirstThenByLastUsedDescending() {
        let store = makeStore()
        #expect(store.isInitialized == false)

        let t1 = Date(timeIntervalSince1970: 100)
        let t2 = Date(timeIntervalSince1970: 200)
        let t3 = Date(timeIntervalSince1970: 300)

        store.upsert(makeAccount(uid: 10, name: "Alice", lastUsedAt: t1), setActive: true)
        store.upsert(makeAccount(uid: 20, name: "Bob", lastUsedAt: t3), setActive: false)
        store.upsert(makeAccount(uid: 30, name: "Carol", lastUsedAt: t2), setActive: false)

        #expect(store.isInitialized == true)
        #expect(store.activeUID == 10)
        #expect(store.accounts.map(\.uid) == [10, 20, 30])

        store.setActive(uid: 30, touchLastUsedAt: Date(timeIntervalSince1970: 400))
        #expect(store.activeUID == 30)
        #expect(store.accounts.map(\.uid) == [30, 20, 10])
    }

    @Test func upsertDeduplicatesByUIDAndPreservesExistingAvatarWhenNil() {
        let store = makeStore()
        let original = makeAccount(uid: 42, name: "OldName")
        store.upsert(original, setActive: true)

        let updated = SavedAccount(
            uid: 42,
            displayName: "NewName",
            avatarURL: nil,
            profileURL: URL(string: "https://www.nodeseek.com/space/42")!,
            stats: [],
            lastUsedAt: Date(timeIntervalSince1970: 500),
            credentialState: .valid
        )
        let saved = store.upsert(updated, setActive: true)

        #expect(store.accounts.count == 1)
        #expect(saved.displayName == "NewName")
        #expect(saved.avatarURL == original.avatarURL)
        #expect(saved.stats == original.stats)
    }

    @Test func markExpiredAndRemoveUpdateStateCorrectly() {
        let store = makeStore()
        let base = Date(timeIntervalSince1970: 1_000)
        store.upsert(makeAccount(uid: 1, name: "A", lastUsedAt: base), setActive: true)
        store.upsert(makeAccount(uid: 2, name: "B", lastUsedAt: base.addingTimeInterval(20)), setActive: false)
        store.upsert(makeAccount(uid: 3, name: "C", lastUsedAt: base.addingTimeInterval(10)), setActive: false)

        store.markCredentialState(.expired, for: 2)
        #expect(store.account(uid: 2)?.credentialState == .expired)
        #expect(store.otherValidAccounts(excluding: 1).map(\.uid) == [3])

        #expect(store.remove(uid: 1) == true)
        #expect(store.activeUID == nil)
        #expect(store.hasOtherAccounts(excluding: nil) == true)
        #expect(store.accounts.map(\.uid) == [2, 3])
    }

    @Test func pendingSwitchTargetUIDPersistsAndClears() {
        let store = makeStore()
        #expect(store.pendingSwitchTargetUID == nil)
        store.pendingSwitchTargetUID = 999
        #expect(store.pendingSwitchTargetUID == 999)
        store.pendingSwitchTargetUID = nil
        #expect(store.pendingSwitchTargetUID == nil)
    }

    @Test func cookieClassifierSeparatesAccountCloudflarePreferenceAndExternal() throws {
        func cookie(name: String, domain: String) throws -> HTTPCookie {
            try #require(HTTPCookie(properties: [
                .name: name,
                .value: "v",
                .domain: domain,
                .path: "/",
            ]))
        }

        let session = try cookie(name: "session", domain: "www.nodeseek.com")
        let pjwt = try cookie(name: "pjwt", domain: "www.nodeseek.com")
        let smac = try cookie(name: "smac", domain: "www.nodeseek.com")
        let cfClearance = try cookie(name: "cf_clearance", domain: ".nodeseek.com")
        let cfBm = try cookie(name: "__cf_bm", domain: ".nodeseek.com")
        let cfChl = try cookie(name: "cf_chl_rc_m", domain: ".nodeseek.com")
        let colorscheme = try cookie(name: "colorscheme", domain: ".nodeseek.com")
        let sortBy = try cookie(name: "sortBy", domain: "www.nodeseek.com")
        let hmti = try cookie(name: "hmti_", domain: "www.nodeseek.com")
        let external = try cookie(name: "session", domain: "example.com")

        let all = [session, pjwt, smac, cfClearance, cfBm, cfChl, colorscheme, sortBy, hmti, external]

        #expect(NodeSeekCookieClassifier.accountSessionCookies(from: all).map(\.name) == ["session", "pjwt", "smac"])
        #expect(NodeSeekCookieClassifier.cloudflareCookies(from: all).map(\.name) == ["cf_clearance", "__cf_bm", "cf_chl_rc_m"])
        #expect(NodeSeekCookieClassifier.classify(colorscheme) == .sitePreference)
        #expect(NodeSeekCookieClassifier.classify(sortBy) == .sitePreference)
        #expect(NodeSeekCookieClassifier.classify(hmti) == .sitePreference)
        #expect(NodeSeekCookieClassifier.classify(external) == .external)
    }

    @Test func currentAccountStoreRotateSessionIDRejectsStaleRequestSave() async {
        let suite = "current-account-rotate-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = CurrentAccountStore(userDefaults: defaults)

        let oldSessionID = await store.sessionID
        let newAccount = AccountResponse(
            displayName: "AccountB",
            isLoggedIn: true,
            profileURL: URL(string: "https://www.nodeseek.com/space/200")
        )
        let newSessionID = await store.replaceSnapshot(newAccount)
        #expect(oldSessionID != newSessionID)

        let staleAccount = AccountResponse(
            displayName: "AccountA",
            isLoggedIn: true,
            profileURL: URL(string: "https://www.nodeseek.com/space/100")
        )
        let savedStale = await store.save(staleAccount, for: oldSessionID)
        #expect(savedStale == false)
        #expect(await store.snapshot()?.account.displayName == "AccountB")
    }

    @Test func pushNotificationRouteParsesOptionalTargetAccountUID() {
        #expect(PushNotificationRoute.targetAccountUID(from: ["account_uid": 12345]) == 12345)
        #expect(PushNotificationRoute.targetAccountUID(from: ["uid": "67890"]) == 67890)
        #expect(PushNotificationRoute.targetAccountUID(from: ["member_id": "42"]) == 42)
        #expect(PushNotificationRoute.targetAccountUID(from: ["uid": "0"]) == nil)
        #expect(PushNotificationRoute.targetAccountUID(from: ["type": "reply"]) == nil)
    }
}
