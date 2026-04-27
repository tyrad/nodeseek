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

    var title: String {
        switch self {
        case .all: return "全部"
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

    var pathComponent: String? {
        switch self {
        case .all:
            return nil
        case .df:
            // 站点顶部 DF 对应 dev 频道内容。
            return "dev"
        default:
            return rawValue
        }
    }
}

struct PostListRequest {
    let page: Int
    let category: PostListCategory
}

struct PostListResponse {
    let posts: [PostSummary]
}
