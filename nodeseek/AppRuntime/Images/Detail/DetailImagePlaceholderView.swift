import UIKit

/// 加载与失败共用占位，独立于图片视图，等待行高更新时也保留灰底。
final class DetailImagePlaceholderView: UIView {
    private let iconView = UIImageView(image: UIImage(systemName: "exclamationmark.triangle"))
    private let label = UILabel()
    private(set) var hasFailed = false

    nonisolated static func failureSize(maxWidth: CGFloat) -> CGSize {
        CGSize(width: min(max(1, maxWidth), 240), height: 44)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemFill
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityIdentifier = "detail-image-placeholder"
        iconView.tintColor = .secondaryLabel
        iconView.contentMode = .scaleAspectFit
        label.text = "图片加载失败"
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        addSubview(iconView)
        addSubview(label)
        showFailure(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func showFailure(_ failed: Bool) {
        hasFailed = failed
        accessibilityLabel = failed ? "图片加载失败" : "图片加载中"
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        iconView.isHidden = !hasFailed
        label.isHidden = !hasFailed || bounds.width < 130
        let textWidth = label.isHidden ? 0 : label.intrinsicContentSize.width
        let width = 18 + (textWidth > 0 ? 6 + textWidth : 0)
        let x = max(0, (bounds.width - width) / 2)
        iconView.frame = CGRect(x: x, y: (bounds.height - 18) / 2, width: 18, height: 18)
        label.frame = CGRect(x: x + 24, y: (bounds.height - 20) / 2, width: textWidth, height: 20)
    }
}
