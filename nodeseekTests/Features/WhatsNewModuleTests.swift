//
//  WhatsNewModuleTests.swift
//  nodeseekTests
//

import Testing
import WhatsNewKit
@testable import nodeseek

@MainActor
struct WhatsNewModuleTests {
    private let catalog = [
        WhatsNewModule.release("1.0.10", features: [])
    ]

    @Test func returnsWhatsNewWhenCurrentVersionNotPresented() {
        let store = InMemoryWhatsNewVersionStore()

        let whatsNew = WhatsNewModule.whatsNewToPresent(
            currentVersion: "1.0.10",
            versionStore: store,
            catalog: catalog
        )

        #expect(whatsNew?.version == "1.0.10")
    }

    @Test func returnsNilWhenCurrentVersionAlreadyPresented() {
        let store = InMemoryWhatsNewVersionStore()
        store.save(presentedVersion: "1.0.10")

        let whatsNew = WhatsNewModule.whatsNewToPresent(
            currentVersion: "1.0.10",
            versionStore: store,
            catalog: catalog
        )

        #expect(whatsNew == nil)
    }

    @Test func patchVersionWithoutEntryFallsBackToLatestEarlierRelease() {
        let catalog = [
            WhatsNewModule.release("1.2.0", features: []),
            WhatsNewModule.release("1.1.0", features: [])
        ]

        let whatsNew = WhatsNewModule.whatsNewToPresent(
            currentVersion: "1.2.1",
            versionStore: InMemoryWhatsNewVersionStore(),
            catalog: catalog
        )

        #expect(whatsNew?.version == "1.2.0")
    }

    @Test func patchVersionDoesNotRepeatAlreadyPresentedRelease() {
        let store = InMemoryWhatsNewVersionStore()
        store.save(presentedVersion: "1.0.10")

        let whatsNew = WhatsNewModule.whatsNewToPresent(
            currentVersion: "1.0.11",
            versionStore: store,
            catalog: catalog
        )

        #expect(whatsNew == nil)
    }

    @Test func returnsNilWhenCurrentVersionIsOlderThanAllReleases() {
        let whatsNew = WhatsNewModule.whatsNewToPresent(
            currentVersion: "1.0.9",
            versionStore: InMemoryWhatsNewVersionStore(),
            catalog: catalog
        )

        #expect(whatsNew == nil)
    }
}
