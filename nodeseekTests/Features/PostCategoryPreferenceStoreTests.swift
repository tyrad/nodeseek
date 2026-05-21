//
//  PostCategoryPreferenceStoreTests.swift
//  nodeseekTests
//

import Foundation
import Testing
@testable import nodeseek

@MainActor
struct PostCategoryPreferenceStoreTests {
    @Test func defaultPreferencesShowAllCategoriesInDefaultOrder() throws {
        let store = makeStore()

        #expect(store.visibleCategories == PostListCategory.allCases)
        #expect(store.hiddenCategories.isEmpty)
    }

    @Test func defaultPreferencesFollowNodeSeekSidebarCategoryOrder() throws {
        let store = makeStore()

        #expect(store.visibleCategories == [
            .all,
            .daily,
            .tech,
            .info,
            .review,
            .trade,
            .carpool,
            .promotion,
            .life,
            .dev,
            .photoShare,
            .expose,
            .inside,
            .meaningless,
            .sandbox,
            .award
        ])
    }

    @Test func hidingAndShowingCategoryKeepsAllVisibleAndFixedFirst() throws {
        let store = makeStore()

        store.hideCategory(.all)
        #expect(store.visibleCategories.first == .all)
        #expect(store.hiddenCategories.contains(.all) == false)

        store.hideCategory(.tech)
        #expect(store.visibleCategories.first == .all)
        #expect(store.visibleCategories.contains(.tech) == false)
        #expect(store.hiddenCategories == [.tech])

        store.showCategory(.tech)
        #expect(store.visibleCategories.first == .all)
        #expect(store.visibleCategories.last == .tech)
        #expect(store.hiddenCategories.isEmpty)
    }

    @Test func movingVisibleCategoryCannotMoveAnythingBeforeAll() throws {
        let store = makeStore()

        store.moveVisibleCategory(from: 2, to: 0)

        #expect(Array(store.visibleCategories.prefix(3)) == [.all, .tech, .daily])
    }

    @Test func storedPreferencesNormalizeDuplicatesUnknownValuesAndHiddenOverlap() throws {
        let suiteName = "post-category-preferences-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let storageKey = "categories"
        let rawJSON = """
        {
          "orderedVisibleCategories": ["trade", "all", "removed", "trade"],
          "hiddenCategories": ["all", "tech", "removed", "trade"]
        }
        """.data(using: .utf8)!
        defaults.set(rawJSON, forKey: storageKey)

        let store = PostCategoryPreferenceStore(userDefaults: defaults, storageKey: storageKey)

        #expect(Array(store.visibleCategories.prefix(2)) == [.all, .trade])
        #expect(store.hiddenCategories == [.tech])
        #expect(store.visibleCategories.contains(.daily))
        #expect(store.visibleCategories.contains(.tech) == false)
    }

    @Test func storedPreferencesIgnoreCustomCategories() throws {
        let suiteName = "post-category-preferences-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let storageKey = "categories"
        let rawJSON = """
        {
          "orderedVisibleCategories": [
            "all",
            { "kind": "custom", "title": "生活", "code": "life" },
            { "kind": "custom", "title": "重复内置", "code": "daily" },
            { "kind": "custom", "title": "重复自定义", "code": "life" },
            { "kind": "custom", "title": "非法", "code": "bad/path" }
          ],
          "hiddenCategories": [
            { "kind": "custom", "title": "技术副本", "code": "tech" },
            { "kind": "custom", "title": "贴图", "code": "photo-share" }
          ]
        }
        """.data(using: .utf8)!
        defaults.set(rawJSON, forKey: storageKey)

        let store = PostCategoryPreferenceStore(userDefaults: defaults, storageKey: storageKey)

        #expect(store.visibleCategoryItems == PostListCategory.allCases.map(PostListCategoryItem.builtin))
        #expect(store.hiddenCategoryItems.isEmpty)
    }

    @Test func mutationPersistsPreferencesAndPostsDidChangeNotification() async throws {
        let suiteName = "post-category-preferences-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let storageKey = "categories"
        let store = PostCategoryPreferenceStore(userDefaults: defaults, storageKey: storageKey)
        let notificationCounter = NotificationCounter()
        let observer = NotificationCenter.default.addObserver(
            forName: PostCategoryPreferenceStore.didChangeNotification,
            object: store,
            queue: nil
        ) { _ in
            notificationCounter.increment()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        store.hideCategory(.tech)

        await waitForNotificationCount(1, in: notificationCounter)
        let data = try #require(defaults.data(forKey: storageKey))
        let reloadedStore = PostCategoryPreferenceStore(userDefaults: defaults, storageKey: storageKey)
        #expect(reloadedStore.hiddenCategories == [.tech])
        #expect(reloadedStore.visibleCategories.contains(.tech) == false)
        #expect(data.isEmpty == false)
        #expect(notificationCounter.value == 1)
    }

    @Test func encodedPreferencesUseCategoryRawStringValues() throws {
        let suiteName = "post-category-preferences-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let storageKey = "categories"
        let store = PostCategoryPreferenceStore(userDefaults: defaults, storageKey: storageKey)

        store.hideCategory(.tech)

        let data = try #require(defaults.data(forKey: storageKey))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: [String]])
        #expect(json["hiddenCategories"] == ["tech"])
        #expect(json["orderedVisibleCategories"]?.first == "all")
        #expect(json["orderedVisibleCategories"]?.contains("tech") == false)
    }

    @Test func defaultStorageKeyWritesToPostCategoryPreferencesV1() throws {
        let suiteName = "post-category-preferences-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PostCategoryPreferenceStore(userDefaults: defaults)

        store.hideCategory(.tech)

        #expect(defaults.data(forKey: "postCategoryPreferences.v1") != nil)
    }

    @Test func noOpMoveDoesNotPersistOrPostNotification() throws {
        let suiteName = "post-category-preferences-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let storageKey = "categories"
        let store = PostCategoryPreferenceStore(userDefaults: defaults, storageKey: storageKey)
        let notificationCounter = NotificationCounter()
        let observer = NotificationCenter.default.addObserver(
            forName: PostCategoryPreferenceStore.didChangeNotification,
            object: store,
            queue: nil
        ) { _ in
            notificationCounter.increment()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        store.moveVisibleCategory(from: 1, to: 0)

        #expect(store.visibleCategories == PostListCategory.allCases)
        #expect(defaults.data(forKey: storageKey) == nil)
        #expect(notificationCounter.value == 0)
    }

    @Test func noOpShowDoesNotPersistOrPostNotification() throws {
        let suiteName = "post-category-preferences-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let storageKey = "categories"
        let store = PostCategoryPreferenceStore(userDefaults: defaults, storageKey: storageKey)
        let notificationCounter = NotificationCounter()
        let observer = NotificationCenter.default.addObserver(
            forName: PostCategoryPreferenceStore.didChangeNotification,
            object: store,
            queue: nil
        ) { _ in
            notificationCounter.increment()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        store.showCategory(.tech)

        #expect(store.visibleCategories == PostListCategory.allCases)
        #expect(defaults.data(forKey: storageKey) == nil)
        #expect(notificationCounter.value == 0)
    }

    @Test func invalidStoredDataFallsBackToDefaultPreferences() throws {
        let suiteName = "post-category-preferences-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let storageKey = "categories"
        defaults.set(Data("not-json".utf8), forKey: storageKey)

        let store = PostCategoryPreferenceStore(userDefaults: defaults, storageKey: storageKey)

        #expect(store.visibleCategories == PostListCategory.allCases)
        #expect(store.hiddenCategories.isEmpty)
    }

    @Test func resetToDefaultDoesNotPersistOrPostNotificationWhenAlreadyDefault() async throws {
        let suiteName = "post-category-preferences-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let storageKey = "categories"
        let store = PostCategoryPreferenceStore(userDefaults: defaults, storageKey: storageKey)
        let notificationCounter = NotificationCounter()
        let observer = NotificationCenter.default.addObserver(
            forName: PostCategoryPreferenceStore.didChangeNotification,
            object: store,
            queue: nil
        ) { _ in
            notificationCounter.increment()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        store.resetToDefault()

        await Task.yield()
        #expect(defaults.data(forKey: storageKey) == nil)
        #expect(notificationCounter.value == 0)
    }

    @Test func resetToDefaultFromNonDefaultPersistsAndPostsNotification() async throws {
        let suiteName = "post-category-preferences-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let storageKey = "categories"
        let store = PostCategoryPreferenceStore(userDefaults: defaults, storageKey: storageKey)
        store.hideCategory(.tech)
        let notificationCounter = NotificationCounter()
        let observer = NotificationCenter.default.addObserver(
            forName: PostCategoryPreferenceStore.didChangeNotification,
            object: store,
            queue: nil
        ) { _ in
            notificationCounter.increment()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        store.resetToDefault()

        await waitForNotificationCount(1, in: notificationCounter)
        let reloadedStore = PostCategoryPreferenceStore(userDefaults: defaults, storageKey: storageKey)
        #expect(reloadedStore.visibleCategories == PostListCategory.allCases)
        #expect(reloadedStore.hiddenCategories.isEmpty)
        #expect(defaults.data(forKey: storageKey) != nil)
        #expect(notificationCounter.value == 1)
    }

    @Test func resetRestoresDefaultOrderAndVisibility() throws {
        let store = makeStore()
        store.hideCategory(.tech)
        store.moveVisibleCategory(from: 3, to: 1)

        store.resetToDefault()

        #expect(store.visibleCategories == PostListCategory.allCases)
        #expect(store.hiddenCategories.isEmpty)
    }
}

private func makeStore() -> PostCategoryPreferenceStore {
    let suiteName = "post-category-preferences-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return PostCategoryPreferenceStore(userDefaults: defaults, storageKey: "categories")
}

private final class NotificationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock {
            count += 1
        }
    }
}

private func waitForNotificationCount(
    _ expectedCount: Int,
    in counter: NotificationCounter
) async {
    for _ in 0..<20 where counter.value < expectedCount {
        await Task.yield()
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}
