//
//  AccountRowCell.swift
//  nodeseek
//

import UIKit

/// 复用的已保存账号列表行：40pt 圆角头像 + 昵称 + UID / 失效状态 + 当前勾选标记。
final class AccountRowCell: UITableViewCell {
    static let reuseIdentifier = "AccountRowCell"

    private static let placeholderAvatar: UIImage? = {
        let config = UIImage.SymbolConfiguration(pointSize: 32, weight: .regular)
        return UIImage(systemName: "person.crop.circle.fill", withConfiguration: config)
    }()

    private let avatarView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 20
        imageView.backgroundColor = .secondarySystemBackground
        imageView.tintColor = .tertiaryLabel
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = ReadingColors.text
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let checkmarkView: UIImageView = {
        let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        let imageView = UIImageView(image: UIImage(systemName: "checkmark", withConfiguration: config))
        imageView.tintColor = .label
        imageView.contentMode = .scaleAspectFit
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.required, for: .horizontal)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private var currentAvatarURL: URL?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        currentAvatarURL = nil
        AvatarImageLoader.shared.cancel(on: avatarView)
        avatarView.image = Self.placeholderAvatar
        checkmarkView.isHidden = true
    }

    func configure(account: SavedAccount, isActive: Bool) {
        nameLabel.text = account.displayName
        let uidText = String(account.uid)
        if account.credentialState == .expired {
            subtitleLabel.text = AccountsL10n.format("UID %@ · 登录已失效，点击重新登录", uidText)
            subtitleLabel.textColor = .systemOrange
        } else if isActive {
            subtitleLabel.text = AccountsL10n.format("UID %@ · 当前使用", uidText)
            subtitleLabel.textColor = .secondaryLabel
        } else {
            subtitleLabel.text = AccountsL10n.format("UID %@", uidText)
            subtitleLabel.textColor = .secondaryLabel
        }
        checkmarkView.isHidden = !isActive

        let targetURL = account.avatarURL ?? URL(string: "https://www.nodeseek.com/avatar/\(account.uid).png")
        currentAvatarURL = targetURL
        avatarView.image = Self.placeholderAvatar
        if let targetURL {
            ImageLoad.url(targetURL)
                .toAvatar(requestID: "account-\(account.uid)")
                .into(avatarView)
        }

        accessibilityIdentifier = "account-row-\(account.uid)"
        let stateDesc = isActive ? AccountsL10n.text("当前使用") : (account.credentialState == .expired ? AccountsL10n.text("登录已失效") : "")
        accessibilityLabel = [account.displayName, "UID \(account.uid)", stateDesc]
            .filter { !$0.isEmpty }
            .joined(separator: "，")
    }

    private func setupLayout() {
        let textStack = UIStackView(arrangedSubviews: [nameLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 3
        textStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(avatarView)
        contentView.addSubview(textStack)
        contentView.addSubview(checkmarkView)

        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 40),
            avatarView.heightAnchor.constraint(equalToConstant: 40),

            textStack.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            textStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            textStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: checkmarkView.leadingAnchor, constant: -10),

            checkmarkView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            checkmarkView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            checkmarkView.widthAnchor.constraint(equalToConstant: 18),
            checkmarkView.heightAnchor.constraint(equalToConstant: 18)
        ])
    }
}
