//
//  SettingsTextSizeCells.swift
//  nodeseek
//
//  Created by Codex on 2026/5/10.
//

import UIKit

final class SettingsTextSizeAdjustmentCell: UITableViewCell {
    var onPointOffsetChanged: ((CGFloat) -> Void)?

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "字体大小"
        label.font = .systemFont(ofSize: 17, weight: .regular)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let valueLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15, weight: .regular)
        label.textColor = .secondaryLabel
        label.textAlignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let slider: UISlider = {
        let slider = UISlider()
        slider.minimumValue = Float(AppTextSizeSettings.minimumPointOffset)
        slider.maximumValue = Float(AppTextSizeSettings.maximumPointOffset)
        slider.isContinuous = true
        slider.accessibilityIdentifier = "settings-text-size-slider"
        slider.translatesAutoresizingMaskIntoConstraints = false
        return slider
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(pointOffset: CGFloat) {
        let normalized = AppTextSizeSettings.normalizedPointOffset(pointOffset)
        slider.value = Float(normalized)
        valueLabel.text = AppTextSizeSettings.displayText(for: normalized)
        slider.accessibilityValue = valueLabel.text
    }

    private func setupUI() {
        selectionStyle = .none
        accessibilityIdentifier = "settings-text-size-adjustment-cell"
        contentView.addSubview(titleLabel)
        contentView.addSubview(valueLabel)
        contentView.addSubview(slider)
        slider.addTarget(self, action: #selector(sliderChanged(_:)), for: .valueChanged)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            titleLabel.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor, constant: 2),

            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 12),
            valueLabel.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

            slider.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            slider.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            slider.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            slider.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor, constant: -2)
        ])
    }

    @objc private func sliderChanged(_ sender: UISlider) {
        let normalized = AppTextSizeSettings.normalizedPointOffset(CGFloat(sender.value))
        sender.value = Float(normalized)
        valueLabel.text = AppTextSizeSettings.displayText(for: normalized)
        sender.accessibilityValue = valueLabel.text
        onPointOffsetChanged?(normalized)
    }
}

final class SettingsTextSizePreviewCell: UITableViewCell {
    private enum Layout {
        static let listAvatarSize: CGFloat = PostListCellStyle.Avatar.size
        static let commentAvatarSize: CGFloat = PostDetailContentLayout.avatarSize
    }

    private let containerStack = UIStackView()
    private let listPreview = UIView()
    private let commentPreview = UIView()
    private let listAvatarView = UIView()
    private let commentAvatarView = UIView()
    private let listTitleLabel = UILabel()
    private let listMetadataLabel = UILabel()
    private let commentAuthorLabel = UILabel()
    private let commentMetaLabel = UILabel()
    private let commentBodyLabel = UILabel()
    private let commentActionLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(pointOffset: CGFloat) {
        listTitleLabel.font = AppTypography.listTitleFont(pointOffset: pointOffset)
        listMetadataLabel.font = AppTypography.listMetadataFont(pointOffset: pointOffset)
        commentAuthorLabel.font = AppTypography.commentAuthorFont(pointOffset: pointOffset)
        commentMetaLabel.font = AppTypography.commentMetadataFont(pointOffset: pointOffset)
        commentBodyLabel.font = AppTypography.commentBodyFont(pointOffset: pointOffset)
        commentActionLabel.font = AppTypography.commentActionFont(pointOffset: pointOffset)
        [
            listTitleLabel,
            listMetadataLabel,
            commentAuthorLabel,
            commentMetaLabel,
            commentBodyLabel,
            commentActionLabel
        ].forEach { $0.invalidateIntrinsicContentSize() }
        setNeedsLayout()
        contentView.setNeedsLayout()
    }

    var debugListTitleFont: UIFont? {
        listTitleLabel.font
    }

    var debugCommentBodyFont: UIFont? {
        commentBodyLabel.font
    }

    var debugCommentActionNumberOfLines: Int {
        commentActionLabel.numberOfLines
    }

