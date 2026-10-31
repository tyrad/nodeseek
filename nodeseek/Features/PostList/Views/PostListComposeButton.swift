//
//  PostListComposeButton.swift
//  nodeseek
//

import UIKit

/// 多 Tab 模式首页的悬浮发帖按钮：文字色圆底 + 背景色图标，深浅色自动反色。
final class PostListComposeButton: UIButton {
    override init(frame: CGRect) {
        super.init(frame: frame)
        var configuration = UIButton.Configuration.filled()
        configuration.baseBackgroundColor = .label
        configuration.baseForegroundColor = .systemBackground
        configuration.cornerStyle = .capsule
        configuration.image = UIImage(
            systemName: "square.and.pencil",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        )
        self.configuration = configuration
        accessibilityIdentifier = "post-list-compose-button"
        accessibilityLabel = "发帖"
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.18
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: 4)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // 指定阴影路径，避免滚动时离屏计算阴影
        layer.shadowPath = UIBezierPath(ovalIn: bounds).cgPath
    }
}
