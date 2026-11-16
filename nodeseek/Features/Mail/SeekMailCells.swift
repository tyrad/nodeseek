//
//  SeekMailCells.swift
//  nodeseek
//

import UIKit

enum SeekMailFormat {
    /// 今天显示时间，昨天显示「昨天」，今年显示月日，更早带年份。
    static func listTime(_ date: Date?, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        if calendar.isDate(date, inSameDayAs: now) {
            formatter.dateFormat = "HH:mm"
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "昨天"
        } else if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            formatter.dateFormat = "M月d日"
        } else {
            formatter.dateFormat = "yyyy/M/d"
        }
        return formatter.string(from: date)
    }

    static func detailTime(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter.string(from: date)
    }

    /// 只写「几分钟前收到」，不暗示验证码的有效期。
    static func receivedAgo(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "" }
        let minutes = Int(max(0, now.timeIntervalSince(date)) / 60)
        return minutes < 1 ? "刚刚收到" : "\(minutes) 分钟前收到"
    }

    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    /// 摘要只显示一行，把换行和连续空白压成一个空格。
    static func preview(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// 搜索关键字在本地加粗高亮。
    static func highlighted(_ text: String, keyword: String, font: UIFont, color: UIColor) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return result }
        let nsText = text as NSString
        var range = NSRange(location: 0, length: nsText.length)
        while true {
            let found = nsText.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive], range: range)
            guard found.location != NSNotFound else { break }
            result.addAttributes([
                .backgroundColor: UIColor.systemYellow.withAlphaComponent(0.35),
                .foregroundColor: UIColor.label
            ], range: found)
            let next = found.location + found.length
            range = NSRange(location: next, length: nsText.length - next)
        }
        return result
    }
}

/// 黑白主题的反色胶囊按钮：.label 底、.systemBackground 字。
enum SeekMailStyle {
    static func codeButtonConfiguration(_ title: String, compact: Bool) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.filled()
        configuration.baseBackgroundColor = .label
        configuration.baseForegroundColor = .systemBackground
        configuration.cornerStyle = .capsule
        configuration.contentInsets = compact
            ? NSDirectionalEdgeInsets(top: 4, leading: 9, bottom: 4, trailing: 9)
            : NSDirectionalEdgeInsets(top: 7, leading: 14, bottom: 7, trailing: 14)
        var attributes = AttributeContainer()
        attributes.font = compact
            ? SeekMailFont.digits(14, weight: .semibold)
            : SeekMailFont.system(15, weight: .semibold)
        configuration.attributedTitle = AttributedString(title, attributes: attributes)
        return configuration
    }

    /// 复制后原位显示「已复制」约 2 秒，并给一下轻触觉反馈。
    static func copy(_ text: String, feedbackOn button: UIButton, compact: Bool) {
        UIPasteboard.general.string = text
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let original = button.configuration
        button.configuration = codeButtonConfiguration("已复制", compact: compact)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak button] in
            guard let button, button.configuration?.title == "已复制" else { return }
            button.configuration = original
        }
    }
}

final class SeekMailCell: UITableViewCell {
    static let reuseIdentifier = "SeekMailCell"

    private let unreadDot = UIView()
    private let senderLabel = UILabel()
    private let flagView = UIImageView(image: UIImage(systemName: "star.fill"))
    private let attachmentView = UIImageView(image: UIImage(systemName: "paperclip"))
    private let timeLabel = UILabel()
    private let subjectLabel = UILabel()
    private let previewLabel = UILabel()
    private let codeButton = UIButton(type: .system)
    private var code: String?

    var onCopyCode: ((String) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        unreadDot.backgroundColor = .label
        unreadDot.layer.cornerRadius = 4
        unreadDot.translatesAutoresizingMaskIntoConstraints = false

        senderLabel.font = SeekMailFont.of(.body)
        senderLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        timeLabel.font = SeekMailFont.of(.footnote)
        timeLabel.textColor = .secondaryLabel
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        flagView.tintColor = .systemOrange
        flagView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .caption1)
        attachmentView.tintColor = .secondaryLabel
        attachmentView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .caption1)
        [flagView, attachmentView].forEach { $0.setContentHuggingPriority(.required, for: .horizontal) }

        subjectLabel.font = SeekMailFont.of(.subheadline)
        previewLabel.font = SeekMailFont.of(.subheadline)
        previewLabel.textColor = .secondaryLabel

        codeButton.accessibilityIdentifier = "seek-mail-row-code"
        codeButton.setContentHuggingPriority(.required, for: .horizontal)
        codeButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        codeButton.addAction(UIAction { [weak self] _ in
            guard let self, let code else { return }
            SeekMailStyle.copy(code, feedbackOn: codeButton, compact: true)
            onCopyCode?(code)
        }, for: .touchUpInside)

        let topRow = UIStackView(arrangedSubviews: [senderLabel, flagView, attachmentView, timeLabel])
        topRow.spacing = 6
        topRow.alignment = .firstBaseline
        let textStack = UIStackView(arrangedSubviews: [topRow, subjectLabel, previewLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        let row = UIStackView(arrangedSubviews: [textStack, codeButton])
        row.spacing = 10
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(unreadDot)
        contentView.addSubview(row)
        NSLayoutConstraint.activate([
            unreadDot.widthAnchor.constraint(equalToConstant: 8),
            unreadDot.heightAnchor.constraint(equalToConstant: 8),
            unreadDot.centerXAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            unreadDot.centerYAnchor.constraint(equalTo: senderLabel.centerYAnchor),
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            row.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        ])
        separatorInset = UIEdgeInsets(top: 0, left: 24, bottom: 0, right: 0)
    }

    func configure(mail: SeekMail, recipient: SeekMailboxDisplay?, keyword: String) {
        unreadDot.isHidden = mail.isRead
        let sender = mail.fromName ?? mail.fromAddress
        senderLabel.font = SeekMailFont.of(.body).withWeight(mail.isRead ? .regular : .semibold)
        senderLabel.attributedText = SeekMailFormat.highlighted(sender, keyword: keyword, font: senderLabel.font, color: .label)
        flagView.isHidden = mail.isFlagged == false
        attachmentView.isHidden = mail.hasAttachments == false
        timeLabel.font = SeekMailFont.of(.footnote)
        timeLabel.text = SeekMailFormat.listTime(mail.receivedAt)

        let subject = mail.subject.isEmpty ? "（无主题）" : mail.subject
        let subjectFont = SeekMailFont.of(.subheadline).withWeight(mail.isRead ? .regular : .semibold)
        subjectLabel.attributedText = SeekMailFormat.highlighted(subject, keyword: keyword, font: subjectFont, color: .label)

        let previewFont = SeekMailFont.of(.subheadline)
        let preview = NSMutableAttributedString()
        if let recipient {
            preview.append(NSAttributedString(string: "→ \(recipient.title) · ", attributes: [
                .font: previewFont, .foregroundColor: UIColor.secondaryLabel
            ]))
        }
        preview.append(SeekMailFormat.highlighted(SeekMailFormat.preview(mail.bodyText), keyword: keyword,
                                                  font: previewFont, color: .secondaryLabel))
        previewLabel.attributedText = preview

        code = mail.verificationCode
        codeButton.isHidden = code == nil
        if let code { codeButton.configuration = SeekMailStyle.codeButtonConfiguration(code, compact: true) }

        var parts = [mail.isRead ? nil : "未读", sender, subject, mail.isFlagged ? "已加星标" : nil,
                     mail.hasAttachments ? "有附件" : nil, timeLabel.text]
        if let code { parts.append("验证码 \(code)") }
        accessibilityLabel = parts.compactMap { $0 }.joined(separator: "，")
    }
}

