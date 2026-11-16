//
//  SeekMailModels.swift
//  nodeseek
//

import Foundation

nonisolated struct SeekMailbox: Codable, Equatable, Sendable {
    let id: Int64
    let address: String
    let alias: String?
    let domainId: Int64?
    let status: Int?
    let sendDisabled: Bool?
    let isPinned: Bool?
    let sortOrder: Int?

    /// nodeseek.org 域实测禁止发信，没有接口能查询，只能按后缀预判，最终以服务端返回为准。
    var canSendMail: Bool {
        sendDisabled != true && address.lowercased().hasSuffix("@nodeseek.org") == false
    }
}

nonisolated struct SeekMail: Codable, Equatable, Sendable {
    let id: Int64
    let mailboxId: Int64
    let folderId: Int64?
    let fromAddress: String
    let fromName: String?
    let toAddress: String?
    let cc: String?
    let subject: String
    /// 列表里只是约 200 字的摘要，详情里才是全文。
    let bodyText: String
    /// 列表里为空字符串，详情里才有。
    let bodyHtml: String
    let verificationCode: String?
    var isRead: Bool
    var isFlagged: Bool
    let isPinned: Bool
    let hasAttachments: Bool
    let status: String?
    let receivedAt: Date?
    let size: Int64?
    /// JSON 字符串，含 spf/dkim/dmarc 结果。
    let scoreDetails: String?

    private enum CodingKeys: String, CodingKey {
        case id, mailboxId, folderId, fromAddress, fromName, toAddress, cc, subject, bodyText, bodyHtml
        case verificationCode, isRead, isFlagged, isPinned, hasAttachments, status, receivedAt, size, scoreDetails
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int64.self, forKey: .id)
        mailboxId = try container.decode(Int64.self, forKey: .mailboxId)
        folderId = try container.decodeIfPresent(Int64.self, forKey: .folderId)
        fromAddress = try container.decodeIfPresent(String.self, forKey: .fromAddress) ?? ""
        fromName = try container.decodeIfPresent(String.self, forKey: .fromName).flatMap { $0.isEmpty ? nil : $0 }
        toAddress = try container.decodeIfPresent(String.self, forKey: .toAddress)
        cc = try container.decodeIfPresent(String.self, forKey: .cc).flatMap { $0.isEmpty ? nil : $0 }
        subject = try container.decodeIfPresent(String.self, forKey: .subject) ?? ""
        bodyText = try container.decodeIfPresent(String.self, forKey: .bodyText) ?? ""
        bodyHtml = try container.decodeIfPresent(String.self, forKey: .bodyHtml) ?? ""
        verificationCode = try container.decodeIfPresent(String.self, forKey: .verificationCode)
            .flatMap { $0.isEmpty ? nil : $0 }
        isRead = try container.decodeIfPresent(Bool.self, forKey: .isRead) ?? false
        isFlagged = try container.decodeIfPresent(Bool.self, forKey: .isFlagged) ?? false
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        hasAttachments = try container.decodeIfPresent(Bool.self, forKey: .hasAttachments) ?? false
        status = try container.decodeIfPresent(String.self, forKey: .status)
        receivedAt = try container.decodeIfPresent(Date.self, forKey: .receivedAt)
        size = try container.decodeIfPresent(Int64.self, forKey: .size)
        scoreDetails = try container.decodeIfPresent(String.self, forKey: .scoreDetails)
    }
}

nonisolated struct SeekMailTag: Decodable, Equatable, Sendable {
    let id: Int64
    let name: String
    let color: String?
}

/// `GET /mails/{id}` 实际返回 `data.mail` + `data.tags`，文档写的是直接返回邮件。
nonisolated struct SeekMailDetail: Decodable, Equatable, Sendable {
    var mail: SeekMail
    let tags: [SeekMailTag]

    private enum CodingKeys: String, CodingKey { case mail, tags }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mail = try container.decode(SeekMail.self, forKey: .mail)
        tags = try container.decodeIfPresent([SeekMailTag].self, forKey: .tags) ?? []
    }
}

