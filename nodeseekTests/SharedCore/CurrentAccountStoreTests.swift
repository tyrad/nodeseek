//
//  CurrentAccountStoreTests.swift
//  nodeseekTests
//

import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import NodeSeekCore
#else
@testable import nodeseek
#endif

struct CurrentAccountStoreTests {
    @Test func persistsAccountSnapshotAndLoadsItBack() async throws {
        let defaults = try #require(UserDefaults(suiteName: "CurrentAccountStoreTests.persist"))
        defaults.removePersistentDomain(forName: "CurrentAccountStoreTests.persist")
        let account = AccountResponse(
            displayName: "缭雾",
            isLoggedIn: true,
            avatarURL: URL(string: "https://www.nodeseek.com/avatar/31037.png"),
            profileURL: URL(string: "https://www.nodeseek.com/space/31037"),
            stats: ["等级 Lv 1", "鸡腿 306"],
            notification: AccountNotification(
                url: try #require(URL(string: "https://www.nodeseek.com/notification")),
                iconColorCSS: "rgb(243, 17, 17)"
            )
        )
        let savedAt = Date(timeIntervalSince1970: 1_777_777_777)

        let store = CurrentAccountStore(
            userDefaults: defaults,
            storageKey: "persisted-account"
        )
        await store.save(account, updatedAt: savedAt)

        let reloaded = CurrentAccountStore(
            userDefaults: defaults,
            storageKey: "persisted-account"
        )
        let snapshot = await reloaded.snapshot()

        #expect(snapshot?.account == account)
        #expect(snapshot?.updatedAt == savedAt)
    }

    @Test func ignoresLegacySnapshotWithoutSchemaVersion() async throws {
        let defaults = try #require(UserDefaults(suiteName: "CurrentAccountStoreTests.legacy"))
        defaults.removePersistentDomain(forName: "CurrentAccountStoreTests.legacy")
        let legacyJSON = """
        {
          "displayName": "游客",
          "isLoggedIn": false,
          "avatarURL": null,
          "profileURL": null,
          "stats": [],
          "updatedAt": 1777777777
        }
        """
        let storageKey = "legacy-account"
        defaults.set(Data(legacyJSON.utf8), forKey: storageKey)

        let store = CurrentAccountStore(
            userDefaults: defaults,
            storageKey: storageKey
        )

        let snapshot = await store.snapshot()

        #expect(snapshot == nil)
    }

    @Test func refreshFrequencyUsesStoredUpdatedAt() async throws {
        let defaults = try #require(UserDefaults(suiteName: "CurrentAccountStoreTests.refresh-age"))
        defaults.removePersistentDomain(forName: "CurrentAccountStoreTests.refresh-age")
        let account = AccountResponse(displayName: "缭雾", isLoggedIn: true)
        let savedAt = Date(timeIntervalSince1970: 1_777_777_777)
        let store = CurrentAccountStore(
            userDefaults: defaults,
            storageKey: "refresh-age-account"
        )

        await store.save(account, updatedAt: savedAt)

        let stillFresh = await store.shouldRefresh(
            maxAge: 60,
            now: savedAt.addingTimeInterval(59)
        )
        let expired = await store.shouldRefresh(
            maxAge: 60,
            now: savedAt.addingTimeInterval(61)
        )

        #expect(stillFresh == false)
        #expect(expired == true)
    }
}
