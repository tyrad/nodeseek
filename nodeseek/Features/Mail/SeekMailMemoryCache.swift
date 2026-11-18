//
//  SeekMailMemoryCache.swift
//  nodeseek
//

import UIKit

/// 只放内存的短期缓存，用来少发请求：seek.li 每个请求实际扣 2 次额度，每分钟约 30 次就会被限流。
/// - 邮箱和文件夹 5 分钟内复用，重新进入邮箱只拉邮件。
/// - 邮件详情和附件列表 2 分钟内复用，只缓存加载成功的结果。
/// App 退出、换 Key、系统内存紧张时都会清掉。
final class SeekMailMemoryCache {
    static let shared = SeekMailMemoryCache()

    static let mailboxLifetime: TimeInterval = 5 * 60
    static let detailLifetime: TimeInterval = 2 * 60
    static let maxEntryCount = 32
    static let maxBodyBytes = 4 * 1024 * 1024

    private struct Stamped<Value> {
        let value: Value
        let savedAt: Date
    }

    private let now: () -> Date
    /// 缓存属于哪个 Key；Key 变了整份作废，避免看到别的账号的数据。
    private var owner: String?
    private var mailboxes: Stamped<(mailboxes: [SeekMailbox], folders: [SeekMailFolder])>?
    private var details: [Int64: Stamped<SeekMailDetail>] = [:]
    private var attachments: [Int64: Stamped<[SeekMailAttachment]>] = [:]

    init(now: @escaping () -> Date = Date.init, notificationCenter: NotificationCenter = .default) {
        self.now = now
        notificationCenter.addObserver(self, selector: #selector(clear),
                                       name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
    }

    func mailboxes(for key: String) -> (mailboxes: [SeekMailbox], folders: [SeekMailFolder])? {
        guard prepare(for: key), let entry = mailboxes, isFresh(entry.savedAt, lifetime: Self.mailboxLifetime) else { return nil }
        return entry.value
    }

    func saveMailboxes(_ mailboxes: [SeekMailbox], folders: [SeekMailFolder], for key: String) {
        prepare(for: key)
        self.mailboxes = Stamped(value: (mailboxes, folders), savedAt: now())
    }

    func detail(id: Int64, for key: String) -> SeekMailDetail? {
        guard prepare(for: key), let entry = details[id], isFresh(entry.savedAt, lifetime: Self.detailLifetime) else { return nil }
        return entry.value
    }

    func saveDetail(_ detail: SeekMailDetail, for key: String) {
        prepare(for: key)
        details[detail.mail.id] = nil
        guard bodyBytes(detail) <= Self.maxBodyBytes else { return }
        details[detail.mail.id] = Stamped(value: detail, savedAt: now())
        while details.count > Self.maxEntryCount || details.values.reduce(0, { $0 + bodyBytes($1.value) }) > Self.maxBodyBytes {
            guard let oldest = details.min(by: { $0.value.savedAt < $1.value.savedAt })?.key else { break }
            details[oldest] = nil
        }
    }

    func attachments(mailID: Int64, for key: String) -> [SeekMailAttachment]? {
        guard prepare(for: key), let entry = attachments[mailID], isFresh(entry.savedAt, lifetime: Self.detailLifetime) else { return nil }
        return entry.value
    }

    func saveAttachments(_ list: [SeekMailAttachment], mailID: Int64, for key: String) {
        prepare(for: key)
        attachments[mailID] = Stamped(value: list, savedAt: now())
        while attachments.count > Self.maxEntryCount {
            guard let oldest = attachments.min(by: { $0.value.savedAt < $1.value.savedAt })?.key else { break }
            attachments[oldest] = nil
        }
    }

    /// 邮件删除或移走后不再从缓存打开。
    func removeMail(id: Int64) {
        details[id] = nil
        attachments[id] = nil
    }

    @objc func clear() {
        mailboxes = nil
        details = [:]
        attachments = [:]
    }

    /// 返回缓存是否属于这个 Key；换了 Key 时先清空，再归到新 Key 名下。
    @discardableResult
    private func prepare(for key: String) -> Bool {
        let fingerprint = SeekMailListCache.fingerprint(of: key)
        guard owner == fingerprint else {
            clear()
            owner = fingerprint
            return false
        }
        // 每次读写清理整份过期数据，避免只返回 nil 却一直保留正文。
        let date = now()
        details = details.filter { date.timeIntervalSince($0.value.savedAt) < Self.detailLifetime }
        attachments = attachments.filter { date.timeIntervalSince($0.value.savedAt) < Self.detailLifetime }
        if let entry = mailboxes, date.timeIntervalSince(entry.savedAt) >= Self.mailboxLifetime { mailboxes = nil }
        return true
    }

    private func bodyBytes(_ detail: SeekMailDetail) -> Int {
        detail.mail.bodyHtml.utf8.count + detail.mail.bodyText.utf8.count
    }

    private func isFresh(_ date: Date, lifetime: TimeInterval) -> Bool {
        now().timeIntervalSince(date) < lifetime
    }
}
