//
//  NotificationCells.swift
//  nodeseek
//
//  Created by Codex on 2026/6/8.
//

import UIKit

final class NotificationMentionCell: UITableViewCell {
    static let reuseIdentifier = "NotificationMentionCell"

    private let avatarLoader = AvatarImageLoader.shared
    private let avatarImageView = UIImageView()
    private let unreadDotView = UIView()
    private let profileButton = UIButton(type: .custom)
    private let nameButton = UIButton(type: .system)
    private let actionLabel = UILabel()
    private let titleLabel = UILabel()
    private let timeLabel = UILabel()
    private let markReadButton = UIButton(type: .system)
    private var onProfileTapped: (() -> Void)?
    private var onMarkReadTapped: (() -> Void)?
    private var representedID: Int?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .default
        backgroundColor = .systemBackground
        contentView.backgroundColor = .systemBackground
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        if representedID != nil {
            avatarLoader.cancel(on: avatarImageView)
        }
        representedID = nil
        avatarImageView.image = UIImage(systemName: "person.crop.square.fill")
        avatarImageView.tintColor = .tertiaryLabel
        unreadDotView.isHidden = true
        nameButton.setTitle(nil, for: .normal)
        actionLabel.text = nil
        titleLabel.text = nil
        timeLabel.text = nil
        markReadButton.isHidden = true
        onProfileTapped = nil
        onMarkReadTapped = nil
    }

    func configure(
        record: NodeSeekNotificationRecord,
        tab: NodeSeekNotificationTab,
        timeText: String,
        onProfileTapped: @escaping () -> Void,
        onMarkReadTapped: @escaping () -> Void
    ) {
        representedID = record.id
        self.onProfileTapped = onProfileTapped
        self.onMarkReadTapped = onMarkReadTapped
        nameButton.setTitle(record.commenterName, for: .normal)
        actionLabel.text = tab == .atMe ? "在帖子中@了我" : "回复了我的帖子"
        titleLabel.text = record.title
        timeLabel.text = timeText
        unreadDotView.isHidden = record.isViewed
        markReadButton.isHidden = record.isViewed
        accessibilityLabel = [
            record.commenterName,
            actionLabel.text,
            record.title,
            timeText
        ].compactMap { $0 }.joined(separator: " ")

        avatarImageView.image = UIImage(systemName: "person.crop.square.fill")
        avatarImageView.tintColor = .tertiaryLabel
        ImageLoad.url(record.avatarURL)
            .toAvatar(requestID: "\(record.commenterID)")
            .into(avatarImageView)
    }

    private func setupUI() {
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.layer.cornerRadius = 8
        avatarImageView.image = UIImage(systemName: "person.crop.square.fill")
        avatarImageView.tintColor = .tertiaryLabel

        unreadDotView.translatesAutoresizingMaskIntoConstraints = false
        unreadDotView.backgroundColor = .systemRed
        unreadDotView.layer.cornerRadius = 4
        unreadDotView.isHidden = true

        profileButton.translatesAutoresizingMaskIntoConstraints = false
        profileButton.accessibilityLabel = "打开用户主页"
        profileButton.addTarget(self, action: #selector(profileTapped), for: .touchUpInside)

        nameButton.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        nameButton.titleLabel?.adjustsFontForContentSizeCategory = true
        nameButton.contentHorizontalAlignment = .leading
        nameButton.setTitleColor(.label, for: .normal)
        nameButton.addTarget(self, action: #selector(profileTapped), for: .touchUpInside)
        nameButton.setContentHuggingPriority(.required, for: .horizontal)
        nameButton.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        actionLabel.font = .preferredFont(forTextStyle: .subheadline)
        actionLabel.textColor = .secondaryLabel
        actionLabel.adjustsFontForContentSizeCategory = true
        actionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.textColor = .label
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 2

        timeLabel.font = .preferredFont(forTextStyle: .caption1)
        timeLabel.textColor = .secondaryLabel
        timeLabel.adjustsFontForContentSizeCategory = true

        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        markReadButton.translatesAutoresizingMaskIntoConstraints = false
        markReadButton.setImage(UIImage(systemName: "envelope.open", withConfiguration: symbolConfiguration), for: .normal)
        markReadButton.tintColor = .secondaryLabel
        markReadButton.accessibilityLabel = "标为已读"
        markReadButton.accessibilityIdentifier = "notification-mark-read-button"
        markReadButton.addTarget(self, action: #selector(markReadTapped), for: .touchUpInside)

        let metaRow = UIStackView(arrangedSubviews: [nameButton, actionLabel])
        metaRow.translatesAutoresizingMaskIntoConstraints = false
        metaRow.axis = .horizontal
        metaRow.alignment = .firstBaseline
        metaRow.spacing = 5

        let textStack = UIStackView(arrangedSubviews: [metaRow, titleLabel, timeLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.alignment = .fill
        textStack.spacing = 4

        contentView.addSubview(avatarImageView)
        contentView.addSubview(unreadDotView)
        contentView.addSubview(profileButton)
        contentView.addSubview(textStack)
        contentView.addSubview(markReadButton)

        NSLayoutConstraint.activate([
            avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 13),
            avatarImageView.widthAnchor.constraint(equalToConstant: 40),
            avatarImageView.heightAnchor.constraint(equalToConstant: 40),
            avatarImageView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -13),

            unreadDotView.widthAnchor.constraint(equalToConstant: 8),
            unreadDotView.heightAnchor.constraint(equalToConstant: 8),
            unreadDotView.topAnchor.constraint(equalTo: avatarImageView.topAnchor, constant: -2),
            unreadDotView.trailingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 2),

            profileButton.leadingAnchor.constraint(equalTo: avatarImageView.leadingAnchor),
            profileButton.trailingAnchor.constraint(equalTo: avatarImageView.trailingAnchor),
            profileButton.topAnchor.constraint(equalTo: avatarImageView.topAnchor),
            profileButton.bottomAnchor.constraint(equalTo: avatarImageView.bottomAnchor),

            markReadButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            markReadButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            markReadButton.widthAnchor.constraint(equalToConstant: 36),
            markReadButton.heightAnchor.constraint(equalToConstant: 36),

            textStack.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: markReadButton.leadingAnchor, constant: -8),
            textStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 11),
            textStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -11)
        ])
    }

    @objc private func profileTapped() {
        onProfileTapped?()
    }

    @objc private func markReadTapped() {
        onMarkReadTapped?()
    }
}

