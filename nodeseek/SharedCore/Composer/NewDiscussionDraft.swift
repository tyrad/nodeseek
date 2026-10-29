//
//  NewDiscussionDraft.swift
//  nodeseek
//

import Foundation

/// 本机保存的单份发帖草稿。
nonisolated struct NewDiscussionDraft: Codable, Equatable, Sendable {
    var title: String
    var content: String
    var category: DiscussionCategory?
    var rank: DiscussionReadRank
    var updatedAt: Date

    init(
        title: String = "",
        content: String = "",
        category: DiscussionCategory? = nil,
        rank: DiscussionReadRank = .everyone,
        updatedAt: Date = Date()
    ) {
        self.title = title
        self.content = content
        self.category = category
        self.rank = rank
        self.updatedAt = updatedAt
    }

    /// 只看标题和正文：只改了板块或阅读限制不算有内容，不值得保存或提示恢复。
    var hasContent: Bool {
        !title.isBlank || !content.isBlank
    }

    func validatedSubmission() throws -> NewDiscussionSubmission {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw NewDiscussionValidationError.titleEmpty }
        guard let category else { throw NewDiscussionValidationError.categoryMissing }
        guard !content.isBlank else { throw NewDiscussionValidationError.contentEmpty }
        return NewDiscussionSubmission(
            title: trimmedTitle,
            content: content,
            category: category,
            rank: rank
        )
    }
}

nonisolated enum NewDiscussionValidationError: Error, Equatable, LocalizedError {
    case titleEmpty
    case categoryMissing
    case contentEmpty

    // 前两条沿用网页的提示文案。
    var errorDescription: String? {
        switch self {
        case .titleEmpty: return "标题不能为空"
        case .categoryMissing: return "请选择正确的板块"
        case .contentEmpty: return "正文不能为空"
        }
    }
}

/// `POST /api/content/new-discussion` 的请求体，字段与网页前端一致。
nonisolated struct NewDiscussionSubmission: Equatable, Sendable {
    static let mode = "new-discussion"

    let title: String
    let content: String
    let category: DiscussionCategory
    let rank: DiscussionReadRank

    var jsonObject: [String: Any] {
        [
            "content": content,
            "mode": Self.mode,
            "title": title,
            "category": category.rawValue,
            "rank": rank.rawValue
        ]
    }

    func jsonData() throws -> Data {
        try JSONSerialization.data(withJSONObject: jsonObject, options: [.sortedKeys])
    }
}

private extension String {
    nonisolated var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
