//
//  HotListL10n.swift
//  nodeseek
//

import Foundation

nonisolated enum HotListL10n {
    static func text(_ key: String, bundle: Bundle = .main) -> String {
        bundle.localizedString(forKey: key, value: key, table: "HotList")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: arguments)
    }
}

extension HotListKind {
    /// 列表顶部的 tab 名。
    var tabTitle: String {
        switch self {
        case .realtime: return HotListL10n.text("实时")
        case .daily: return HotListL10n.text("日榜")
        case .weekly: return HotListL10n.text("周榜")
        }
    }

    /// 设置页里的接口名。
    var sourceTitle: String {
        switch self {
        case .realtime: return HotListL10n.text("实时榜")
        case .daily: return HotListL10n.text("日榜")
        case .weekly: return HotListL10n.text("周榜")
        }
    }

    var rangeDescription: String {
        switch self {
        case .realtime: return HotListL10n.text("近 2 小时热门")
        case .daily: return HotListL10n.text("近 24 小时热门")
        case .weekly: return HotListL10n.text("近 7 天热门")
        }
    }
}
