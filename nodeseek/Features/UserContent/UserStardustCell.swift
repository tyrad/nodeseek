import UIKit

@MainActor
final class UserStardustCell: UITableViewCell {
    private let reasonLabel = UILabel()
    private let changeLabel = UILabel()
    private let timeLabel = UILabel()
    private let balanceLabel = UILabel()
    private let peer = StardustMemberView()
    private let member = StardustMemberView()
    private let arrow = UIImageView()
    private let members = UIStackView()
    private let stack = UIStackView()
    private let skeletonBlock = UIView()
    private var contentConstraints: [NSLayoutConstraint] = []
    private var skeletonConstraints: [NSLayoutConstraint] = []
    private var equalMemberWidths: NSLayoutConstraint!
    private var wideMemberWidths: [NSLayoutConstraint] = []
    private var outgoing = false
    private var showsPeer = true
    var onSelectUser: ((Int) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .secondarySystemGroupedBackground
        reasonLabel.font = Self.font(16, weight: .semibold, style: .body)
        changeLabel.font = UIFontMetrics(forTextStyle: .title3).scaledFont(for: .monospacedDigitSystemFont(ofSize: 20, weight: .semibold))
        timeLabel.font = Self.font(12, style: .caption1)
        balanceLabel.font = Self.font(12, style: .caption1)
        [reasonLabel, changeLabel, timeLabel, balanceLabel].forEach {
            $0.adjustsFontForContentSizeCategory = true
            $0.numberOfLines = 0
            $0.textColor = .label
        }
        timeLabel.textColor = .secondaryLabel
        balanceLabel.textColor = .secondaryLabel
        changeLabel.textAlignment = .right
        balanceLabel.textAlignment = .right
        changeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        let top = UIStackView(arrangedSubviews: [reasonLabel, changeLabel])
        top.spacing = 12
        top.alignment = .firstBaseline
        let bottom = UIStackView(arrangedSubviews: [timeLabel, balanceLabel])
        bottom.spacing = 8
        bottom.alignment = .firstBaseline
        arrow.tintColor = .secondaryLabel
        arrow.contentMode = .scaleAspectFit
        arrow.setContentHuggingPriority(.required, for: .horizontal)
        arrow.widthAnchor.constraint(equalToConstant: 18).isActive = true
        arrow.heightAnchor.constraint(equalToConstant: 18).isActive = true
        members.addArrangedSubview(peer)
        members.addArrangedSubview(arrow)
        members.addArrangedSubview(member)
        members.alignment = .center
        members.spacing = 8
        equalMemberWidths = peer.widthAnchor.constraint(equalTo: member.widthAnchor)
        equalMemberWidths.isActive = true
        wideMemberWidths = [peer.widthAnchor.constraint(equalTo: members.widthAnchor), member.widthAnchor.constraint(equalTo: members.widthAnchor)]
        stack.axis = .vertical
        stack.spacing = 2
        [top, members, bottom].forEach { stack.addArrangedSubview($0) }
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        contentConstraints = [
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ]
        NSLayoutConstraint.activate(contentConstraints)
        skeletonBlock.backgroundColor = .systemGray5
        skeletonBlock.layer.cornerRadius = 12
        skeletonBlock.layer.cornerCurve = .continuous
        skeletonBlock.translatesAutoresizingMaskIntoConstraints = false
        skeletonBlock.isHidden = true
        skeletonBlock.accessibilityIdentifier = "stardust-record-skeleton"
        contentView.addSubview(skeletonBlock)
        skeletonConstraints = [
            skeletonBlock.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            skeletonBlock.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            skeletonBlock.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            skeletonBlock.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            skeletonBlock.heightAnchor.constraint(equalToConstant: 82)
        ]
        peer.onSelect = { [weak self] uid in self?.onSelectUser?(uid) }
        member.onSelect = { [weak self] uid in self?.onSelectUser?(uid) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        peer.cancelImage()
        member.cancelImage()
        onSelectUser = nil
    }

    func configure(record: UserStardustRecord?, profile: UserProfileRecord?) {
        let isSkeleton = record == nil
        isUserInteractionEnabled = !isSkeleton
        accessibilityElementsHidden = isSkeleton
        stack.isHidden = isSkeleton
        skeletonBlock.isHidden = !isSkeleton
        NSLayoutConstraint.deactivate(isSkeleton ? contentConstraints : skeletonConstraints)
        NSLayoutConstraint.activate(isSkeleton ? skeletonConstraints : contentConstraints)
        guard let record else {
            peer.cancelImage()
            member.cancelImage()
            return
        }
        reasonLabel.text = record.typeText
        changeLabel.text = record.changeText
        balanceLabel.text = "余额 \(record.result)"
        timeLabel.text = Self.timeText(record.createdAt)
        showsPeer = record.validPeerID != nil
        peer.isHidden = !showsPeer
        arrow.isHidden = peer.isHidden
        outgoing = record.isOutgoingTransfer
        updateMemberLayout()
        arrow.isAccessibilityElement = true
        peer.configure(uid: record.validPeerID, name: nil)
        let memberName = profile?.uid == record.memberID ? profile?.name : nil
        member.configure(uid: record.memberID, name: memberName)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateMemberLayout()
    }

    private func updateMemberLayout() {
        let vertical = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        equalMemberWidths.isActive = false
        NSLayoutConstraint.deactivate(wideMemberWidths)
        members.axis = vertical ? .vertical : .horizontal
        members.alignment = vertical ? .leading : .center
        if vertical {
            wideMemberWidths[1].isActive = true
            wideMemberWidths[0].isActive = showsPeer
        } else {
            equalMemberWidths.isActive = showsPeer
        }
        arrow.image = UIImage(systemName: vertical ? (outgoing ? "arrow.up" : "arrow.down") : (outgoing ? "arrow.left" : "arrow.right"))
        arrow.accessibilityLabel = outgoing ? "转给对方用户" : "来自对方用户"
    }

    private static func font(_ size: CGFloat, weight: UIFont.Weight = .regular, style: UIFont.TextStyle) -> UIFont {
        UIFontMetrics(forTextStyle: style).scaledFont(for: .systemFont(ofSize: size, weight: weight))
    }

    private static func timeText(_ raw: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = iso.date(from: raw)
        if date == nil {
            iso.formatOptions = [.withInternetDateTime]
            date = iso.date(from: raw)
        }
        guard let date else { return raw }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: date)
    }
}

