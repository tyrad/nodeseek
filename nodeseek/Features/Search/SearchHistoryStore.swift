//
//  SearchHistoryStore.swift
//  nodeseek
//
//  Created by Codex on 2026/5/3.
//

import Foundation

struct SearchHistoryRecord: Codable, Equatable, Sendable {
    let query: String
    let category: PostListCategory

    var displayTitle: String {
        switch category {
        case .all:
            return query
        default:
            return "\(category.title) · \(query)"
        }
    }
}

final class SearchHistoryStore {
    private let userDefaults: UserDefaults
    private let storageKey: String
    private let limit: Int

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "search.history.records",
        limit: Int = 10
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        self.limit = limit
    }

    func records() -> [SearchHistoryRecord] {
        guard let data = userDefaults.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([SearchHistoryRecord].self, from: data)) ?? []
    }

    func record(query: String, category: PostListCategory) {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return }

        let newRecord = SearchHistoryRecord(query: normalizedQuery, category: category)
        var nextRecords = records().filter { existing in
            existing != newRecord
        }
        nextRecords.insert(newRecord, at: 0)
        save(Array(nextRecords.prefix(limit)))
    }

    func clear() {
        userDefaults.removeObject(forKey: storageKey)
    }

    private func save(_ records: [SearchHistoryRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        userDefaults.set(data, forKey: storageKey)
    }
}
