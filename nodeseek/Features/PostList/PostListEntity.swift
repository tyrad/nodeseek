//
//  PostListEntity.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation

enum PostListCategory: String, CaseIterable, Sendable {
    case all
    case daily
    case tech
    case info
    case review
    case trade
    case carpool
    case promotion
    case df
    case award

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
        case .df: return "DF"
        }
    }

    private var categoryPathComponent: String {
        switch self {
        case .df:
            // 站点顶部 DF 对应 dev 频道内容。
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

enum PostListSortMode: String, Sendable {
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
            return "按发帖时间排序"
        case .replyTime:
            return "按回复时间排序"
        }
    }

}

struct PostListRequest {
    let page: Int
    let category: PostListCategory
    let sortMode: PostListSortMode
}

struct PostListResponse {
    let posts: [PostSummary]
}
