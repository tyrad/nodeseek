import UIKit

/// 仅调整显示亮度，保持头像原图与缓存不变。
final class AvatarDimOverlayView: UIView {
    static func install(on imageView: UIImageView) {
        if let existing = imageView.subviews.first(where: { $0 is AvatarDimOverlayView }) {
            imageView.bringSubviewToFront(existing)
            return
        }
        let overlay = AvatarDimOverlayView(frame: imageView.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.backgroundColor = UIColor(named: "AvatarDimOverlay")
        overlay.isUserInteractionEnabled = false
        overlay.isAccessibilityElement = false
        imageView.addSubview(overlay)
    }
}
