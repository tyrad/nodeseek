//
//  PostSummaryCell.swift
//  nodeseek
//
//  Created by Codex on 2026/10/31.
//

import UIKit

final class PostSummaryCell: UITableViewCell {
    static let reuseIdentifier = "PostSummaryCell"

    private enum Layout {
        static let verticalSpacing: CGFloat = 5
        static let contentInset = UIEdgeInsets(
            top: PostListCellStyle.Layout.verticalContentInset,
            left: 16,
            bottom: PostListCellStyle.Layout.verticalContentInset,
            right: 12
        )
    }

    private let avatarImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = PostListCellStyle.Avatar.cornerRadius
        imageView.layer.masksToBounds = true
        imageView.backgroundColor = .systemGray5
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = Int(PostListCellStyle.Typography.titleMaximumNumberOfLines)
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    private let metadataLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = Int(PostListCellStyle.Typography.metadataMaximumNumberOfLines)
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    private lazy var textStackView: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [titleLabel, metadataLabel])
        stack.axis = .vertical
        stack.spacing = Layout.verticalSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private var textLeadingWithAvatar: NSLayoutConstraint!
    private var textLeadingWithoutAvatar: NSLayoutConstraint!
    private var avatarBottomConstraint: NSLayoutConstraint!
    private var item: PostListItem?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        AvatarImageLoader.shared.cancel(on: avatarImageView)
        avatarImageView.image = nil
        item = nil
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
        // 符号附件是按当前外观画好的位图，切换深浅色后要重建富文本。
        applyCurrentTheme()
    }

    func configure(with item: PostListItem) {
        let previousPostID = self.item?.post.id
        self.item = item
        applyCurrentTheme()

        let hasDisplayableAuthor = AuthorDisplayPolicy.isDisplayable(item.post.authorName)
        avatarImageView.isHidden = !hasDisplayableAuthor
        textLeadingWithAvatar.isActive = hasDisplayableAuthor
        textLeadingWithoutAvatar.isActive = !hasDisplayableAuthor
        avatarBottomConstraint.isActive = hasDisplayableAuthor

        // 同一帖子仅刷新访问状态时不重复请求头像。
        guard hasDisplayableAuthor, previousPostID != item.post.id || avatarImageView.image == nil else { return }
        ImageLoad.url(item.post.avatarURL)
            .toAvatar(requestID: item.post.id)
            .into(avatarImageView)
    }

    func applyCurrentTheme() {
        guard let item else { return }
        let specialFollowRules = SpecialFollowKeywordStore.shared.rules
        titleLabel.attributedText = PostSummaryText.titleAttributedText(
            for: item.post,
            isVisited: item.isVisited,
            specialFollowRules: specialFollowRules
        )
        metadataLabel.attributedText = PostSummaryText.metadataAttributedText(
            for: item.post,
            specialFollowRules: specialFollowRules
        )
    }

    var debugTitleAttributedText: NSAttributedString? {
        titleLabel.attributedText
    }

    var debugMetadataAttributedText: NSAttributedString? {
        metadataLabel.attributedText
    }

    private func setupUI() {
        selectionStyle = .none
        backgroundColor = .clear
        separatorInset = .zero
        contentView.addSubview(avatarImageView)
        contentView.addSubview(textStackView)

        let inset = Layout.contentInset
        textLeadingWithAvatar = textStackView.leadingAnchor.constraint(
            equalTo: avatarImageView.trailingAnchor,
            constant: PostListCellStyle.Layout.horizontalSpacing
        )
        textLeadingWithoutAvatar = textStackView.leadingAnchor.constraint(
            equalTo: contentView.leadingAnchor,
            constant: inset.left
        )
        avatarBottomConstraint = contentView.bottomAnchor.constraint(
            greaterThanOrEqualTo: avatarImageView.bottomAnchor,
            constant: inset.bottom
        )

        NSLayoutConstraint.activate([
            avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: inset.left),
            avatarImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: inset.top),
            avatarImageView.widthAnchor.constraint(equalToConstant: PostListCellStyle.Avatar.size),
            avatarImageView.heightAnchor.constraint(equalToConstant: PostListCellStyle.Avatar.size),
            avatarBottomConstraint,

            textLeadingWithAvatar,
            textStackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: inset.top),
            textStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -inset.right),
            contentView.bottomAnchor.constraint(greaterThanOrEqualTo: textStackView.bottomAnchor, constant: inset.bottom)
        ])

        // 让行高贴合头像和文字中较高的一侧，而不是被拉伸。
        let compactHeight = contentView.heightAnchor.constraint(equalToConstant: 0)
        compactHeight.priority = .fittingSizeLevel
        compactHeight.isActive = true
    }
}
