//
//  SearchHistoryStore.swift
//  nodeseek
//
//  Created by Codex on 2026/5/3.
//

import Foundation

/// 搜索范围，对应网页搜索弹窗的「帖子 / 用户 / 谷歌」三个 Tab。
enum SearchScope: String, Codable, CaseIterable, Sendable {
    case post
    case user
    case google

    var title: String {
        switch self {
        case .post: return "帖子"
        case .user: return "用户"
        case .google: return "谷歌"
        }
    }
}

struct SearchHistoryRecord: Codable, Equatable, Sendable {
    let query: String
    let category: PostListCategory
    let scope: SearchScope

    init(query: String, category: PostListCategory, scope: SearchScope = .post) {
        self.query = query
        // 分类只对帖子搜索有意义，其他范围统一记成全部，便于去重
        self.category = scope == .post ? category : .all
        self.scope = scope
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // 旧版本记录没有 scope 字段，全部视为帖子搜索
        self.init(
            query: try container.decode(String.self, forKey: .query),
            category: try container.decode(PostListCategory.self, forKey: .category),
            scope: try container.decodeIfPresent(SearchScope.self, forKey: .scope) ?? .post
        )
    }

    /// 历史标签右侧的小标签：帖子显示分类，其他显示搜索范围；帖子「全部」不再标注，减少重复信息
    var tagTitle: String? {
        guard scope == .post else { return scope.title }
        return category == .all ? nil : category.title
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

    func record(query: String, category: PostListCategory, scope: SearchScope = .post) {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return }

        let newRecord = SearchHistoryRecord(query: normalizedQuery, category: category, scope: scope)
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
