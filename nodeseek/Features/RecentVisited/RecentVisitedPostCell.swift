//
//  RecentVisitedPostCell.swift
//  nodeseek
//
//  Created by Codex on 2026/5/2.
//

import UIKit

final class RecentVisitedPostCell: UITableViewCell {
    private enum Layout {
        static let avatarSize: CGFloat = 44
        static let horizontalInset: CGFloat = 16
        static let verticalInset: CGFloat = 10
    }

    private let avatarLoader = AvatarImageLoader.shared
    private var representedPostID: String?

    private let avatarImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.backgroundColor = .secondarySystemBackground
        imageView.tintColor = .tertiaryLabel
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 10
        imageView.image = UIImage(systemName: "person.crop.square.fill")
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .label
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let visitedLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator
        selectionStyle = .default
        contentView.addSubview(avatarImageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(visitedLabel)

        NSLayoutConstraint.activate([
            avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Layout.horizontalInset),
            avatarImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Layout.verticalInset),
            avatarImageView.widthAnchor.constraint(equalToConstant: Layout.avatarSize),
            avatarImageView.heightAnchor.constraint(equalToConstant: Layout.avatarSize),
            avatarImageView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -Layout.verticalInset),

            titleLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Layout.verticalInset),

            visitedLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            visitedLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            visitedLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            visitedLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Layout.verticalInset)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        if representedPostID != nil {
            avatarLoader.cancel(on: avatarImageView)
            self.representedPostID = nil
        }
        avatarImageView.image = UIImage(systemName: "person.crop.square.fill")
        titleLabel.text = nil
        visitedLabel.text = nil
    }

    func configure(record: VisitedPostRecord, visitedText: String) {
        representedPostID = record.postID
        titleLabel.text = record.title
        visitedLabel.text = visitedText
        ImageLoad.url(record.avatarURL)
            .toAvatar(requestID: record.postID)
            .into(avatarImageView)
    }
}
