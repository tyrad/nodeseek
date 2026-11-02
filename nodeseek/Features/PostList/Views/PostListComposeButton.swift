//
//  PostListComposeButton.swift
//  nodeseek
//

import UIKit

/// 多 Tab 模式首页的悬浮发帖按钮：玻璃胶囊 + 图标与“发帖”文字。
/// iOS 26 起用系统液态玻璃，与底部 Tab 栏同一质感；更早系统用模糊材质模拟。
final class PostListComposeButton: UIButton {
    static let height: CGFloat = 44

    private var fallbackBackground: UIVisualEffectView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        var configuration: UIButton.Configuration
        if #available(iOS 26.0, *) {
            configuration = .glass()
        } else {
            configuration = .plain()
            installFallbackBackground()
        }
        configuration.cornerStyle = .capsule
        configuration.baseForegroundColor = .label
        configuration.image = UIImage(
            systemName: "square.and.pencil",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        )
        configuration.imagePadding = 6
        configuration.title = "发帖"
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 15, weight: .semibold)
            return outgoing
        }
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 18)
        self.configuration = configuration
        accessibilityIdentifier = "post-list-compose-button"
        accessibilityLabel = "发帖"
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let fallbackBackground else { return }
        sendSubviewToBack(fallbackBackground)
        fallbackBackground.layer.cornerRadius = bounds.height / 2
        // 指定阴影路径，避免滚动时离屏计算阴影
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: bounds.height / 2).cgPath
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateFallbackBorderColor()
    }

    /// iOS 15–18：厚模糊材质 + 细描边 + 柔和阴影。
    private func installFallbackBackground() {
        let background = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
        background.isUserInteractionEnabled = false
        background.clipsToBounds = true
        background.layer.cornerCurve = .continuous
        background.layer.borderWidth = 1 / UIScreen.main.scale
        background.frame = bounds
        background.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        insertSubview(background, at: 0)
        fallbackBackground = background
        updateFallbackBorderColor()

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 4)
    }

    private func updateFallbackBorderColor() {
        // layer 颜色不会自动跟随深浅色
        fallbackBackground?.layer.borderColor = UIColor.separator.resolvedColor(with: traitCollection).cgColor
    }
}
