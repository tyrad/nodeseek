//
//  PostDetailViewController+ReplyBar.swift
//  nodeseek
//

import UIKit

/// 置底评论栏：写评论胶囊，正文滚到栏下方时淡出；往下读时收成右下角小圆钮，往回滚或回到顶部时再展开。
extension PostDetailViewController {
    func configureReplyBar() {
        replyButton.addTarget(self, action: #selector(replyButtonTapped), for: .touchUpInside)
        view.addSubview(replyBarFadeView)
        view.addSubview(replyBarView)

        if #available(iOS 26.0, *) {
            // 系统滚动边缘效果：正文滚到评论栏下方时模糊淡出，与顶部导航栏一致。
            let interaction = UIScrollEdgeElementContainerInteraction()
            interaction.scrollView = detailScrollView
            interaction.edge = .bottom
            replyBarView.addInteraction(interaction)
            replyBarFadeView.isEnabled = false
        }
    }

    func updateReplyBarForUserScroll(_ scrollView: UIScrollView) {
        let topY = -scrollView.adjustedContentInset.top
        let bottomY = max(topY, scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
        // 顶部、底部的回弹不算方向变化：越界部分按边界处理，到底回弹时评论栏保持原样。
        let offsetY = min(max(scrollView.contentOffset.y, topY), bottomY)
        let threshold = ReplyBarCollapseLayout.directionThreshold

        // 回到顶部附近时恢复完整评论栏；旁白模式下不收起，避免焦点目标变化。
        if offsetY <= topY + threshold || UIAccessibility.isVoiceOverRunning {
            replyBarScrollAnchorY = offsetY
            setReplyBarCollapsed(false, animated: true)
            return
        }

        let delta = offsetY - replyBarScrollAnchorY
        if replyBarView.isCollapsed {
            if delta <= -threshold {
                replyBarScrollAnchorY = offsetY
                setReplyBarCollapsed(false, animated: true)
            } else if delta > 0 {
                replyBarScrollAnchorY = offsetY
            }
        } else {
            if delta >= threshold {
                replyBarScrollAnchorY = offsetY
                setReplyBarCollapsed(true, animated: true)
            } else if delta < 0 {
                replyBarScrollAnchorY = offsetY
            }
        }
    }

    func setReplyBarCollapsed(_ collapsed: Bool, animated: Bool) {
        guard replyBarView.isCollapsed != collapsed else { return }
        replyBarView.setCollapsedLayout(collapsed)
        updatePageIndicatorPlacement(replyBarCollapsed: collapsed)
        guard animated, isViewLoaded, view.window != nil else {
            replyBarView.setExpandedContentVisible(collapsed == false)
            replyBarView.setCollapsedIconVisible(collapsed)
            view.layoutIfNeeded()
            return
        }
        if UIAccessibility.isReduceMotionEnabled {
            // 减弱动态效果时不做形变，只交叉淡入淡出。
            UIView.transition(with: replyBarView, duration: 0.2, options: [.transitionCrossDissolve, .allowUserInteraction]) {
                self.replyBarView.setExpandedContentVisible(collapsed == false)
                self.replyBarView.setCollapsedIconVisible(collapsed)
                self.view.layoutIfNeeded()
            }
            return
        }
        // 内容不跟着胶囊横移：要消失的一侧先快速淡出，要出现的一侧等形变过半再淡入。
        UIView.animate(withDuration: 0.12, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]) {
            if collapsed {
                self.replyBarView.setExpandedContentVisible(false)
            } else {
                self.replyBarView.setCollapsedIconVisible(false)
            }
        }
        UIView.animate(withDuration: 0.22, delay: 0.16, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]) {
            if collapsed {
                self.replyBarView.setCollapsedIconVisible(true)
            } else {
                self.replyBarView.setExpandedContentVisible(true)
            }
        }
        UIView.animate(
            withDuration: 0.5,
            delay: 0,
            usingSpringWithDamping: 0.86,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            self.view.layoutIfNeeded()
        }
    }
}

private enum ReplyBarCollapseLayout {
    /// 同方向累计滚动超过这个距离才切换形态，过滤手指抖动和惯性尾段。
    static let directionThreshold: CGFloat = 40
}

