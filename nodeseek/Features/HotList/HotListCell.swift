//
//  HotListCell.swift
//  nodeseek
//

import UIKit

/// 热榜一行：排名｜标题（最多两行）＋信息行（小头像、作者 · 分类 · 时间、浏览/回复/热度）。
final class HotListCell: UITableViewCell {
    static let reuseIdentifier = "HotListCell"

    private enum Layout {
        static let horizontalInset: CGFloat = 16
        static let verticalInset: CGFloat = 12
        static let rankWidth: CGFloat = 28
        static let avatarSize: CGFloat = 16
    }

    private let avatarLoader = AvatarImageLoader.shared
    private var representedPostID: String?

    private let rankLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.textColor = ReadingColors.text
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    private let avatarImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.backgroundColor = .secondarySystemBackground
        imageView.tintColor = .tertiaryLabel
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 4
        imageView.image = UIImage(systemName: "person.crop.square.fill")
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let metaLabel: UILabel = {
        let label = UILabel()
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }()

    private let statsLabel: UILabel = {
        let label = UILabel()
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }()

    private lazy var metaRow: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [avatarImageView, metaLabel, statsLabel])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 6
        stack.setCustomSpacing(10, after: metaLabel)
        return stack
    }()

    private lazy var contentStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [titleLabel, metaRow])
        stack.axis = .vertical
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .systemBackground
        contentView.addSubview(rankLabel)
        contentView.addSubview(contentStack)
        separatorInset = UIEdgeInsets(top: 0, left: Layout.horizontalInset + Layout.rankWidth + 8, bottom: 0, right: 0)

        NSLayoutConstraint.activate([
            rankLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Layout.horizontalInset - 4),
            rankLabel.widthAnchor.constraint(equalToConstant: Layout.rankWidth),
            rankLabel.firstBaselineAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor),

            avatarImageView.widthAnchor.constraint(equalToConstant: Layout.avatarSize),
            avatarImageView.heightAnchor.constraint(equalToConstant: Layout.avatarSize),

            contentStack.leadingAnchor.constraint(equalTo: rankLabel.trailingAnchor, constant: 8),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Layout.horizontalInset),
            contentStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Layout.verticalInset),
            contentStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Layout.verticalInset)
        ])
        applyFonts()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        if representedPostID != nil {
            avatarLoader.cancel(on: avatarImageView)
            representedPostID = nil
        }
        avatarImageView.image = UIImage(systemName: "person.crop.square.fill")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory else { return }
        applyMetaRowAxis()
    }

    /// 已读标题用次级色，与首页列表一致。
    func configure(rank: Int, entry: HotListEntry, timeText: String?, isVisited: Bool) {
        applyFonts()
        representedPostID = String(entry.postID)
        rankLabel.text = "\(rank)"
        let isTop = rank <= 3
        rankLabel.font = UIFont.monospacedDigitSystemFont(
            ofSize: AppTextSizeSettings.adjustedPointSize(basePointSize: isTop ? 19 : 16),
            weight: isTop ? .heavy : .medium
        )
        rankLabel.textColor = isTop ? .label : .secondaryLabel
        titleLabel.text = entry.title
        titleLabel.textColor = isVisited ? .secondaryLabel : ReadingColors.unreadTitle
        metaLabel.text = [entry.authorName, entry.categoryTitle, timeText]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " · ")
        statsLabel.attributedText = Self.stats(entry: entry, font: metaLabel.font)
        accessibilityLabel = [
            HotListL10n.format("第 %ld 名", rank),
            entry.title,
            metaLabel.text,
            HotListL10n.format("浏览 %ld", entry.viewCount),
            HotListL10n.format("回复 %ld", entry.commentCount),
            HotListL10n.format("热度 %ld", Int(entry.score))
        ].compactMap { $0 }.joined(separator: "，")
        ImageLoad.url(entry.avatarURL)
            .toAvatar(requestID: String(entry.postID))
            .into(avatarImageView)
    }

    private func applyFonts() {
        titleLabel.font = AppTypography.listTitleFont()
        metaLabel.font = AppTypography.font(basePointSize: 12)
        statsLabel.font = metaLabel.font
        applyMetaRowAxis()
    }

    /// 辅助功能大字号下信息行放不下，改为上下排列，避免截断统计数字。
    private func applyMetaRowAxis() {
        let isAccessibilitySize = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        metaRow.axis = isAccessibilitySize ? .vertical : .horizontal
        metaRow.alignment = isAccessibilitySize ? .leading : .center
    }

    /// 一万以上用当前语言的紧凑写法（如「2.3万」「23K」），避免统计数字挤掉作者和时间。
    private static func compact(_ value: Int) -> String {
        guard value >= 10_000 else { return value.formatted(.number.grouping(.never)) }
        return value.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
    }

    private static func stats(entry: HotListEntry, font: UIFont) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let items: [(String, String, Bool)] = [
            ("eye", compact(entry.viewCount), false),
            ("bubble.left", compact(entry.commentCount), false),
            ("flame", compact(Int(entry.score)), true)
        ]
        let configuration = UIImage.SymbolConfiguration(font: font, scale: .small)
        for (index, item) in items.enumerated() {
            let color: UIColor = item.2 ? .label : .secondaryLabel
            let attributes: [NSAttributedString.Key: Any] = [
                .font: item.2 ? UIFont.systemFont(ofSize: font.pointSize, weight: .semibold) : font,
                .foregroundColor: color
            ]
            if index > 0 { result.append(NSAttributedString(string: "  ", attributes: attributes)) }
            if let image = UIImage(systemName: item.0, withConfiguration: configuration)?
                .withTintColor(color, renderingMode: .alwaysOriginal) {
                result.append(NSAttributedString(attachment: NSTextAttachment(image: image)))
            }
            result.append(NSAttributedString(string: " " + item.1, attributes: attributes))
        }
        return result
    }
}