nonisolated struct SeekMailPagination: Decodable, Equatable, Sendable {
    let total: Int
    let limit: Int
    let offset: Int

    var hasMore: Bool { offset + limit < total }
}

/// `GET /mails` 的完整响应；没有邮件时 `data` 为 null。
nonisolated struct SeekMailList: Decodable, Equatable, Sendable {
    let mails: [SeekMail]
    let pagination: SeekMailPagination?

    private enum CodingKeys: String, CodingKey {
        case mails = "data"
        case pagination
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mails = try container.decodeIfPresent([SeekMail].self, forKey: .mails) ?? []
        pagination = try container.decodeIfPresent(SeekMailPagination.self, forKey: .pagination)
    }
}

nonisolated struct SeekUnreadMail: Decodable, Equatable, Sendable {
    let id: Int64
    let mailboxId: Int64
    let mailboxAddress: String?
    let fromAddress: String
    let fromName: String?
    let subject: String?
    /// 服务端高置信度提取的验证码，未识别时缺省。
    let verificationCode: String?
    let receivedAt: Date?
}

/// `GET /mails/unread` 的完整响应，用游标分页。
nonisolated struct SeekUnreadMailPage: Decodable, Equatable, Sendable {
    struct Page: Decodable, Equatable, Sendable {
        let limit: Int
        let hasMore: Bool
        /// hasMore 为 false 时服务端返回空字符串，这里转成 nil。
        let nextCursor: String?

        private enum CodingKeys: String, CodingKey { case limit, hasMore, nextCursor }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            limit = try container.decodeIfPresent(Int.self, forKey: .limit) ?? 0
            hasMore = try container.decodeIfPresent(Bool.self, forKey: .hasMore) ?? false
            nextCursor = try container.decodeIfPresent(String.self, forKey: .nextCursor).flatMap { $0.isEmpty ? nil : $0 }
        }
    }

    let mails: [SeekUnreadMail]
    let page: Page?

    private enum CodingKeys: String, CodingKey {
        case mails = "data"
        case page
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mails = try container.decodeIfPresent([SeekUnreadMail].self, forKey: .mails) ?? []
        page = try container.decodeIfPresent(Page.self, forKey: .page)
    }
}

/// `GET /mails/counts` 只给各邮箱的未读数。
nonisolated struct SeekMailUnreadCounts: Decodable, Equatable, Sendable {
    let byMailbox: [Int64: Int]
    let total: Int

    private enum CodingKeys: String, CodingKey {
        case mailboxes, total
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decodeIfPresent([String: Int].self, forKey: .mailboxes) ?? [:]
        byMailbox = raw.reduce(into: [:]) { result, item in
            if let id = Int64(item.key) { result[id] = item.value }
        }
        total = try container.decodeIfPresent(Int.self, forKey: .total) ?? 0
    }
}

nonisolated struct SeekMailAttachment: Decodable, Equatable, Sendable {
    let id: Int64
    let mailId: Int64
    let filename: String
    let contentType: String?
    let size: Int64?
    let isInline: Bool?
    let index: Int
}

nonisolated struct SeekMailFolder: Codable, Equatable, Sendable {
    let id: Int64
    let name: String
    let color: String?
    /// 服务端用 emoji 作为图标。
    let icon: String?
    let sortOrder: Int?
    let mailCount: Int?
    let unreadCount: Int?
}

nonisolated struct SeekMailQuota: Decodable, Equatable, Sendable {
    struct Storage: Decodable, Equatable, Sendable {
        let used: Int64
        let quota: Int64
        let usagePercent: Int?
    }

    struct Mailboxes: Decodable, Equatable, Sendable {
        let count: Int
    }

    let storage: Storage?
    let mailboxes: Mailboxes?
}

/// 发信成功后返回的已入队邮件，只取用得到的字段。
nonisolated struct SeekMailSendResult: Decodable, Equatable, Sendable {
    let id: Int64
    let status: String?
    let messageId: String?
}

/// 下载附件、原始邮件这类非 JSON 响应。
nonisolated struct SeekMailFile: Equatable, Sendable {
    let data: Data
    let filename: String?
    let contentType: String?
}
