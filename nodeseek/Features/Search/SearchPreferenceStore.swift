//
//  SearchPreferenceStore.swift
//  nodeseek
//
//  Created by Codex on 2026/5/3.
//

import Foundation

final class SearchPreferenceStore {
    private let userDefaults: UserDefaults
    private let categoryStorageKey: String

    init(
        userDefaults: UserDefaults = .standard,
        categoryStorageKey: String = "search.selected.category"
    ) {
        self.userDefaults = userDefaults
        self.categoryStorageKey = categoryStorageKey
    }

    func category() -> PostListCategory {
        guard let rawValue = userDefaults.string(forKey: categoryStorageKey),
              let category = PostListCategory(rawValue: rawValue) else {
            return .all
        }
        return category
    }

    func rememberCategory(_ category: PostListCategory) {
        userDefaults.set(category.rawValue, forKey: categoryStorageKey)
    }
}