@MainActor
private final class StardustMemberView: UIControl {
    private let avatar = UIImageView()
    private let nameLabel = UILabel()
    private var uid: Int?
    var onSelect: ((Int) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true
        avatar.layer.cornerRadius = 7
        avatar.layer.cornerCurve = .continuous
        avatar.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: .systemFont(ofSize: 13))
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.textColor = .label
        nameLabel.numberOfLines = 0
        let content = UIStackView(arrangedSubviews: [avatar, nameLabel])
        content.alignment = .center
        content.spacing = 8
        content.isUserInteractionEnabled = false
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            avatar.widthAnchor.constraint(equalToConstant: 28),
            avatar.heightAnchor.constraint(equalToConstant: 28),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
        addAction(UIAction { [weak self] _ in
            guard let self, let uid else { return }
            onSelect?(uid)
        }, for: .touchUpInside)
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(uid: Int?, name: String?) {
        self.uid = uid
        cancelImage()
        avatar.backgroundColor = .systemGray5
        nameLabel.text = name?.isEmpty == false ? name : uid.map { "UID \($0)" }
        accessibilityLabel = nameLabel.text
        accessibilityHint = "查看用户主页"
        isEnabled = uid != nil
        avatar.image = nil
        if let uid {
            AvatarImageLoader.shared.loadAvatar(into: avatar, postID: "stardust-\(uid)", avatarURL: NodeSeekNotificationURLBuilder.avatarURL(memberID: uid))
        }
    }

    func cancelImage() { AvatarImageLoader.shared.cancel(on: avatar) }
}