    private func setupUI() {
        selectionStyle = .none
        accessibilityIdentifier = "settings-text-size-preview-cell"

        containerStack.axis = .vertical
        containerStack.spacing = 14
        containerStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(containerStack)

        setupListPreview()
        setupCommentPreview()
        containerStack.addArrangedSubview(listPreview)
        containerStack.addArrangedSubview(commentPreview)

        NSLayoutConstraint.activate([
            containerStack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            containerStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            containerStack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor, constant: 2),
            containerStack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor, constant: -2)
        ])
    }

    private func setupListPreview() {
        listPreview.translatesAutoresizingMaskIntoConstraints = false
        listAvatarView.backgroundColor = .systemGray5
        listAvatarView.layer.cornerRadius = PostListCellStyle.Avatar.cornerRadius
        listAvatarView.translatesAutoresizingMaskIntoConstraints = false

        listTitleLabel.text = "节点列表字体调整预览，标题可自然换行"
        listTitleLabel.textColor = .label
        listTitleLabel.numberOfLines = 0
        listTitleLabel.translatesAutoresizingMaskIntoConstraints = false

        listMetadataLabel.text = "mistj  128  32  刚刚"
        listMetadataLabel.textColor = .secondaryLabel
        listMetadataLabel.numberOfLines = 0
        listMetadataLabel.translatesAutoresizingMaskIntoConstraints = false

        let textStack = UIStackView(arrangedSubviews: [listTitleLabel, listMetadataLabel])
        textStack.axis = .vertical
        textStack.spacing = 5
        textStack.translatesAutoresizingMaskIntoConstraints = false

        listPreview.addSubview(listAvatarView)
        listPreview.addSubview(textStack)
        NSLayoutConstraint.activate([
            listAvatarView.leadingAnchor.constraint(equalTo: listPreview.leadingAnchor),
            listAvatarView.topAnchor.constraint(equalTo: listPreview.topAnchor),
            listAvatarView.widthAnchor.constraint(equalToConstant: Layout.listAvatarSize),
            listAvatarView.heightAnchor.constraint(equalToConstant: Layout.listAvatarSize),
            listPreview.bottomAnchor.constraint(greaterThanOrEqualTo: listAvatarView.bottomAnchor),

            textStack.leadingAnchor.constraint(equalTo: listAvatarView.trailingAnchor, constant: PostListCellStyle.Layout.horizontalSpacing),
            textStack.trailingAnchor.constraint(equalTo: listPreview.trailingAnchor),
            textStack.topAnchor.constraint(equalTo: listPreview.topAnchor),
            textStack.bottomAnchor.constraint(equalTo: listPreview.bottomAnchor)
        ])
    }

    private func setupCommentPreview() {
        commentPreview.translatesAutoresizingMaskIntoConstraints = false
        commentAvatarView.backgroundColor = .systemGray5
        commentAvatarView.layer.cornerRadius = PostDetailContentLayout.avatarCornerRadius
        commentAvatarView.translatesAutoresizingMaskIntoConstraints = false

        commentAuthorLabel.text = "ipv4"
        commentAuthorLabel.textColor = .label
        commentAuthorLabel.translatesAutoresizingMaskIntoConstraints = false

        commentMetaLabel.text = "#12  5min ago"
        commentMetaLabel.textColor = .secondaryLabel
        commentMetaLabel.numberOfLines = 0
        commentMetaLabel.translatesAutoresizingMaskIntoConstraints = false

        let headerStack = UIStackView(arrangedSubviews: [commentAuthorLabel, commentMetaLabel])
        headerStack.axis = .vertical
        headerStack.spacing = 3
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        commentBodyLabel.text = "评论正文跟随同一套 App 内字号，预览会随滑块实时变化。"
        commentBodyLabel.textColor = .label
        commentBodyLabel.numberOfLines = 0
        commentBodyLabel.translatesAutoresizingMaskIntoConstraints = false

        commentActionLabel.text = "点赞  加鸡腿  回复"
        commentActionLabel.textColor = .secondaryLabel
        commentActionLabel.numberOfLines = 0
        commentActionLabel.translatesAutoresizingMaskIntoConstraints = false

        let textStack = UIStackView(arrangedSubviews: [headerStack, commentBodyLabel, commentActionLabel])
        textStack.axis = .vertical
        textStack.spacing = 8
        textStack.translatesAutoresizingMaskIntoConstraints = false

        commentPreview.addSubview(commentAvatarView)
        commentPreview.addSubview(textStack)
        NSLayoutConstraint.activate([
            commentAvatarView.leadingAnchor.constraint(equalTo: commentPreview.leadingAnchor),
            commentAvatarView.topAnchor.constraint(equalTo: commentPreview.topAnchor),
            commentAvatarView.widthAnchor.constraint(equalToConstant: Layout.commentAvatarSize),
            commentAvatarView.heightAnchor.constraint(equalToConstant: Layout.commentAvatarSize),
            commentPreview.bottomAnchor.constraint(greaterThanOrEqualTo: commentAvatarView.bottomAnchor),

            textStack.leadingAnchor.constraint(equalTo: commentAvatarView.trailingAnchor, constant: PostDetailContentLayout.avatarSpacing),
            textStack.trailingAnchor.constraint(equalTo: commentPreview.trailingAnchor),
            textStack.topAnchor.constraint(equalTo: commentPreview.topAnchor),
            textStack.bottomAnchor.constraint(equalTo: commentPreview.bottomAnchor)
        ])
    }
}
