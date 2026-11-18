//
//  SeekMailboxNaming.swift
//  nodeseek
//

import Foundation

/// 一个邮箱在界面上的名字。邮箱很多时只显示 @ 前面的部分，读起来更快。
struct SeekMailboxDisplay: Equatable {
    /// 主名字：别名，或 @ 前面的部分；重名时是完整地址。
    let title: String
    /// 跟在主名字后面的浅灰域名，例如 “@seek.li”；主名字已含域名或用了别名时为 nil。
    let domainSuffix: String?
    let address: String
    let hasAlias: Bool
}

enum SeekMailboxNaming {
    /// 异常响应或旧缓存可能重复返回同一邮箱，保留首次记录以稳定名称和排序。
    static func uniqueMailboxes(_ mailboxes: [SeekMailbox]) -> [SeekMailbox] {
        var seen = Set<Int64>()
        return mailboxes.filter { seen.insert($0.id).inserted }
    }

    /// 是否重名要和全部邮箱比较，所以输入是整个列表。
    static func displays(for mailboxes: [SeekMailbox]) -> [Int64: SeekMailboxDisplay] {
        let mailboxes = uniqueMailboxes(mailboxes)
        var localCounts: [String: Int] = [:]
        for mailbox in mailboxes where alias(of: mailbox) == nil {
            localCounts[localPart(of: mailbox.address).lowercased(), default: 0] += 1
        }

        var result: [Int64: SeekMailboxDisplay] = [:]
        for mailbox in mailboxes {
            if let alias = alias(of: mailbox) {
                result[mailbox.id] = SeekMailboxDisplay(title: alias, domainSuffix: nil, address: mailbox.address, hasAlias: true)
                continue
            }
            let local = localPart(of: mailbox.address)
            let domain = domainPart(of: mailbox.address)
            if localCounts[local.lowercased(), default: 0] > 1 || domain == nil {
                // 不同域名下 @ 前部分相同，只显示前半段就分不清了
                result[mailbox.id] = SeekMailboxDisplay(title: mailbox.address, domainSuffix: nil, address: mailbox.address, hasAlias: false)
            } else {
                result[mailbox.id] = SeekMailboxDisplay(title: local, domainSuffix: domain.map { "@\($0)" }, address: mailbox.address, hasAlias: false)
            }
        }
        return result
    }

    private static func alias(of mailbox: SeekMailbox) -> String? {
        let text = mailbox.alias?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    static func localPart(of address: String) -> String {
        guard let at = address.lastIndex(of: "@") else { return address }
        return String(address[..<at])
    }

    static func domainPart(of address: String) -> String? {
        guard let at = address.lastIndex(of: "@") else { return nil }
        let domain = address[address.index(after: at)...]
        return domain.isEmpty ? nil : String(domain)
    }
}

/// 邮箱选择面板的分组。逻辑和界面分开，方便单测。
struct SeekMailboxPickerSections: Equatable {
    struct Row: Equatable {
        let mailboxID: Int64
        let unreadCount: Int
    }

    var recents: [Row] = []
    var pinned: [Row] = []
    var unread: [Row] = []
    var others: [Row] = []
    /// 搜索时不显示「最近」和「全部邮箱」，只显示匹配结果。
    var isSearching = false

    static func make(
        mailboxes: [SeekMailbox],
        names: [Int64: SeekMailboxDisplay],
        counts: [Int64: Int],
        recentIDs: [Int64],
        query: String
    ) -> SeekMailboxPickerSections {
        let mailboxes = SeekMailboxNaming.uniqueMailboxes(mailboxes)
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matched = mailboxes.filter { mailbox in
            guard keyword.isEmpty == false else { return true }
            return mailbox.address.lowercased().contains(keyword)
                || (mailbox.alias?.lowercased().contains(keyword) ?? false)
        }
        let sorted = matched.sorted { lhs, rhs in
            switch (lhs.sortOrder, rhs.sortOrder) {
            case let (l?, r?) where l != r: return l < r
            case (_?, nil): return true
            case (nil, _?): return false
            default:
                let l = names[lhs.id]?.title ?? lhs.address
                let r = names[rhs.id]?.title ?? rhs.address
                return l.localizedStandardCompare(r) == .orderedAscending
            }
        }
        func row(_ mailbox: SeekMailbox) -> Row { Row(mailboxID: mailbox.id, unreadCount: counts[mailbox.id] ?? 0) }

        var sections = SeekMailboxPickerSections(isSearching: keyword.isEmpty == false)
        if keyword.isEmpty {
            let byID = Dictionary(uniqueKeysWithValues: mailboxes.map { ($0.id, $0) })
            sections.recents = recentIDs.compactMap { byID[$0] }.prefix(3).map(row)
        }
        for mailbox in sorted {
            if mailbox.isPinned == true {
                sections.pinned.append(row(mailbox))
            } else if (counts[mailbox.id] ?? 0) > 0 {
                sections.unread.append(row(mailbox))
            } else {
                sections.others.append(row(mailbox))
            }
        }
        return sections
    }
}
