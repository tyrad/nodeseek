//
//  DetailImageLayout.swift
//  nodeseek
//
//  Created by Codex on 2026/4/28.
//

import CoreGraphics

enum DetailImageDisplayMode {
    case thumbnailCrop
    case aspectFit
}

struct DetailImagePresentation {
    let size: CGSize
    let mode: DetailImageDisplayMode

    var targetPointSide: CGFloat {
        max(size.width, size.height)
    }
}

enum DetailImageLayout {
    static let fixedStickerWidth: CGFloat = 65
    static let maxImageHeight: CGFloat = 420
    private static let extremeAspectRatio: CGFloat = 1.8

    static func fixedNormalImageSize(maxWidth: CGFloat) -> CGSize {
        guard maxWidth > 0 else { return .zero }
        let side = max(1, floor(maxWidth / 2))
        return CGSize(width: side, height: side)
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
        maxHeight: CGFloat?,
        isSticker: Bool
    ) -> CGSize {
        guard maxWidth > 0 else { return .zero }

        if isSticker {
            let side = min(maxWidth, fixedStickerWidth)
            return CGSize(width: max(1, side), height: max(1, side))
        }

        return fixedNormalImageSize(maxWidth: maxWidth)
    }

    static func presentation(
        for originalSize: CGSize,
        maxWidth: CGFloat,
        isSticker: Bool
    ) -> DetailImagePresentation {
        guard maxWidth > 0 else {
            return DetailImagePresentation(size: .zero, mode: .aspectFit)
        }

        if isSticker {
            let size: CGSize
            if originalSize.width > 0, originalSize.height > 0 {
                size = scaledSize(
                    for: originalSize,
                    maxWidth: min(maxWidth, fixedStickerWidth),
                    maxHeight: nil
                )
            } else {
                size = placeholderSize(maxWidth: maxWidth, maxHeight: nil, isSticker: true)
            }
            return DetailImagePresentation(size: size, mode: .aspectFit)
        }

        guard originalSize.width > 0, originalSize.height > 0 else {
            return DetailImagePresentation(size: fixedNormalImageSize(maxWidth: maxWidth), mode: .thumbnailCrop)
        }

        let aspectRatio = originalSize.width / originalSize.height
        let isExtremeRatio = aspectRatio >= extremeAspectRatio || aspectRatio <= 1 / extremeAspectRatio
        guard isExtremeRatio else {
            return DetailImagePresentation(size: fixedNormalImageSize(maxWidth: maxWidth), mode: .thumbnailCrop)
        }

        return DetailImagePresentation(
            size: scaledSize(for: originalSize, maxWidth: maxWidth, maxHeight: maxImageHeight),
            mode: .aspectFit
        )
    }

    static func allowsInlineAnimation(
        for originalSize: CGSize,
        maxWidth: CGFloat,
        isSticker: Bool
    ) -> Bool {
        if isSticker {
            return true
        }

        return presentation(
            for: originalSize,
            maxWidth: maxWidth,
            isSticker: false
        ).mode == .thumbnailCrop
    }
}
