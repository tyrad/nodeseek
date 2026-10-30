import UIKit

@MainActor
final class UserConnectionCell: UITableViewCell {
    private let avatar = UIImageView()
    private let nameLabel = UILabel()
    private let bioLabel = UILabel()
    private let statsLabel = UILabel()
    private let content = UIStackView()
    private let followButton = UIButton(configuration: .plain())
    var onToggleFollow: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .secondarySystemGroupedBackground
        avatar.contentMode = .scaleAspectFill
        avatar.layer.cornerRadius = 10
        avatar.layer.cornerCurve = .continuous
        avatar.clipsToBounds = true
        avatar.backgroundColor = .systemGray5
        avatar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            avatar.widthAnchor.constraint(equalToConstant: 44),
            avatar.heightAnchor.constraint(equalToConstant: 44)
        ])
        nameLabel.font = .preferredFont(forTextStyle: .headline)
        nameLabel.textColor = .label
        bioLabel.font = .preferredFont(forTextStyle: .footnote)
        bioLabel.textColor = .secondaryLabel
        statsLabel.font = .preferredFont(forTextStyle: .caption1)
        statsLabel.textColor = .secondaryLabel
        [nameLabel, bioLabel, statsLabel].forEach {
            $0.numberOfLines = 0
            $0.adjustsFontForContentSizeCategory = true
        }
        let info = UIStackView(arrangedSubviews: [nameLabel, bioLabel])
        info.axis = .vertical
        info.spacing = 4
        followButton.setContentHuggingPriority(.required, for: .horizontal)
        followButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        followButton.accessibilityIdentifier = "connection-follow-button"
        followButton.addAction(UIAction { [weak self] _ in self?.onToggleFollow?() }, for: .touchUpInside)
        let head = UIStackView(arrangedSubviews: [avatar, info, followButton])
        head.alignment = .center
        head.spacing = 12
        content.axis = .vertical
        content.spacing = 10
        [head, statsLabel].forEach { content.addArrangedSubview($0) }
        content.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            content.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        AvatarImageLoader.shared.cancel(on: avatar)
        onToggleFollow = nil
    }

    func configure(_ record: UserConnectionRecord, isUpdatingFollow: Bool = false) {
        configureFollowButton(followed: record.followed ?? false, busy: isUpdatingFollow)
        AvatarImageLoader.shared.cancel(on: avatar)
        nameLabel.text = record.name.isEmpty ? "UID \(record.uid)" : record.name
        let bio = record.bio?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        bioLabel.text = bio.isEmpty ? "UID \(record.uid)" : bio
        func value(_ count: Int?) -> String { count.map { "\($0)" } ?? "—" }
        statsLabel.text = "Lv \(value(record.rank)) · 鸡腿 \(value(record.coin)) · 星辰 \(value(record.stardust))\n帖子 \(value(record.postCount)) · 评论 \(value(record.commentCount)) · 被关注 \(value(record.fans))"
        AvatarImageLoader.shared.loadAvatar(into: avatar, postID: "connections-\(record.uid)", avatarURL: NodeSeekNotificationURLBuilder.avatarURL(memberID: record.uid))
    }

    private func configureFollowButton(followed: Bool, busy: Bool) {
        followButton.applyFollowStyle(followed: followed, busy: busy)
    }
}

extension UIButton {
    /// 关注按钮，列表和个人页共用。
    /// 未关注：反色实心胶囊，作为主操作；已关注：灰底弱化，点按后确认取消
    func applyFollowStyle(followed: Bool, busy: Bool) {
        var configuration = UIButton.Configuration.plain()
        configuration.title = followed ? "已关注" : "关注"
        configuration.image = followed ? nil : UIImage(
            systemName: "plus",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)
        )
        configuration.imagePadding = 3
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .systemFont(ofSize: 13.5, weight: .semibold))
            return attributes
        }
        configuration.baseForegroundColor = followed ? .secondaryLabel : .systemBackground
        configuration.background.backgroundColor = followed ? .tertiarySystemFill : .label
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        configuration.showsActivityIndicator = busy
        self.configuration = configuration
        // 不用 isEnabled：禁用态会被系统换成另一套底色，请求期间只屏蔽点击、保持原样转圈
        isUserInteractionEnabled = !busy
        accessibilityLabel = followed ? "已关注，点按取消关注" : "关注"
    }
}
