//
//  SearchHistoryTagCloudView.swift
//  nodeseek
//
//  Created by Codex on 2026/5/3.
//

import UIKit

final class SearchHistoryTagCloudView: UIView {
    private let horizontalSpacing: CGFloat = 8
    private let verticalSpacing: CGFloat = 8
    private var buttons: [UIButton] = []
    private var lastLayoutWidth: CGFloat = 0

    /// 收起时只排一行，放不下的标签隐藏，行尾显示「展开」。
    var isCollapsed = false {
        didSet {
            guard oldValue != isCollapsed else { return }
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
    }

    var onExpand: (() -> Void)?

    private lazy var expandButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.title = "展开"
        configuration.image = UIImage(
            systemName: "chevron.down",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        )
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 2
        configuration.baseForegroundColor = .secondaryLabel
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 0)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 13, weight: .regular)
            return outgoing
        }

        let button = UIButton(type: .system)
        button.configuration = configuration
        button.isHidden = true
        button.accessibilityLabel = "展开搜索历史"
        button.accessibilityIdentifier = "search-history-expand-button"
        button.addAction(UIAction { [weak self] _ in
            self?.onExpand?()
        }, for: .touchUpInside)
        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(expandButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setButtons(_ buttons: [UIButton]) {
        self.buttons.forEach { $0.removeFromSuperview() }
        self.buttons = buttons
        buttons.forEach { insertSubview($0, belowSubview: expandButton) }
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if abs(bounds.width - lastLayoutWidth) > 0.5 {
            lastLayoutWidth = bounds.width
            invalidateIntrinsicContentSize()
        }
        _ = layoutButtons(width: bounds.width, applyFrames: true)
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: layoutHeight(for: bounds.width))
    }

    override func systemLayoutSizeFitting(
        _ targetSize: CGSize,
        withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
        verticalFittingPriority: UILayoutPriority
    ) -> CGSize {
        let width = targetSize.width > 0 ? targetSize.width : bounds.width
        return CGSize(width: targetSize.width, height: layoutHeight(for: width))
    }

    private func layoutHeight(for width: CGFloat) -> CGFloat {
        guard width > 0 else {
            return buttons.map { $0.sizeThatFits(UIView.layoutFittingCompressedSize).height }.max() ?? 0
        }
        return layoutButtons(width: width, applyFrames: false)
    }

    private func buttonSize(_ button: UIButton, availableWidth: CGFloat) -> CGSize {
        let fittingSize = button.sizeThatFits(
            CGSize(width: availableWidth, height: UIView.layoutFittingCompressedSize.height)
        )
        return CGSize(width: min(ceil(fittingSize.width), availableWidth), height: ceil(fittingSize.height))
    }

    private func layoutButtons(width: CGFloat, applyFrames: Bool) -> CGFloat {
        guard !buttons.isEmpty else {
            if applyFrames { expandButton.isHidden = true }
            return 0
        }

        let availableWidth = max(width, 1)
        if isCollapsed {
            return layoutSingleRow(width: availableWidth, applyFrames: applyFrames)
        }

        if applyFrames { expandButton.isHidden = true }
        var origin = CGPoint.zero
        var rowHeight: CGFloat = 0

        for button in buttons {
            let size = buttonSize(button, availableWidth: availableWidth)
            if origin.x > 0, origin.x + size.width > availableWidth {
                origin.x = 0
                origin.y += rowHeight + verticalSpacing
                rowHeight = 0
            }

            if applyFrames {
                button.isHidden = false
                button.frame = CGRect(origin: origin, size: size)
            }

            origin.x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }

        return origin.y + rowHeight
    }

    /// 单行排布：全部放得下就不显示「展开」；放不下时给「展开」留出位置，
    /// 只保留完整可见的标签，避免出现被截断一半的标签。
    private func layoutSingleRow(width: CGFloat, applyFrames: Bool) -> CGFloat {
        let sizes = buttons.map { buttonSize($0, availableWidth: width) }
        let rowHeight = sizes.map(\.height).max() ?? 0
        let totalWidth = sizes.map(\.width).reduce(0, +) + horizontalSpacing * CGFloat(sizes.count - 1)
        let overflows = totalWidth > width
        let expandSize = expandButton.sizeThatFits(UIView.layoutFittingCompressedSize)
        let limit = overflows ? width - ceil(expandSize.width) - horizontalSpacing : width
        let height = overflows ? max(rowHeight, ceil(expandSize.height)) : rowHeight
        guard applyFrames else { return height }

        var x: CGFloat = 0
        for (button, size) in zip(buttons, sizes) {
            // 第一个标签过长时压缩到可用宽度，保证至少展示一条
            let fits = x + size.width <= limit
            let isFirst = x == 0
            button.isHidden = !(fits || isFirst)
            guard !button.isHidden else { continue }
            let itemWidth = fits ? size.width : max(limit, 0)
            button.frame = CGRect(x: x, y: (height - size.height) / 2, width: itemWidth, height: size.height)
            x += itemWidth + horizontalSpacing
            if !fits { x = .greatestFiniteMagnitude }
        }

        expandButton.isHidden = !overflows
        if overflows {
            expandButton.frame = CGRect(
                x: width - ceil(expandSize.width),
                y: (height - ceil(expandSize.height)) / 2,
                width: ceil(expandSize.width),
                height: ceil(expandSize.height)
            )
        }
        return height
    }
}

/// 搜索历史标签：胶囊形，关键词后跟分类小标签。
final class SearchHistoryChipButton: UIButton {
    private let tagBackgroundView = UIView()
    private let tagLabel = UILabel()
    private let hasTag: Bool
    private let tagHorizontalPadding: CGFloat = 5
    private let tagSpacing: CGFloat = 6
    private let trailingInset: CGFloat = 8

    /// tag 为空时只显示关键词（帖子搜索「全部」分类不再重复标注）。
    init(title: String, tag: String?) {
        hasTag = tag != nil
        super.init(frame: .zero)

        var trailing: CGFloat = 14
        if let tag {
            tagLabel.text = tag
            tagLabel.font = .systemFont(ofSize: 11, weight: .medium)
            tagLabel.textAlignment = .center
            tagLabel.textColor = .secondaryLabel
            tagBackgroundView.backgroundColor = .systemBackground
            tagBackgroundView.layer.cornerRadius = 8
            tagBackgroundView.layer.cornerCurve = .continuous
            tagBackgroundView.isUserInteractionEnabled = false
            tagBackgroundView.addSubview(tagLabel)
            addSubview(tagBackgroundView)
            let tagWidth = ceil(tagLabel.intrinsicContentSize.width) + tagHorizontalPadding * 2
            trailing = trailingInset + tagWidth + tagSpacing
        }

        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.baseForegroundColor = .label
        configuration.background.backgroundColor = .tertiarySystemFill
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 14, bottom: 7, trailing: trailing)
        configuration.titleLineBreakMode = .byTruncatingTail
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 14, weight: .regular)
            return outgoing
        }
        self.configuration = configuration
        contentHorizontalAlignment = .leading
        accessibilityLabel = tag.map { "\(title)，\($0)" } ?? title
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard hasTag else { return }
        let labelSize = tagLabel.intrinsicContentSize
        let width = ceil(labelSize.width) + tagHorizontalPadding * 2
        let height = ceil(labelSize.height) + 3
        tagBackgroundView.frame = CGRect(
            x: bounds.width - trailingInset - width,
            y: (bounds.height - height) / 2,
            width: width,
            height: height
        )
        tagLabel.frame = tagBackgroundView.bounds
        bringSubviewToFront(tagBackgroundView)
    }
}
