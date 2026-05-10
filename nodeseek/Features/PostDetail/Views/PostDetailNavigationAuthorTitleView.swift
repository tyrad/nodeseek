//
//  PostDetailNavigationAuthorTitleView.swift
//  nodeseek
//

import UIKit

/// 导航栏中展示作者头像和名称的标题视图。
final class PostDetailNavigationAuthorTitleView: UIView {
    private enum Layout {
        static let avatarSize: CGFloat = 24
        static let horizontalSpacing: CGFloat = 8
    }

    private let avatarImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "person.crop.square.fill"))
        imageView.contentMode = .scaleAspectFill
        imageView.tintColor = .tertiaryLabel
        imageView.backgroundColor = .secondarySystemBackground
        imageView.layer.cornerRadius = 6
        imageView.layer.cornerCurve = .continuous
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.lineBreakMode = .byTruncatingTail
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override var intrinsicContentSize: CGSize {
        let nameWidth = nameLabel.intrinsicContentSize.width
        let width = min(180, Layout.avatarSize + Layout.horizontalSpacing + nameWidth)
        return CGSize(width: width, height: 32)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(postID: String, authorName: String, avatarURL: URL?) {
        nameLabel.text = AuthorDisplayPolicy.displayName(from: authorName)
        accessibilityLabel = nameLabel.text
        invalidateIntrinsicContentSize()
        avatarImageView.image = UIImage(systemName: "person.crop.square.fill")
        avatarImageView.tintColor = .tertiaryLabel
        ImageLoad.url(avatarURL)
            .toAvatar(requestID: postID)
            .into(avatarImageView)
    }

    func setVisible(_ isVisible: Bool, animated: Bool) {
        let changes = {
            self.alpha = isVisible ? 1 : 0
        }

        if isVisible {
            isHidden = false
        }

        guard animated else {
            changes()
            isHidden = !isVisible
            return
        }

        UIView.animate(
            withDuration: 0.18,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
            animations: changes
        ) { _ in
            self.isHidden = !isVisible
        }
    }

    private func setupView() {
        accessibilityIdentifier = "post-detail-navigation-author-title"
        addSubview(avatarImageView)
        addSubview(nameLabel)

        NSLayoutConstraint.activate([
            avatarImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            avatarImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: Layout.avatarSize),
            avatarImageView.heightAnchor.constraint(equalToConstant: Layout.avatarSize),

            nameLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: Layout.horizontalSpacing),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            heightAnchor.constraint(equalToConstant: 32),
            widthAnchor.constraint(lessThanOrEqualToConstant: 180)
        ])
    }
}
