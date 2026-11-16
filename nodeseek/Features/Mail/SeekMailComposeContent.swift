//
//  SeekMailComposeContent.swift
//  nodeseek
//

import Foundation

/// 写信页的纯逻辑：收件人解析、回复预填、发件邮箱选择。和界面分开，方便单测。
struct SeekMailComposeContent: Equatable {
    var mailboxID: Int64?
    var to: String = ""
    var cc: String = ""
    var subject: String = ""
    var body: String = ""

    /// 收件人可以用逗号、分号、空格或换行分隔。
    static func addresses(from text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",;，；").union(.whitespacesAndNewlines))
            .filter { $0.isEmpty == false }
    }

    static func isValidAddress(_ address: String) -> Bool {
        address.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil
    }

    /// 只有能发信的邮箱可选；优先用指定的邮箱，否则用第一个能发信的。
    static func defaultSender(in mailboxes: [SeekMailbox], preferred: Int64?) -> Int64? {
        if let preferred, mailboxes.first(where: { $0.id == preferred })?.canSendMail == true { return preferred }
        return mailboxes.first { $0.canSendMail }?.id
    }

    static func reply(to mail: SeekMail, mailboxes: [SeekMailbox]) -> SeekMailComposeContent {
        let subject = mail.subject.range(of: #"^\s*re\s*[:：]"#, options: [.regularExpression, .caseInsensitive]) == nil
            ? "Re: \(mail.subject)" : mail.subject
        let sender = mail.fromName.map { "\($0) <\(mail.fromAddress)>" } ?? mail.fromAddress
        // 原文末尾的空行不引用，否则会多出几行空的「>」
        let quoted = mail.bodyText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .map { "> \($0)" }
            .joined(separator: "\n")
        let time = SeekMailFormat.detailTime(mail.receivedAt)
        let intro = time.isEmpty ? SeekMailL10n.format("%@ 写道：", sender) : SeekMailL10n.format("在 %@，%@ 写道：", time, sender)
        return SeekMailComposeContent(
            mailboxID: defaultSender(in: mailboxes, preferred: mail.mailboxId),
            to: mail.fromAddress,
            subject: subject,
            body: "\n\n\(intro)\n\(quoted)"
        )
    }

    enum Problem: Equatable {
        case noSender
        case noRecipient
        case invalidAddress(String)
        case emptyContent
    }

    /// 发送前的检查，返回第一个问题；没问题时返回 nil。
    var problem: Problem? {
        guard mailboxID != nil else { return .noSender }
        let recipients = Self.addresses(from: to)
        guard recipients.isEmpty == false else { return .noRecipient }
        if let bad = (recipients + Self.addresses(from: cc)).first(where: { Self.isValidAddress($0) == false }) {
            return .invalidAddress(bad)
        }
        if subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .emptyContent
        }
        return nil
    }

    var draft: SeekMailDraft? {
        guard problem == nil, let mailboxID else { return nil }
        return SeekMailDraft(
            mailboxID: mailboxID,
            to: Self.addresses(from: to),
            cc: Self.addresses(from: cc),
            subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
            bodyText: body
        )
    }
}

extension SeekMailComposeContent.Problem {
    var message: String {
        switch self {
        case .noSender: return SeekMailL10n.text("没有可用的发件邮箱")
        case .noRecipient: return SeekMailL10n.text("请填写收件人")
        case .invalidAddress(let address): return SeekMailL10n.format("收件地址格式不对：%@", address)
        case .emptyContent: return SeekMailL10n.text("主题和正文不能都为空")
        }
    }
}
