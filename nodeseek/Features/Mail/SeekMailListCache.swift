//
//  SeekMailListCache.swift
//  nodeseek
//

import CryptoKit
import Foundation

/// 列表快照：进入邮箱时先显示上次的第一页，再在后台刷新。
/// 按 Key 指纹隔离，换了账号的旧快照直接作废；只存在 Caches，系统清理也无妨。
final class SeekMailListCache {
    private nonisolated struct Snapshot: Codable {
        var keyFingerprint: String
        var mailboxes: [SeekMailbox]
        var folders: [SeekMailFolder]
        /// 键是「邮箱 + 文件夹」，例如 "all|inbox"、"12|folder:3"。
        var pages: [String: [SeekMail]]
    }

    /// 每个范围只留第一页，范围太多时丢掉最早的，避免文件无限变大。
    static let maxPages = 20

    private let fileURL: URL
    private var snapshot: Snapshot?
    private var pageOrder: [String] = []

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        fileURL = base.appendingPathComponent("seek-mail-list.json")
    }

    static func fingerprint(of key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    static func pageKey(mailboxID: Int64?, scope: SeekMailFolderScope) -> String {
        "\(mailboxID.map(String.init) ?? "all")|\(scope.storageValue)"
    }

    func mailboxes(for key: String) -> (mailboxes: [SeekMailbox], folders: [SeekMailFolder])? {
        guard let snapshot = load(for: key), snapshot.mailboxes.isEmpty == false else { return nil }
        return (snapshot.mailboxes, snapshot.folders)
    }

    func mails(for key: String, page: String) -> [SeekMail]? {
        load(for: key)?.pages[page]
    }

    func saveMailboxes(_ mailboxes: [SeekMailbox], folders: [SeekMailFolder], for key: String) {
        var snapshot = load(for: key) ?? Snapshot(keyFingerprint: Self.fingerprint(of: key), mailboxes: [], folders: [], pages: [:])
        snapshot.mailboxes = mailboxes
        snapshot.folders = folders
        write(snapshot)
    }

    func saveMails(_ mails: [SeekMail], for key: String, page: String) {
        var snapshot = load(for: key) ?? Snapshot(keyFingerprint: Self.fingerprint(of: key), mailboxes: [], folders: [], pages: [:])
        snapshot.pages[page] = Array(mails.prefix(SeekMailInboxModel.pageSize))
        pageOrder.removeAll { $0 == page }
        pageOrder.append(page)
        while snapshot.pages.count > Self.maxPages, let oldest = pageOrder.first {
            pageOrder.removeFirst()
            snapshot.pages[oldest] = nil
        }
        write(snapshot)
    }

    func clear() {
        snapshot = nil
        pageOrder = []
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func load(for key: String) -> Snapshot? {
        let fingerprint = Self.fingerprint(of: key)
        if let snapshot, snapshot.keyFingerprint == fingerprint { return snapshot }
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? SeekMailJSON.decoder.decode(Snapshot.self, from: data),
              decoded.keyFingerprint == fingerprint else {
            return nil
        }
        snapshot = decoded
        pageOrder = Array(decoded.pages.keys)
        return decoded
    }

    private func write(_ snapshot: Snapshot) {
        self.snapshot = snapshot
        guard let data = try? Self.encoder.encode(snapshot) else { return }
        // 快照里有邮件摘要，写入时加文件保护
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// 时间按 ISO8601 带毫秒写入，和 SeekMailJSON.decoder 的解析规则对齐。
    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        return encoder
    }
}
