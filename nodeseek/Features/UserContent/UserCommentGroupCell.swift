import UIKit

final class UserCommentGroupCell: UITableViewCell {
    private let title = UIButton(type: .system)
    private let postTitleLabel = UILabel()
    private var openPost: (() -> Void)?
    private let stack = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        postTitleLabel.numberOfLines = 0
        postTitleLabel.adjustsFontForContentSizeCategory = true
        postTitleLabel.textColor = ReadingColors.text
        postTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        title.addSubview(postTitleLabel)
        NSLayoutConstraint.activate([
            postTitleLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            postTitleLabel.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            postTitleLabel.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            postTitleLabel.topAnchor.constraint(greaterThanOrEqualTo: title.topAnchor)
        ])
        title.addAction(UIAction { [weak self] _ in self?.openPost?() }, for: .touchUpInside)
        title.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        stack.addArrangedSubview(title)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ group: UserCommentGroup, onOpenPost: @escaping () -> Void, onOpen: @escaping (UserCommentRecord) -> Void) {
        stack.arrangedSubviews.dropFirst().forEach { $0.removeFromSuperview() }
        openPost = onOpenPost
        title.accessibilityLabel = group.title
        postTitleLabel.text = group.title
        postTitleLabel.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: PostListCellStyle.Typography.titleFont, compatibleWith: traitCollection)
        for record in group.comments {
            let row = UIButton(type: .system)
            let text = UILabel()
            text.text = record.text.trimmingCharacters(in: .whitespacesAndNewlines)
            text.numberOfLines = 2
            text.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: PostListCellStyle.Typography.metadataFont, compatibleWith: traitCollection)
            text.adjustsFontForContentSizeCategory = true
            text.textColor = .secondaryLabel
            let icon = UIImageView(image: UIImage(systemName: "text.bubble"))
            icon.contentMode = .center
            icon.tintColor = .secondaryLabel
            let contents = UIStackView(arrangedSubviews: [text, icon])
            contents.spacing = 10
            contents.alignment = .center
            contents.translatesAutoresizingMaskIntoConstraints = false
            contents.isUserInteractionEnabled = false
            row.addSubview(contents)
            NSLayoutConstraint.activate([
                contents.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                contents.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                contents.topAnchor.constraint(equalTo: row.topAnchor),
                contents.bottomAnchor.constraint(equalTo: row.bottomAnchor),
                icon.widthAnchor.constraint(equalToConstant: 44),
                row.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
            ])
            row.accessibilityLabel = String(format: UserContentL10n.text("打开评论 #%ld"), record.floorID)
            row.accessibilityValue = text.text
            row.addAction(UIAction { _ in onOpen(record) }, for: .touchUpInside)
            stack.addArrangedSubview(row)
        }
    }
}
