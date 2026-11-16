//
//  SeekMailAPI.swift
//  nodeseek
//

import Foundation

/// seek.li 邮箱 OpenAPI。字段和参数以 2026-11-16 实测为准，与官方文档不一致处见
/// docs/plans/2026-11-16-seekli-mail-design.md「已核实的数据契约」。
enum SeekMailAPI {
    static let baseURL = URL(string: "https://seek.li/openapi/v1")!

    // 邮箱
    case mailboxes
    case mailbox(id: Int64)

    // 邮件
    case mails(SeekMailListQuery)
    case unreadMails(limit: Int = 50, cursor: String? = nil, afterID: Int64? = nil)
    case mail(id: Int64)
    case mailCounts
    case markRead(id: Int64, read: Bool)
    case markFlagged(id: Int64, flagged: Bool)
    /// folderID 为 nil 表示移回收件箱。
    case moveMail(id: Int64, folderID: Int64?)
    /// 只会移到回收站，服务端没有彻底删除。
    case deleteMail(id: Int64)
    case rawMail(id: Int64)

    // 附件
    case attachments(mailID: Int64)
    case downloadAttachment(mailID: Int64, index: Int)

    // 文件夹、存储
    case folders
    case quotas

    // 发信
    case send(SeekMailDraft)
}

extension SeekMailAPI: SeekMailTargetType {
    var baseURL: URL { Self.baseURL }

    var path: String {
        switch self {
        case .mailboxes: return "/mailboxes"
        case .mailbox(let id): return "/mailboxes/\(id)"
        case .mails: return "/mails"
        case .unreadMails: return "/mails/unread"
        case .mail(let id), .deleteMail(let id): return "/mails/\(id)"
        case .mailCounts: return "/mails/counts"
        case .markRead(let id, _): return "/mails/\(id)/read"
        case .markFlagged(let id, _): return "/mails/\(id)/flag"
        case .moveMail(let id, _): return "/mails/\(id)/folder"
        case .rawMail(let id): return "/mails/\(id)/raw"
        case .attachments(let mailID): return "/mails/\(mailID)/attachments"
        case .downloadAttachment(let mailID, let index): return "/mails/\(mailID)/attachments/\(index)"
        case .folders: return "/folders"
        case .quotas: return "/quotas"
        case .send: return "/send"
        }
    }

    var method: SeekMailHTTPMethod {
        switch self {
        case .markRead, .markFlagged, .moveMail: return .put
        case .deleteMail: return .delete
        case .send: return .post
        default: return .get
        }
    }

    var requiredScope: String? {
        switch self {
        case .mailboxes, .mailbox: return "mailbox:read"
        case .mails, .unreadMails, .mail, .mailCounts, .rawMail: return "mail:read"
        case .markRead, .markFlagged, .moveMail, .deleteMail: return "mail:manage"
        case .attachments, .downloadAttachment: return "attachment:read"
        case .folders: return "folder:read"
        case .quotas: return "storage:read"
        case .send: return "mail:send"
        }
    }

    var task: SeekMailTask {
        switch self {
        case .mails(let query):
            return .requestParameters(query.parameters)
        case .unreadMails(let limit, let cursor, let afterID):
            return .requestParameters([
                "limit": String(limit),
                "cursor": cursor.flatMap { $0.isEmpty ? nil : $0 },
                "after_id": afterID.map(String.init)
            ])
        case .markRead(_, let read):
            return .requestJSON(["read": read])
        case .markFlagged(_, let flagged):
            return .requestJSON(["flagged": flagged])
        case .moveMail(_, let folderID):
            return .requestJSON(SeekMailMoveBody(folderId: folderID))
        case .send(let draft):
            return .requestJSON(draft)
        default:
            return .requestPlain
        }
    }
}

/// 邮件列表筛选条件，对应 `GET /mails` 的 query。
nonisolated struct SeekMailListQuery: Equatable, Sendable {
    enum Folder: String {
        case inbox, sent, trash, spam
    }

    var mailboxID: Int64?
    var folder: Folder?
    var folderID: Int64?
    var tagID: Int64?
    var search: String?
    var limit: Int = 20
    var offset: Int = 0

    var parameters: [String: String?] {
        let keyword = search?.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            "mailbox_id": mailboxID.map(String.init),
            "folder": folder?.rawValue,
            "folder_id": folderID.map(String.init),
            "tag_id": tagID.map(String.init),
            "search": keyword?.isEmpty == false ? keyword : nil,
            "limit": String(limit),
            "offset": String(offset)
        ]
    }
}

/// 发信内容。收件人在请求里要拼成逗号分隔的字符串，按文档传数组会被拒绝。
nonisolated struct SeekMailDraft: Encodable, Equatable, Sendable {
    var mailboxID: Int64
    var to: [String]
    var cc: [String] = []
    var bcc: [String] = []
    var subject: String
    var bodyText: String
    var bodyHTML: String?

    private enum CodingKeys: String, CodingKey {
        case mailboxId, to, cc, bcc, subject, bodyText, bodyHtml
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mailboxID, forKey: .mailboxId)
        try container.encode(Self.joined(to), forKey: .to)
        if cc.isEmpty == false { try container.encode(Self.joined(cc), forKey: .cc) }
        if bcc.isEmpty == false { try container.encode(Self.joined(bcc), forKey: .bcc) }
        try container.encode(subject, forKey: .subject)
        try container.encode(bodyText, forKey: .bodyText)
        if let bodyHTML, bodyHTML.isEmpty == false { try container.encode(bodyHTML, forKey: .bodyHtml) }
    }

    private static func joined(_ addresses: [String]) -> String {
        addresses
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .joined(separator: ",")
    }
}

/// 移回收件箱必须显式传 `"folderId": null`，合成的 Encodable 会直接省略 nil。
private nonisolated struct SeekMailMoveBody: Encodable {
    let folderId: Int64?

    private enum CodingKeys: String, CodingKey { case folderId }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let folderId {
            try container.encode(folderId, forKey: .folderId)
        } else {
            try container.encodeNil(forKey: .folderId)
        }
    }
}
