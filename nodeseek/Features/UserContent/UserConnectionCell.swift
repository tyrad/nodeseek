import UIKit

@MainActor
final class UserConnectionCell: UITableViewCell {
    private let avatar = UIImageView()
    private let nameLabel = UILabel()
    private let bioLabel = UILabel()
    private let statsLabel = UILabel()
    private let content = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .secondarySystemGroupedBackground
        accessoryType = .disclosureIndicator
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
        let head = UIStackView(arrangedSubviews: [avatar, info])
        head.alignment = .top
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
    }

    func configure(_ record: UserConnectionRecord) {
        AvatarImageLoader.shared.cancel(on: avatar)
        nameLabel.text = record.name.isEmpty ? "UID \(record.uid)" : record.name
        let bio = record.bio?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        bioLabel.text = bio.isEmpty ? "UID \(record.uid)" : bio
        func value(_ count: Int?) -> String { count.map { "\($0)" } ?? "—" }
        statsLabel.text = "Lv \(value(record.rank)) · 鸡腿 \(value(record.coin)) · 星辰 \(value(record.stardust))\n帖子 \(value(record.postCount)) · 评论 \(value(record.commentCount)) · 被关注 \(value(record.fans))"
        AvatarImageLoader.shared.loadAvatar(into: avatar, postID: "connections-\(record.uid)", avatarURL: NodeSeekNotificationURLBuilder.avatarURL(memberID: record.uid))
    }
}
