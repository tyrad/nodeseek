//
//  DetailImageLayout.swift
//  nodeseek
//
//  Created by Codex on 2026/4/28.
//

import CoreGraphics

nonisolated enum DetailImageDisplayMode: Equatable, Sendable {
    case thumbnailCrop
    case aspectFit
    /// 长图预览：从图片顶部开始显示，右下角标注「长图」。
    case topCrop
}

nonisolated enum DetailImageKind: Equatable, Sendable {
    case normal
    case sticker
    case report
}

nonisolated struct DetailImagePresentation: Equatable, Sendable {
    let size: CGSize
    let mode: DetailImageDisplayMode

    var targetPointSide: CGFloat {
        max(size.width, size.height)
    }
}

nonisolated enum DetailImageLayout {
    static let fixedStickerHeight: CGFloat = 65
    static let maxImageHeight: CGFloat = 420
    private static let extremeAspectRatio: CGFloat = 1.8
    /// 普通图加载前的占位高宽比，接近常见图片的平均高度，减少加载后的高度跳动。
    private static let normalPlaceholderHeightRatio: CGFloat = 0.75
    /// 按高度上限缩小后宽度不足栏宽这个比例时，视为长图，避免窄条看不清内容。
    private static let longImageMinWidthRatio: CGFloat = 0.4
    private static let reportPlaceholderAspectRatio: CGFloat = 74 * 0.6 / 47

    static func fixedNormalImageSize(maxWidth: CGFloat) -> CGSize {
        guard maxWidth > 0 else { return .zero }
        let side = max(1, floor(maxWidth / 2))
        return CGSize(width: side, height: side)
    }

    static func normalPlaceholderSize(maxWidth: CGFloat) -> CGSize {
        guard maxWidth > 0 else { return .zero }
        return CGSize(width: maxWidth, height: max(1, floor(maxWidth * normalPlaceholderHeightRatio)))
    }

    static func reportPlaceholderSize(maxWidth: CGFloat) -> CGSize {
        guard maxWidth > 0 else { return .zero }
        return CGSize(width: maxWidth, height: ceil(maxWidth / reportPlaceholderAspectRatio))
    }

    static func scaledSize(
        for size: CGSize,
        maxWidth: CGFloat,
        maxHeight: CGFloat?
    ) -> CGSize {
        guard size.width > 0, size.height > 0, maxWidth > 0 else { return size }

        var scale = min(1, maxWidth / size.width)
        if let maxHeight, maxHeight > 0 {
            scale = min(scale, maxHeight / size.height)
        }

        return CGSize(
            width: max(1, size.width * scale),
            height: max(1, size.height * scale)
        )
    }

    static func placeholderSize(
        maxWidth: CGFloat,
        kind: DetailImageKind
    ) -> CGSize {
        guard maxWidth > 0 else { return .zero }

        if kind == .sticker {
            return CGSize(
                width: max(1, min(maxWidth, fixedStickerHeight)),
                height: fixedStickerHeight
            )
        }

        if kind == .report {
            return reportPlaceholderSize(maxWidth: maxWidth)
        }

        return normalPlaceholderSize(maxWidth: maxWidth)
    }

    static func presentation(
        for originalSize: CGSize,
        maxWidth: CGFloat,
        kind: DetailImageKind
    ) -> DetailImagePresentation {
        guard maxWidth > 0 else {
            return DetailImagePresentation(size: .zero, mode: .aspectFit)
        }

        switch kind {
        case .sticker:
            return stickerPresentation(for: originalSize, maxWidth: maxWidth)
        case .normal:
            return normalPresentation(for: originalSize, maxWidth: maxWidth)
        case .report:
            return reportPresentation(for: originalSize, maxWidth: maxWidth)
        }
    }

    private static func stickerPresentation(for originalSize: CGSize, maxWidth: CGFloat) -> DetailImagePresentation {
        let size: CGSize
        if originalSize.width > 0, originalSize.height > 0 {
            let scaledWidth = originalSize.width * fixedStickerHeight / originalSize.height
            size = CGSize(
                width: max(1, min(maxWidth, scaledWidth)),
                height: fixedStickerHeight
            )
        } else {
            size = placeholderSize(maxWidth: maxWidth, kind: .sticker)
        }
        return DetailImagePresentation(size: size, mode: .aspectFit)
    }

    private static func normalPresentation(for originalSize: CGSize, maxWidth: CGFloat) -> DetailImagePresentation {
        guard originalSize.width > 0, originalSize.height > 0 else {
            return DetailImagePresentation(size: normalPlaceholderSize(maxWidth: maxWidth), mode: .thumbnailCrop)
        }

        // 按原比例展示，不放大、不裁剪；高度超出上限时按高度等比缩小。
        let maxHeight = normalMaxHeight(maxWidth: maxWidth)
        let widthFitSize = scaledSize(for: originalSize, maxWidth: maxWidth, maxHeight: nil)
        let fitSize = scaledSize(for: originalSize, maxWidth: maxWidth, maxHeight: maxHeight)
        let isHeightLimited = widthFitSize.height >= maxHeight
        guard isHeightLimited, fitSize.width < maxWidth * longImageMinWidthRatio else {
            return DetailImagePresentation(size: fitSize, mode: .aspectFit)
        }

        // 长图只展示顶部，宽度沿用原图宽度上限，避免小图被放大。
        let previewWidth = min(maxWidth, originalSize.width)
        return DetailImagePresentation(
            size: CGSize(width: previewWidth, height: max(1, floor(previewWidth * normalPlaceholderHeightRatio))),
            mode: .topCrop
        )
    }

    private static func reportPresentation(for originalSize: CGSize, maxWidth: CGFloat) -> DetailImagePresentation {
        guard originalSize.width > 0, originalSize.height > 0 else {
            return DetailImagePresentation(size: reportPlaceholderSize(maxWidth: maxWidth), mode: .aspectFit)
        }
        // 报告缩略图仅影响清晰度，显示尺寸始终由栏宽和宽高比决定。
        return DetailImagePresentation(
            size: CGSize(width: maxWidth, height: max(1, maxWidth * (originalSize.height / originalSize.width))),
            mode: .aspectFit
        )
    }

    private static func normalMaxHeight(maxWidth: CGFloat) -> CGFloat {
        min(maxWidth, maxImageHeight)
    }

    static func allowsInlineAnimation(
        for originalSize: CGSize,
        maxWidth: CGFloat,
        kind: DetailImageKind
    ) -> Bool {
        if kind == .sticker {
            return true
        }

        guard originalSize.width > 0, originalSize.height > 0 else { return false }
        return originalSize.width / originalSize.height > 1 / extremeAspectRatio
    }
}
