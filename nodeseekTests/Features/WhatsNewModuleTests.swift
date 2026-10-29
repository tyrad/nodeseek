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

    @Test func returnsNilWhenCurrentVersionHasNoContent() {
        let whatsNew = WhatsNewModule.whatsNewToPresent(
            currentVersion: "1.0.11",
            versionStore: InMemoryWhatsNewVersionStore(),
            catalog: catalog
        )

        #expect(whatsNew == nil)
    }
}