/// 评论栏容器：横向铺满，只有胶囊本身响应点按；收起后胶囊缩成贴右的圆钮。
final class PostDetailReplyBarView: UIView {
    let capsuleView = UIView()
    let button = UIButton(type: .custom)
    let titleLabel = UILabel()
    private let backgroundView = UIVisualEffectView()
    private let iconView = UIImageView()
    /// 收起后圆钮里的图标；与展开态的图标分开淡入淡出，避免图标横穿整条胶囊。
    private let collapsedIconView = UIImageView()
    private let collapsedIconGuide = UILayoutGuide()
    private(set) var isCollapsed = false

    private var expandedLeadingConstraint: NSLayoutConstraint!
    private var collapsedWidthConstraint: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "post-detail-reply-bar"
        isHidden = true
        translatesAutoresizingMaskIntoConstraints = false

        capsuleView.translatesAutoresizingMaskIntoConstraints = false
        capsuleView.clipsToBounds = false
        addSubview(capsuleView)

        if #available(iOS 26.0, *) {
            backgroundView.effect = UIGlassEffect(style: .regular)
        } else {
            backgroundView.effect = UIBlurEffect(style: .systemChromeMaterial)
            backgroundView.layer.borderWidth = 0.5
            backgroundView.layer.borderColor = UIColor.separator.cgColor
            capsuleView.layer.shadowColor = UIColor.black.cgColor
            capsuleView.layer.shadowOpacity = 0.08
            capsuleView.layer.shadowRadius = 12
            capsuleView.layer.shadowOffset = CGSize(width: 0, height: 4)
        }
        backgroundView.isUserInteractionEnabled = false
        backgroundView.clipsToBounds = true
        backgroundView.layer.cornerCurve = .continuous
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        capsuleView.addSubview(backgroundView)

        // 图标和文字放在玻璃的内容层里，跟随胶囊一起裁剪。
        let contentView = backgroundView.contentView
        iconView.image = UIImage(
            systemName: "bubble.left",
            withConfiguration: UIImage.SymbolConfiguration(textStyle: .body)
        )
        iconView.tintColor = .secondaryLabel
        iconView.contentMode = .center
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        contentView.addSubview(iconView)

        collapsedIconView.image = iconView.image
        collapsedIconView.tintColor = .label
        collapsedIconView.contentMode = .center
        collapsedIconView.alpha = 0
        collapsedIconView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(collapsedIconView)
        contentView.addLayoutGuide(collapsedIconGuide)

        titleLabel.font = .preferredFont(forTextStyle: .subheadline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .secondaryLabel
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.numberOfLines = 1
        titleLabel.text = DetailListStrings.text("reply-bar-placeholder")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        contentView.addSubview(titleLabel)

        button.accessibilityIdentifier = "post-detail-reply-button"
        button.accessibilityLabel = DetailListStrings.text("reply-bar-accessibility")
        button.isHidden = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(highlight), for: [.touchDown, .touchDragEnter])
        button.addTarget(self, action: #selector(unhighlight), for: [.touchUpInside, .touchUpOutside, .touchDragExit, .touchCancel])
        capsuleView.addSubview(button)

        expandedLeadingConstraint = capsuleView.leadingAnchor.constraint(equalTo: leadingAnchor)
        collapsedWidthConstraint = capsuleView.widthAnchor.constraint(equalTo: capsuleView.heightAnchor)
        // 收起时文字仍挂在图标后面，只是被裁掉，所以右侧约束允许被挤破。
        let titleTrailing = titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -16)
        titleTrailing.priority = .defaultHigh
        // 默认 44pt 高；大字号时由文字上下留白撑高，收起的圆钮随之变大。
        let preferredHeight = capsuleView.heightAnchor.constraint(equalToConstant: 44)
        // 优先级要高于文字右侧约束，否则收起时文字会通过“宽 = 高”把圆钮撑大。
        preferredHeight.priority = .required - 1

        NSLayoutConstraint.activate([
            capsuleView.trailingAnchor.constraint(equalTo: trailingAnchor),
            capsuleView.topAnchor.constraint(equalTo: topAnchor),
            capsuleView.bottomAnchor.constraint(equalTo: bottomAnchor),
            capsuleView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            preferredHeight,
            expandedLeadingConstraint,
            backgroundView.leadingAnchor.constraint(equalTo: capsuleView.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: capsuleView.trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: capsuleView.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: capsuleView.bottomAnchor),
            button.leadingAnchor.constraint(equalTo: capsuleView.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: capsuleView.trailingAnchor),
            button.topAnchor.constraint(equalTo: capsuleView.topAnchor),
            button.bottomAnchor.constraint(equalTo: capsuleView.bottomAnchor),
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            // 圆钮图标固定在胶囊最右侧那个正方形的中心，收起前后位置不变。
            collapsedIconGuide.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            collapsedIconGuide.topAnchor.constraint(equalTo: contentView.topAnchor),
            collapsedIconGuide.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            collapsedIconGuide.widthAnchor.constraint(equalTo: collapsedIconGuide.heightAnchor),
            collapsedIconView.centerXAnchor.constraint(equalTo: collapsedIconGuide.centerXAnchor),
            collapsedIconView.centerYAnchor.constraint(equalTo: collapsedIconGuide.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLabel.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 12),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -12),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleTrailing
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // 高度会随字号变化，圆角始终保持胶囊形。
        backgroundView.layer.cornerRadius = capsuleView.bounds.height / 2
    }

    /// 容器横向铺满，收起后胶囊之外的区域要把点按交还给下面的列表。
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        capsuleView.frame.contains(point)
    }

    /// 只切换约束，动画由页面统一驱动，让页码胶囊一起移动。
    func setCollapsedLayout(_ collapsed: Bool) {
        isCollapsed = collapsed
        if collapsed {
            expandedLeadingConstraint.isActive = false
            collapsedWidthConstraint.isActive = true
        } else {
            collapsedWidthConstraint.isActive = false
            expandedLeadingConstraint.isActive = true
        }
    }

    func setExpandedContentVisible(_ visible: Bool) {
        iconView.alpha = visible ? 1 : 0
        titleLabel.alpha = visible ? 1 : 0
    }

    func setCollapsedIconVisible(_ visible: Bool) {
        collapsedIconView.alpha = visible ? 1 : 0
    }

    func setDraft(_ draft: String?) {
        titleLabel.text = draft ?? DetailListStrings.text("reply-bar-placeholder")
        titleLabel.textColor = draft == nil ? .secondaryLabel : .label
    }

    @objc private func highlight() {
        UIView.animate(withDuration: 0.12, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.capsuleView.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
        }
    }

    @objc private func unhighlight() {
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.capsuleView.transform = .identity
        }
    }
}

