//
//  HotListRepositoryTests.swift
//  nodeseekTests
//

import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import NodeSeekCore
#else
@testable import nodeseek
#endif

private final class HotListTestState: @unchecked Sendable {
    private let lock = NSLock()
    private var _now = Date(timeIntervalSince1970: 1_000_000)
    private var _requests: [URL] = []
    private var _fails = false

    var now: Date { lock.withLock { _now } }
    var requests: [URL] { lock.withLock { _requests } }
    func advance(_ seconds: TimeInterval) { lock.withLock { _now += seconds } }
    func setFails(_ fails: Bool) { lock.withLock { _fails = fails } }

    func load(_ url: URL) throws -> Data {
        try lock.withLock {
            _requests.append(url)
            if _fails { throw URLError(.notConnectedToInternet) }
        }
        return Data(#"{"updated_at": 1, "posts": [{"post": {"id": 7, "title": "热帖"}, "score": 1}]}"#.utf8)
    }
}

struct HotListRepositoryTests {
    private func makeSettings() -> HotListSourceSettings {
        let suite = "HotListRepositoryTests.\(UUID().uuidString)"
        return HotListSourceSettings(userDefaults: UserDefaults(suiteName: suite)!)
    }

    private func makeRepository(_ state: HotListTestState, settings: HotListSourceSettings) -> HotListRepository {
        HotListRepository(
            settings: settings,
            loader: { try state.load($0) },
            now: { state.now }
        )
    }

    @Test func reusesCacheWithinLifetimeAndRefetchesAfterExpiry() async throws {
        let state = HotListTestState()
        let repository = makeRepository(state, settings: makeSettings())

        _ = try await repository.load(.realtime)
        state.advance(59)
        _ = try await repository.load(.realtime)
        #expect(state.requests.count == 1)

        state.advance(2)
        _ = try await repository.load(.realtime)
        #expect(state.requests.count == 2)
    }

    @Test func pullToRefreshIsThrottledToMinimumInterval() async throws {
        let state = HotListTestState()
        let repository = makeRepository(state, settings: makeSettings())

        _ = try await repository.load(.weekly)
        state.advance(10)
        _ = try await repository.load(.weekly, userInitiated: true)
        #expect(state.requests.count == 1)

        state.advance(6)
        _ = try await repository.load(.weekly, userInitiated: true)
        #expect(state.requests.count == 2)
    }

    @Test func failureKeepsPreviousSnapshotCached() async throws {
        let state = HotListTestState()
        let repository = makeRepository(state, settings: makeSettings())

        let first = try await repository.load(.daily)
        state.advance(400)
        state.setFails(true)
        await #expect(throws: URLError.self) {
            try await repository.load(.daily)
        }
        #expect(await repository.cachedSnapshot(for: .daily) == first)
        #expect(await repository.lastAttemptFailed)
    }

    @Test func customURLIsUsedAndDoesNotHitOldCache() async throws {
        let state = HotListTestState()
        let settings = makeSettings()
        let repository = makeRepository(state, settings: settings)

        _ = try await repository.load(.realtime)
        let custom = URL(string: "https://example.com/hot.json")!
        settings.setURLs([.realtime: custom])
        #expect(await repository.cachedSnapshot(for: .realtime) == nil)
        _ = try await repository.load(.realtime)

        #expect(state.requests == [HotListKind.realtime.defaultURL, custom])
    }

    @Test func settingsStoreOnlyNonDefaultURLs() {
        let settings = makeSettings()
        settings.setURLs([.daily: HotListKind.daily.defaultURL])
        #expect(settings.isUsingDefaults)

        let custom = URL(string: "https://example.com/weekly.json")!
        settings.setURLs([.weekly: custom])
        #expect(settings.url(for: .weekly) == custom)
        #expect(!settings.isUsingDefaults)

        settings.resetToDefaults()
        #expect(settings.url(for: .weekly) == HotListKind.weekly.defaultURL)
    }

    @Test func kindOrderPersistsAndFillsMissingKinds() {
        let settings = makeSettings()
        #expect(settings.kindOrder == [.realtime, .daily, .weekly])

        settings.setKindOrder([.weekly, .realtime, .daily])
        #expect(settings.kindOrder == [.weekly, .realtime, .daily])

        settings.setKindOrder([.daily, .daily])
        #expect(settings.kindOrder == [.daily, .realtime, .weekly])

        // 恢复接口地址不影响顺序
        settings.resetToDefaults()
        #expect(settings.kindOrder.first == .daily)
    }

    @Test func validatesOnlyHTTPURLsWithHost() {
        #expect(HotListSourceSettings.validatedURL(from: " https://example.com/a.json ")?.absoluteString == "https://example.com/a.json")
        #expect(HotListSourceSettings.validatedURL(from: "ftp://example.com/a.json") == nil)
        #expect(HotListSourceSettings.validatedURL(from: "example.com/a.json") == nil)
        #expect(HotListSourceSettings.validatedURL(from: "") == nil)
    }
}