/// 首次加载时的骨架行。
final class SeekMailSkeletonCell: UITableViewCell {
    static let reuseIdentifier = "SeekMailSkeletonCell"

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        isUserInteractionEnabled = false
        let ratios: [CGFloat] = [0.45, 0.8, 0.65]
        let bars = ratios.map { _ -> UIView in
            let bar = UIView()
            bar.backgroundColor = .secondarySystemFill
            bar.layer.cornerRadius = 5
            bar.translatesAutoresizingMaskIntoConstraints = false
            return bar
        }
        let stack = UIStackView(arrangedSubviews: bars)
        stack.axis = .vertical
        stack.spacing = 9
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14)
        ])
        // 宽度约束跨到 contentView，必须等条形视图进了视图层级再激活
        for (bar, ratio) in zip(bars, ratios) {
            bar.heightAnchor.constraint(equalToConstant: 11).isActive = true
            bar.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: ratio).isActive = true
        }
        separatorInset = UIEdgeInsets(top: 0, left: 24, bottom: 0, right: 0)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// 顶部验证码卡片：只放当前范围最新的一条。
final class SeekMailCodeCell: UITableViewCell {
    static let reuseIdentifier = "SeekMailCodeCell"

    private let codeLabel = UILabel()
    private let detailLabel = UILabel()
    private let copyButton = UIButton(type: .system)
    private var code: String?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        let card = UIView()
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 12
        card.layer.cornerCurve = .continuous
        card.translatesAutoresizingMaskIntoConstraints = false

        codeLabel.font = SeekMailFont.digits(26, weight: .bold)
        codeLabel.adjustsFontSizeToFitWidth = true
        codeLabel.minimumScaleFactor = 0.6
        codeLabel.accessibilityIdentifier = "seek-mail-code-card-code"
        detailLabel.font = SeekMailFont.of(.footnote)
        detailLabel.textColor = .secondaryLabel
        detailLabel.lineBreakMode = .byTruncatingMiddle
        copyButton.configuration = SeekMailStyle.codeButtonConfiguration("复制", compact: false)
        copyButton.accessibilityIdentifier = "seek-mail-code-card-copy"
        copyButton.setContentHuggingPriority(.required, for: .horizontal)
        copyButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        copyButton.addAction(UIAction { [weak self] _ in
            guard let self, let code else { return }
            SeekMailStyle.copy(code, feedbackOn: copyButton, compact: false)
        }, for: .touchUpInside)

        let text = UIStackView(arrangedSubviews: [codeLabel, detailLabel])
        text.axis = .vertical
        text.spacing = 2
        let row = UIStackView(arrangedSubviews: [text, copyButton])
        row.alignment = .center
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)
        contentView.addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10)
        ])
        separatorInset = UIEdgeInsets(top: 0, left: 10_000, bottom: 0, right: 0)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(mail: SeekMail, recipient: SeekMailboxDisplay?) {
        code = mail.verificationCode
        // 每次配置时取当前字号，调整「字体大小」后刷新列表即可生效
        codeLabel.font = SeekMailFont.digits(26, weight: .bold)
        detailLabel.font = SeekMailFont.of(.footnote)
        codeLabel.text = mail.verificationCode
        let sender = mail.fromName ?? mail.fromAddress
        let target = recipient.map { " → \($0.title)" } ?? ""
        detailLabel.text = "\(sender)\(target) · \(SeekMailFormat.receivedAgo(mail.receivedAt))"
        copyButton.configuration = SeekMailStyle.codeButtonConfiguration("复制", compact: false)
        accessibilityElements = [codeLabel, detailLabel, copyButton]
        codeLabel.accessibilityLabel = "最新验证码 \(mail.verificationCode ?? "")"
    }
}

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
