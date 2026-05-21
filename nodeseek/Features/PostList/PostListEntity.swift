//
//  PostListEntity.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation

nonisolated enum PostListCategory: String, CaseIterable, Codable, Sendable {
    case all
    case daily
    case tech
    case info
    case review
    case trade
    case carpool
    case promotion
    case life
    case dev
    case photoShare = "photo-share"
    case expose
    case inside
    case meaningless
    case sandbox
    case df
    case award

    static let allCases: [PostListCategory] = [
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
    ]

    var title: String {
        switch self {
        case .all: return "全部"
        case .award: return "推荐阅读"
        case .daily: return "日常"
        case .tech: return "技术"
        case .info: return "情报"
        case .review: return "测评"
        case .trade: return "交易"
        case .carpool: return "拼车"
        case .promotion: return "推广"
        case .life: return "生活"
        case .dev: return "Dev"
        case .photoShare: return "贴图"
        case .expose: return "曝光"
        case .inside: return "内版"
        case .meaningless: return "无意义"
        case .sandbox: return "沙盒"
        case .df: return "Dev"
        }
    }

    var categoryPathComponent: String {
        switch self {
        case .df:
            // 站点顶部 DF 对应 dev 频道内容。
            return "dev"
        default:
            return rawValue
        }
    }

    var searchQueryValue: String? {
        switch self {
        case .all:
            return nil
        case .df, .dev:
            return "dev"
        default:
            return rawValue
        }
    }

    func pathComponents(page: Int) -> [String] {
        let normalized = max(1, page)
        switch self {
        case .all:
            return ["page-\(normalized)"]
        case .award:
            return [categoryPathComponent, "page-\(normalized)"]
        default:
            guard normalized > 1 else { return ["categories", categoryPathComponent] }
            return ["categories", categoryPathComponent, "page-\(normalized)"]
        }
    }
}

nonisolated struct PostListCategoryItem: Hashable, Codable, Sendable {
    private let category: PostListCategory

    private init(category: PostListCategory) {
        self.category = category == .df ? .dev : category
    }

    static var all: PostListCategoryItem { .builtin(.all) }
    static var daily: PostListCategoryItem { .builtin(.daily) }
    static var tech: PostListCategoryItem { .builtin(.tech) }
    static var info: PostListCategoryItem { .builtin(.info) }
    static var review: PostListCategoryItem { .builtin(.review) }
    static var trade: PostListCategoryItem { .builtin(.trade) }
    static var carpool: PostListCategoryItem { .builtin(.carpool) }
    static var promotion: PostListCategoryItem { .builtin(.promotion) }
    static var life: PostListCategoryItem { .builtin(.life) }
    static var dev: PostListCategoryItem { .builtin(.dev) }
    static var photoShare: PostListCategoryItem { .builtin(.photoShare) }
    static var expose: PostListCategoryItem { .builtin(.expose) }
    static var inside: PostListCategoryItem { .builtin(.inside) }
    static var meaningless: PostListCategoryItem { .builtin(.meaningless) }
    static var sandbox: PostListCategoryItem { .builtin(.sandbox) }
    static var df: PostListCategoryItem { .builtin(.df) }
    static var award: PostListCategoryItem { .builtin(.award) }

    static func builtin(_ category: PostListCategory) -> PostListCategoryItem {
        PostListCategoryItem(category: category)
    }

    var builtInCategory: PostListCategory? {
        category
    }

    var isAll: Bool {
        category == .all
    }

    var title: String {
        category.title
    }

    var code: String {
        category.categoryPathComponent
    }

    var rawValue: String {
        category.rawValue
    }

    var searchQueryValue: String? {
        category.searchQueryValue
    }

    var duplicateCodeValues: Set<String> {
        Set(
            [category.rawValue, category.categoryPathComponent, category.searchQueryValue]
                .compactMap { $0?.lowercased() }
        )
    }

    func pathComponents(page: Int) -> [String] {
        category.pathComponents(page: page)
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case code
    }

    init(from decoder: Decoder) throws {
        if let rawValue = try? decoder.singleValueContainer().decode(String.self),
           let category = PostListCategory(rawValue: rawValue) {
            self = .builtin(category)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decodeIfPresent(String.self, forKey: .kind)
        guard kind == nil || kind == "builtin" else {
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unsupported category kind")
        }
        let code = try container.decode(String.self, forKey: .code)
        guard let category = PostListCategory(rawValue: code) else {
            throw DecodingError.dataCorruptedError(forKey: .code, in: container, debugDescription: "Unknown built-in category")
        }
        self = .builtin(category)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(category.rawValue)
    }
}

nonisolated enum PostListSortMode: String, Sendable {
    case postTime
    case replyTime

    var toggled: PostListSortMode {
        switch self {
        case .postTime:
            return .replyTime
        case .replyTime:
            return .postTime
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .postTime:
            return "发帖时间优先"
        case .replyTime:
            return "回复时间优先"
        }
    }

}

nonisolated struct PostListRequest {
    let page: Int
    let category: PostListCategoryItem
    let sortMode: PostListSortMode
}

nonisolated struct PostListResponse {
    let posts: [PostSummary]
}
