//
//  SceneDelegateTests.swift
//  nodeseekTests
//

import Testing
import UIKit
@testable import nodeseek

@MainActor
struct SceneDelegateTests {
    @Test func autoCheckInSkipsSplashRootAndRunsAfterMainRootIsInstalled() async throws {
        let delegate = SceneDelegate()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let capturedContexts = AutoCheckInPresentationContexts()
        delegate.window = window
        delegate.autoCheckInRunner = { context in
            capturedContexts.append(context)
        }
        window.rootViewController = NodeSeekSplashViewController(
            reduceMotion: true,
            prewarmWebView: {},
            onFinish: {}
        )
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
        }

        delegate.runAutoCheckInIfNeeded()
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(capturedContexts.values.isEmpty)

        let mainRoot = UIViewController()
        window.rootViewController = mainRoot
        delegate.runAutoCheckInIfNeeded()
        try await waitUntil {
            capturedContexts.values.count == 1
        }

        let capturedContext = try #require(capturedContexts.values.first ?? nil)
        #expect(capturedContext === mainRoot)
    }
}

@MainActor
private final class AutoCheckInPresentationContexts {
    private(set) var values: [UIViewController?] = []

    func append(_ value: UIViewController?) {
        values.append(value)
    }
}

@MainActor
private func waitUntil(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    condition: @escaping @MainActor () -> Bool
) async throws {
    let step: UInt64 = 25_000_000
    var waited: UInt64 = 0
    while waited < timeoutNanoseconds {
        if condition() {
            return
        }
        try await Task.sleep(nanoseconds: step)
        waited += step
    }
}
