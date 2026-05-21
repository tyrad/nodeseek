//
//  PostCategoryPreferences.swift
//  nodeseek
//

import Foundation

struct PostCategoryPreferences: Codable, Equatable {
    var orderedVisibleCategoryItems: [PostListCategoryItem]
    var hiddenCategoryItems: [PostListCategoryItem]

    var orderedVisibleCategories: [PostListCategory] {
        orderedVisibleCategoryItems.compactMap(\.builtInCategory)
    }

    var hiddenCategories: [PostListCategory] {
        hiddenCategoryItems.compactMap(\.builtInCategory)
    }

    init(
        orderedVisibleCategories: [PostListCategory],
        hiddenCategories: [PostListCategory]
    ) {
        orderedVisibleCategoryItems = orderedVisibleCategories.map(PostListCategoryItem.builtin)
        hiddenCategoryItems = hiddenCategories.map(PostListCategoryItem.builtin)
    }

    init(
        orderedVisibleCategoryItems: [PostListCategoryItem],
        hiddenCategoryItems: [PostListCategoryItem]
    ) {
        self.orderedVisibleCategoryItems = orderedVisibleCategoryItems
        self.hiddenCategoryItems = hiddenCategoryItems
    }

    private enum CodingKeys: String, CodingKey {
        case orderedVisibleCategories
        case hiddenCategories
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let visibleItems = try container.decodeIfPresent(
            [LossyPostListCategoryItem].self,
            forKey: .orderedVisibleCategories
        ) ?? []
        let hiddenItems = try container.decodeIfPresent(
            [LossyPostListCategoryItem].self,
            forKey: .hiddenCategories
        ) ?? []
        orderedVisibleCategoryItems = visibleItems.compactMap(\.value)
        hiddenCategoryItems = hiddenItems.compactMap(\.value)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(orderedVisibleCategoryItems, forKey: .orderedVisibleCategories)
        try container.encode(hiddenCategoryItems, forKey: .hiddenCategories)
    }

    private struct LossyPostListCategoryItem: Decodable {
        let value: PostListCategoryItem?

        init(from decoder: Decoder) throws {
            value = try? PostListCategoryItem(from: decoder)
        }
    }
}

final class PostCategoryPreferenceStore {
    static let didChangeNotification = Notification.Name("PostCategoryPreferenceStore.didChange")
    static let shared = PostCategoryPreferenceStore()

    private let userDefaults: UserDefaults
    private let storageKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "postCategoryPreferences.v1"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    var visibleCategories: [PostListCategory] {
        visibleCategoryItems.compactMap(\.builtInCategory)
    }

    var hiddenCategories: [PostListCategory] {
        hiddenCategoryItems.compactMap(\.builtInCategory)
    }

    var visibleCategoryItems: [PostListCategoryItem] {
        preferences.orderedVisibleCategoryItems
    }

    var hiddenCategoryItems: [PostListCategoryItem] {
        preferences.hiddenCategoryItems
    }

    var preferences: PostCategoryPreferences {
        normalizedPreferences(from: storedPreferences())
    }

    func moveVisibleCategory(from sourceIndex: Int, to destinationIndex: Int) {
        var next = preferences
        guard next.orderedVisibleCategoryItems.indices.contains(sourceIndex) else { return }
        guard sourceIndex > 0 else { return }

        let current = next
        let category = next.orderedVisibleCategoryItems.remove(at: sourceIndex)
        let clampedDestination = max(1, min(destinationIndex, next.orderedVisibleCategoryItems.count))
        next.orderedVisibleCategoryItems.insert(category, at: clampedDestination)
        let normalized = normalizedPreferences(from: next)
        guard normalized != current else { return }
        persist(normalized)
    }

    func hideCategory(_ category: PostListCategoryItem) {
        guard !category.isAll else { return }
        var next = preferences
        guard let index = next.orderedVisibleCategoryItems.firstIndex(of: category) else { return }

        next.orderedVisibleCategoryItems.remove(at: index)
        if !next.hiddenCategoryItems.contains(category) {
            next.hiddenCategoryItems.append(category)
        }
        persist(normalizedPreferences(from: next))
    }

    func showCategory(_ category: PostListCategoryItem) {
        guard !category.isAll else { return }
        var next = preferences
        let current = next
        next.hiddenCategoryItems.removeAll { $0 == category }
        if !next.orderedVisibleCategoryItems.contains(category) {
            next.orderedVisibleCategoryItems.append(category)
        }
        let normalized = normalizedPreferences(from: next)
        guard normalized != current else { return }
        persist(normalized)
    }

    func resetToDefault() {
        let defaultPreferences = defaultPreferences()
        guard preferences != defaultPreferences else { return }
        persist(defaultPreferences)
    }

    private func storedPreferences() -> PostCategoryPreferences? {
        guard let data = userDefaults.data(forKey: storageKey) else { return nil }
        return try? decoder.decode(PostCategoryPreferences.self, from: data)
    }

    private func normalizedPreferences(from stored: PostCategoryPreferences?) -> PostCategoryPreferences {
        guard let stored else {
            return defaultPreferences()
        }

        var usedCodeValues = PostListCategoryItem.all.duplicateCodeValues
        var visible: [PostListCategoryItem] = [.all]
        var hidden: [PostListCategoryItem] = []

        for category in stored.orderedVisibleCategoryItems {
            appendNormalizedCategory(
                category,
                to: &visible,
                usedCodeValues: &usedCodeValues
            )
        }

        for category in stored.hiddenCategoryItems {
            appendNormalizedCategory(
                category,
                to: &hidden,
                usedCodeValues: &usedCodeValues
            )
        }

        let configuredCategories = Set((visible + hidden).compactMap(\.builtInCategory))
        for category in PostListCategory.allCases {
            guard category != .all else { continue }
            guard !configuredCategories.contains(category) else { continue }
            appendNormalizedCategory(
                .builtin(category),
                to: &visible,
                usedCodeValues: &usedCodeValues
            )
        }

        return PostCategoryPreferences(
            orderedVisibleCategoryItems: visible,
            hiddenCategoryItems: hidden
        )
    }

    private func defaultPreferences() -> PostCategoryPreferences {
        PostCategoryPreferences(
            orderedVisibleCategoryItems: PostListCategory.allCases.map(PostListCategoryItem.builtin),
            hiddenCategoryItems: []
        )
    }

    private func appendNormalizedCategory(
        _ category: PostListCategoryItem,
        to categories: inout [PostListCategoryItem],
        usedCodeValues: inout Set<String>
    ) {
        guard let builtInCategory = category.builtInCategory else { return }
        let normalized = PostListCategoryItem.builtin(builtInCategory)
        guard !normalized.isAll else { return }
        guard normalized.duplicateCodeValues.isDisjoint(with: usedCodeValues) else { return }
        categories.append(normalized)
        usedCodeValues.formUnion(normalized.duplicateCodeValues)
    }

    private func persist(_ preferences: PostCategoryPreferences) {
        guard let data = try? encoder.encode(preferences) else { return }
        userDefaults.set(data, forKey: storageKey)
        let postNotification = {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
        if Thread.isMainThread {
            postNotification()
        } else {
            DispatchQueue.main.async(execute: postNotification)
        }
    }
}