enum PostDetailReplyBarStyle {
    /// iOS 26 用液态玻璃按钮，低版本用系统材质模糊加细描边。
    static func glassConfiguration() -> UIButton.Configuration {
        var configuration: UIButton.Configuration
        if #available(iOS 26.0, *) {
            configuration = .glass()
        } else {
            configuration = .plain()
            configuration.background.visualEffect = UIBlurEffect(style: .systemChromeMaterial)
            configuration.background.strokeColor = .separator
            configuration.background.strokeWidth = 0.5
        }
        configuration.cornerStyle = .capsule
        return configuration
    }
}

/// 评论栏背后从透明到页面背景色的渐隐遮罩，只在 iOS 26 以下使用。
final class PostDetailReplyBarFadeView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }

    /// iOS 26 改用系统滚动边缘效果时关闭。
    var isEnabled = true

    private var gradientLayer: CAGradientLayer { layer as! CAGradientLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isHidden = true
        translatesAutoresizingMaskIntoConstraints = false
        gradientLayer.locations = [0, 0.55]
        updateColors()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        updateColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateColors() {
        let color = UIColor.systemBackground.resolvedColor(with: traitCollection)
        gradientLayer.colors = [color.withAlphaComponent(0).cgColor, color.withAlphaComponent(0.94).cgColor]
    }
}
