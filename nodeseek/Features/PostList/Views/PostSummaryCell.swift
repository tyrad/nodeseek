//
//  PostSummaryCell.swift
//  nodeseek
//
//  Created by Codex on 2026/10/31.
//

import UIKit

/// 帖子行。不用 Auto Layout，直接按 `PostSummaryLayout` 摆放，
/// 行高和文字由列表在后台提前算好，滚动时主线程不再重复测量。
final class PostSummaryCell: UITableViewCell {
    static let reuseIdentifier = "PostSummaryCell"

    private let avatarImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = PostListCellStyle.Avatar.cornerRadius
        imageView.layer.masksToBounds = true
        imageView.backgroundColor = .systemGray5
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

    private var item: PostListItem?
    private var layout: PostSummaryLayout?

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
        layout = nil
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
        // 符号附件是按当前外观画好的位图，切换深浅色后要重建富文本。
        applyCurrentTheme()
    }

    /// `layout` 由列表提供；为空时按当前宽度同步补算。
    func configure(with item: PostListItem, layout: PostSummaryLayout? = nil) {
        let previousPostID = self.item?.post.id
        self.item = item
        apply(layout ?? makeLayout(for: item, width: contentView.bounds.width))

        let hasDisplayableAuthor = AuthorDisplayPolicy.isDisplayable(item.post.authorName)
        avatarImageView.isHidden = !hasDisplayableAuthor

        // 同一帖子仅刷新访问状态时不重复请求头像。
        guard hasDisplayableAuthor, previousPostID != item.post.id || avatarImageView.image == nil else { return }
        ImageLoad.url(item.post.avatarURL)
            .toAvatar(requestID: item.post.id)
            .into(avatarImageView)
    }

    func applyCurrentTheme() {
        guard let item else { return }
        apply(makeLayout(for: item, width: contentView.bounds.width))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let item else { return }
        // 列表给的排版和实际宽度不一致时（如旋转、分屏）才补算。
        if let layout, layout.context.width == contentView.bounds.width {
            applyFrames()
        } else {
            apply(makeLayout(for: item, width: contentView.bounds.width))
        }
    }

    var debugTitleAttributedText: NSAttributedString? {
        titleLabel.attributedText
    }

    var debugMetadataAttributedText: NSAttributedString? {
        metadataLabel.attributedText
    }

    private func makeLayout(for item: PostListItem, width: CGFloat) -> PostSummaryLayout {
        PostSummaryLayout.make(
            item: item,
            context: .current(width: width, traitCollection: traitCollection)
        )
    }

    private func apply(_ layout: PostSummaryLayout) {
        self.layout = layout
        titleLabel.attributedText = layout.title
        metadataLabel.attributedText = layout.metadata
        applyFrames()
    }

    private func applyFrames() {
        guard let layout else { return }
        if let avatarFrame = layout.avatarFrame {
            avatarImageView.frame = avatarFrame
        }
        titleLabel.frame = layout.titleFrame
        metadataLabel.frame = layout.metadataFrame
    }

    private func setupUI() {
        selectionStyle = .none
        backgroundColor = .clear
        separatorInset = .zero
        contentView.addSubview(avatarImageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(metadataLabel)
    }
}
