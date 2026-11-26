import UIKit

final class UserCollectionCell: UITableViewCell {
    private let card = UIView()
    private let title = UILabel()
    private let chevron = UIImageView(image: UIImage(systemName: "chevron.forward"))
    private var appliedOffset: CGFloat?
    private var appliedCategory: UIContentSizeCategory?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 14
        card.layer.cornerCurve = .continuous
        card.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(card)
        title.textColor = ReadingColors.text
        title.numberOfLines = 3
        chevron.tintColor = .tertiaryLabel
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        chevron.setContentCompressionResistancePriority(.required, for: .horizontal)
        title.translatesAutoresizingMaskIntoConstraints = false
        chevron.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(title)
        card.addSubview(chevron)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5),
            title.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            title.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -10),
            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            title.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
            chevron.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14)
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ record: UserCollectionRecord) {
        title.text = record.title
        applyTypography()
        accessibilityIdentifier = "user-collection-post-\(record.postID)"
        accessibilityLabel = record.title
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if previous?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory { applyTypography() }
    }

    private func applyTypography() {
        let offset = AppTextSizeSettings.shared.pointOffset
        let category = traitCollection.preferredContentSizeCategory
        guard appliedOffset != offset || appliedCategory != category else { return }
        appliedOffset = offset
        appliedCategory = category
        title.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: AppTypography.listTitleFont(pointOffset: offset), compatibleWith: traitCollection)
        let font = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: AppTypography.listMetadataFont(pointOffset: offset), compatibleWith: traitCollection)
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(font: font, scale: .small)
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        card.backgroundColor = highlighted ? .tertiarySystemGroupedBackground : .secondarySystemGroupedBackground
    }
}

final class UserCollectionSkeletonCell: UserContentSkeletonCell {
    override var showsCard: Bool { true }
}

class UserContentSkeletonCell: UITableViewCell {
    var showsCard: Bool { false }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        accessibilityElementsHidden = true
        let skeleton = UserListSkeletonView(style: .collection, rowCount: 1)
        skeleton.backgroundColor = showsCard ? .secondarySystemGroupedBackground : .clear
        skeleton.layer.cornerRadius = 14
        skeleton.layer.cornerCurve = .continuous
        skeleton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(skeleton)
        NSLayoutConstraint.activate([
            skeleton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: showsCard ? 16 : 0),
            skeleton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: showsCard ? -16 : 0),
            skeleton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            skeleton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
