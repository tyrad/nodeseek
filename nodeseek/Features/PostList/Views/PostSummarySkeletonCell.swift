//
//  PostSummarySkeletonCell.swift
//  nodeseek
//
//  Created by Codex on 2026/10/31.
//

import UIKit

final class PostSummarySkeletonCell: UITableViewCell {
    static let reuseIdentifier = "PostSummarySkeletonCell"

    private enum Layout {
        static let verticalSpacing: CGFloat = 8
        static let titleHeight: CGFloat = 18
        static let metaHeight: CGFloat = 13
        static let contentInset = UIEdgeInsets(
            top: PostListCellStyle.Layout.verticalContentInset,
            left: 16,
            bottom: PostListCellStyle.Layout.verticalContentInset,
            right: 12
        )
    }

    private let avatarPlaceholder = UIView()
    private let titlePlaceholder = UIView()
    private let metaPlaceholder1 = UIView()
    private let metaPlaceholder2 = UIView()

    private var placeholderViews: [UIView] {
        [avatarPlaceholder, titlePlaceholder, metaPlaceholder1, metaPlaceholder2]
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stopPulseAnimation()
        } else {
            startPulseAnimation()
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        startPulseAnimation()
    }

    private func setupUI() {
        selectionStyle = .none
        backgroundColor = .clear
        separatorInset = .zero

        let metaStack = UIStackView(arrangedSubviews: [metaPlaceholder1, metaPlaceholder2])
        metaStack.axis = .horizontal
        metaStack.spacing = 8
        metaStack.alignment = .center

        let textStack = UIStackView(arrangedSubviews: [titlePlaceholder, metaStack])
        textStack.axis = .vertical
        textStack.spacing = Layout.verticalSpacing
        textStack.alignment = .leading
        textStack.translatesAutoresizingMaskIntoConstraints = false

        avatarPlaceholder.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(avatarPlaceholder)
        contentView.addSubview(textStack)

        avatarPlaceholder.layer.cornerRadius = PostListCellStyle.Avatar.cornerRadius
        titlePlaceholder.layer.cornerRadius = 5
        metaPlaceholder1.layer.cornerRadius = 4
        metaPlaceholder2.layer.cornerRadius = 4
        for view in placeholderViews {
            view.backgroundColor = .systemGray5
            view.clipsToBounds = true
        }

        let inset = Layout.contentInset
        NSLayoutConstraint.activate([
            avatarPlaceholder.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: inset.left),
            avatarPlaceholder.topAnchor.constraint(equalTo: contentView.topAnchor, constant: inset.top),
            avatarPlaceholder.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -inset.bottom),
            avatarPlaceholder.widthAnchor.constraint(equalToConstant: PostListCellStyle.Avatar.skeletonSize),
            avatarPlaceholder.heightAnchor.constraint(equalToConstant: PostListCellStyle.Avatar.skeletonSize),

            textStack.leadingAnchor.constraint(
                equalTo: avatarPlaceholder.trailingAnchor,
                constant: PostListCellStyle.Layout.horizontalSpacing
            ),
            textStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -inset.right),
            textStack.centerYAnchor.constraint(equalTo: avatarPlaceholder.centerYAnchor),

            titlePlaceholder.heightAnchor.constraint(equalToConstant: Layout.titleHeight),
            titlePlaceholder.widthAnchor.constraint(equalTo: textStack.widthAnchor, multiplier: 0.78),
            metaPlaceholder1.heightAnchor.constraint(equalToConstant: Layout.metaHeight),
            metaPlaceholder1.widthAnchor.constraint(equalTo: textStack.widthAnchor, multiplier: 0.32),
            metaPlaceholder2.heightAnchor.constraint(equalToConstant: Layout.metaHeight),
            metaPlaceholder2.widthAnchor.constraint(equalTo: textStack.widthAnchor, multiplier: 0.22)
        ])
    }

    private func startPulseAnimation() {
        for view in placeholderViews {
            guard view.layer.animation(forKey: "skeleton_pulse") == nil else { continue }
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = 1.0
            animation.toValue = 0.45
            animation.duration = 0.8
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            view.layer.add(animation, forKey: "skeleton_pulse")
        }
    }

    private func stopPulseAnimation() {
        for view in placeholderViews {
            view.layer.removeAnimation(forKey: "skeleton_pulse")
        }
    }
}
