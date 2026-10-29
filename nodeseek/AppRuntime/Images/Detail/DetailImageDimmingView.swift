import UIKit

/// 只改变显示效果，不处理图片像素，避免影响动图、缓存和原图导出。
final class DetailImageDimmingView: UIView {
    private let settings: DetailImageDimmingSettings

    @discardableResult
    static func install(on imageView: UIImageView, settings: DetailImageDimmingSettings = .shared) -> DetailImageDimmingView {
        if let existing = imageView.subviews.compactMap({ $0 as? DetailImageDimmingView }).first {
            return existing
        }
        let overlay = DetailImageDimmingView(settings: settings)
        overlay.frame = imageView.bounds
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // 图片位于图层内容中；遮罩置于子视图底层，让占位和长图角标保持原有对比度。
        imageView.insertSubview(overlay, at: 0)
        return overlay
    }

    init(settings: DetailImageDimmingSettings) {
        self.settings = settings
        super.init(frame: .zero)
        isOpaque = false
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(updateAppearance),
            name: DetailImageDimmingSettings.didChangeNotification, object: settings
        )
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func updateAppearance() {
        let enabled = settings.isEnabled
        // 由 UIKit 在首次显示和主题切换时解析颜色，避免等待主题回调导致亮图闪现。
        // 黑色是压暗图片的混合色，浅色模式和关闭状态使用全透明。
        backgroundColor = UIColor { traits in
            UIColor.black.withAlphaComponent(enabled && traits.userInterfaceStyle == .dark ? 0.35 : 0)
        }
    }
}
