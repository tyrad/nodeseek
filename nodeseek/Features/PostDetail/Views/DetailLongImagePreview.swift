//
//  DetailLongImagePreview.swift
//  nodeseek
//
//  Created by Claude on 2026/10/20.
//

import UIKit

/// 长图预览：图片按栏宽缩放后只展示顶部，右下角标注「长图」。
enum DetailLongImagePreview {
    private static let badgeTag = 0x4C4F4E47

    static func apply(to imageView: UIImageView, isLongImage: Bool) {
        updateContentsRect(of: imageView, isLongImage: isLongImage)
        updateBadge(in: imageView, isLongImage: isLongImage)
    }

    private static func updateContentsRect(of imageView: UIImageView, isLongImage: Bool) {
        let fullRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        guard isLongImage,
              let imageSize = imageView.image?.size,
              imageSize.width > 0,
              imageSize.height > 0,
              imageView.bounds.width > 0,
              imageView.bounds.height > 0 else {
            if imageView.layer.contentsRect != fullRect {
                imageView.layer.contentsRect = fullRect
            }
            return
        }
        // scaleAspectFill 只能居中裁剪，这里用 contentsRect 截取顶部区域，避免额外生成裁剪图。
        imageView.contentMode = .scaleToFill
        let scaledImageHeight = imageView.bounds.width * imageSize.height / imageSize.width
        let visibleRatio = min(1, imageView.bounds.height / scaledImageHeight)
        imageView.layer.contentsRect = CGRect(x: 0, y: 0, width: 1, height: visibleRatio)
    }

    private static func updateBadge(in imageView: UIImageView, isLongImage: Bool) {
        let existingBadge = imageView.viewWithTag(badgeTag) as? UILabel
        guard isLongImage else {
            existingBadge?.removeFromSuperview()
            return
        }

        let badge = existingBadge ?? makeBadge()
        if badge.superview == nil {
            imageView.addSubview(badge)
        }
        let size = badge.intrinsicContentSize
        let inset: CGFloat = 6
        badge.frame = CGRect(
            x: imageView.bounds.width - size.width - inset,
            y: imageView.bounds.height - size.height - inset,
            width: size.width,
            height: size.height
        )
    }

    private static func makeBadge() -> UILabel {
        let label = DetailLongImageBadgeLabel()
        label.tag = badgeTag
        label.text = "长图"
        label.font = .systemFont(ofSize: 11, weight: .medium)
        // 角标叠在图片上，深浅模式都用半透明黑底白字保证可读。
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        label.layer.cornerRadius = 4
        label.layer.masksToBounds = true
        label.isUserInteractionEnabled = false
        return label
    }
}

private final class DetailLongImageBadgeLabel: UILabel {
    private let contentInsets = UIEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: ceil(size.width + contentInsets.left + contentInsets.right),
            height: ceil(size.height + contentInsets.top + contentInsets.bottom)
        )
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: contentInsets))
    }
}
