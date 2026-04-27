//
//  PostListTableViewCell.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import UIKit

final class PostListTableViewCell: UITableViewCell {

    static let reuseIdentifier = "PostListTableViewCell"

    private enum Layout {
        static let horizontalSpacing: CGFloat = 12
        static let verticalSpacing: CGFloat = 6
        static let avatarSize: CGFloat = 56
        static let contentInset = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 12)
    }

    private var representedAvatarURL: URL?
    private let avatarLoader = AvatarImageLoader.shared

    private let avatarImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = 10
        imageView.layer.masksToBounds = true
        imageView.backgroundColor = .systemGray5
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .headline)
        label.textColor = .label
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let metadataLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var textStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [titleLabel, metadataLabel])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = Layout.verticalSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedAvatarURL = nil
        avatarLoader.cancel(on: avatarImageView)
        avatarImageView.image = nil
        titleLabel.text = nil
        metadataLabel.text = nil
    }

    func configure(with post: PostSummary) {
        titleLabel.text = post.title
        metadataLabel.text = Self.metadataText(for: post)

        let avatarURL = post.avatarURL
        guard representedAvatarURL != avatarURL else {
            return
        }

        representedAvatarURL = avatarURL
        avatarLoader.loadAvatar(into: avatarImageView, postID: post.id, avatarURL: avatarURL)
    }

    private func setupUI() {
        selectionStyle = .default
        accessoryType = .none

        contentView.addSubview(avatarImageView)
        contentView.addSubview(textStack)

        NSLayoutConstraint.activate([
            avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Layout.contentInset.left),
            avatarImageView.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: Layout.contentInset.top),
            avatarImageView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -Layout.contentInset.bottom),
            avatarImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: Layout.avatarSize),
            avatarImageView.heightAnchor.constraint(equalToConstant: Layout.avatarSize),

            textStack.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: Layout.horizontalSpacing),
            textStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            textStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Layout.contentInset.top),
            textStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Layout.contentInset.bottom)
        ])
    }

    private static func metadataText(for post: PostSummary) -> String {
        var parts = [
            post.authorName,
            post.nodeName ?? "NodeSeek",
            "\(post.replyCount) 回复"
        ]

        if let lastActive = post.lastActivityText?.trimmingCharacters(in: .whitespacesAndNewlines), !lastActive.isEmpty {
            parts.append(lastActive)
        }

        return parts.joined(separator: " · ")
    }
}
