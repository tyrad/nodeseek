//
//  NewDiscussionSettings.swift
//  nodeseek
//

import Foundation

/// 发帖页可选的板块，rawValue 与网页 `select#category` 的 option value 一致。
nonisolated enum DiscussionCategory: String, CaseIterable, Codable, Sendable {
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
    case sandbox

    /// 网格里展示的普通板块；内版单独一行展示。
    static let regularCases: [DiscussionCategory] = allCases.filter { $0 != .inside }

    var title: String {
        switch self {
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
        case .sandbox: return "沙盒"
        }
    }

    /// 网页发内版前会弹确认，提示收取 5 鸡腿手续费。
    var chickenLegFee: Int? {
        self == .inside ? 5 : nil
    }
}

/// 阅读限制，rawValue 与网页 `select#rank` 的 option value 一致。
nonisolated struct DiscussionReadRank: Hashable, Codable, Sendable {
    let rawValue: Int

    static let everyone = DiscussionReadRank(rawValue: 0)
    static let onlyMe = DiscussionReadRank(rawValue: 255)

    static func level(_ level: Int) -> DiscussionReadRank {
        DiscussionReadRank(rawValue: level)
    }

    var title: String {
        switch rawValue {
        case Self.everyone.rawValue: return "公开"
        case Self.onlyMe.rawValue: return "私有"
        default: return "Lv\(rawValue)"
        }
    }

    /// 和网页一样按当前用户等级生成：公开、Lv1…Lv{等级}、私有。
    static func options(userLevel: Int) -> [DiscussionReadRank] {
        let levels = (0..<max(0, userLevel)).map { level($0 + 1) }
        return [everyone] + levels + [onlyMe]
    }
}