final class NotificationMessageCell: UITableViewCell {
    static let reuseIdentifier = "NotificationMessageCell"

    private let avatarLoader = AvatarImageLoader.shared
    private let avatarImageView = UIImageView()
    private let unreadDotView = UIView()
    private let nameLabel = UILabel()
    private let contentLabel = UILabel()
    private let timeLabel = UILabel()
    private var representedID: Int?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator
        selectionStyle = .default
        backgroundColor = .systemBackground
        contentView.backgroundColor = .systemBackground
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        if representedID != nil {
            avatarLoader.cancel(on: avatarImageView)
        }
        representedID = nil
        avatarImageView.image = UIImage(systemName: "person.crop.square.fill")
        avatarImageView.tintColor = .tertiaryLabel
        unreadDotView.isHidden = true
        nameLabel.text = nil
        contentLabel.text = nil
        timeLabel.text = nil
    }

    func configure(
        record: NodeSeekMessageConversationRecord,
        currentUserID: Int?,
        timeText: String
    ) {
        representedID = record.maxID
        let participantName = record.participantName(currentUserID: currentUserID)
        nameLabel.text = participantName
        contentLabel.text = record.content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        timeLabel.text = timeText
        unreadDotView.isHidden = record.isViewed
        accessibilityLabel = [participantName, contentLabel.text, timeText]
            .compactMap { $0 }
            .joined(separator: " ")

        avatarImageView.image = UIImage(systemName: "person.crop.square.fill")
        avatarImageView.tintColor = .tertiaryLabel
        ImageLoad.url(record.participantAvatarURL(currentUserID: currentUserID))
            .toAvatar(requestID: "\(record.participantID(currentUserID: currentUserID))")
            .into(avatarImageView)
    }

    private func setupUI() {
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.layer.cornerRadius = 8
        avatarImageView.image = UIImage(systemName: "person.crop.square.fill")
        avatarImageView.tintColor = .tertiaryLabel

        unreadDotView.translatesAutoresizingMaskIntoConstraints = false
        unreadDotView.backgroundColor = .systemRed
        unreadDotView.layer.cornerRadius = 4
        unreadDotView.isHidden = true

        nameLabel.font = .preferredFont(forTextStyle: .body)
        nameLabel.textColor = .label
        nameLabel.adjustsFontForContentSizeCategory = true

        contentLabel.font = .preferredFont(forTextStyle: .subheadline)
        contentLabel.textColor = .secondaryLabel
        contentLabel.adjustsFontForContentSizeCategory = true
        contentLabel.numberOfLines = 2

        timeLabel.font = .preferredFont(forTextStyle: .caption1)
        timeLabel.textColor = .secondaryLabel
        timeLabel.adjustsFontForContentSizeCategory = true

        let textStack = UIStackView(arrangedSubviews: [nameLabel, contentLabel, timeLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.alignment = .fill
        textStack.spacing = 4

        contentView.addSubview(avatarImageView)
        contentView.addSubview(unreadDotView)
        contentView.addSubview(textStack)

        NSLayoutConstraint.activate([
            avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 13),
            avatarImageView.widthAnchor.constraint(equalToConstant: 40),
            avatarImageView.heightAnchor.constraint(equalToConstant: 40),
            avatarImageView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -13),

            unreadDotView.widthAnchor.constraint(equalToConstant: 8),
            unreadDotView.heightAnchor.constraint(equalToConstant: 8),
            unreadDotView.topAnchor.constraint(equalTo: avatarImageView.topAnchor, constant: -2),
            unreadDotView.trailingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 2),

            textStack.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            textStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 11),
            textStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -11)
        ])
    }
}
