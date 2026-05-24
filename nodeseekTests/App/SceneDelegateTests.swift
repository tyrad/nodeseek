//
//  SceneDelegateTests.swift
//  nodeseekTests
//

import Testing
@testable import nodeseek

@MainActor
struct SceneDelegateTests {
    @Test func sceneDelegateNoLongerOwnsAutoCheckInRunner() {
        let propertyNames = Set(Mirror(reflecting: SceneDelegate()).children.compactMap(\.label))

        #expect(propertyNames.contains("autoCheckInRunner") == false)
    }
}
