//
//  DetailThumbnailBuilder.swift
//  nodeseek
//
//  Created by Codex on 2026/5/10.
//

import UIKit

enum DetailThumbnailBuilder {
    static func makeBoundedThumbnail(from image: UIImage, maxBytes: Int) -> DetailThumbnailResult {
        let byteLimit = max(maxBytes, 1)
        var workingImage = image
        var lastData = image.jpegData(compressionQuality: DetailImageLimits.thumbnailMinimumQuality) ?? DetailImageFallback.pngData
        var lastQuality = DetailImageLimits.thumbnailMinimumQuality

        for _ in 0 ..< 8 {
            var quality = DetailImageLimits.thumbnailInitialQuality
            while quality >= DetailImageLimits.thumbnailMinimumQuality {
                if let data = workingImage.jpegData(compressionQuality: quality) {
                    lastData = data
                    lastQuality = quality
                    if data.count <= byteLimit {
                        return DetailThumbnailResult(
                            cacheData: data,
                            image: workingImage,
                            quality: quality,
                            byteCount: data.count
                        )
                    }
                }
                quality -= 0.09
            }

            let currentMaxSide = max(workingImage.size.width, workingImage.size.height)
            guard currentMaxSide > DetailImageLimits.thumbnailMinimumPixelSide else {
                break
            }

            let ratio = sqrt(CGFloat(byteLimit) / CGFloat(max(lastData.count, 1)))
            let resizeRatio = min(max(ratio * 0.9, 0.5), 0.85)
            guard let resizedImage = resizedImage(workingImage, scale: resizeRatio) else {
                break
            }
            workingImage = resizedImage
        }

        return DetailThumbnailResult(
            cacheData: nil,
            image: workingImage,
            quality: lastQuality,
            byteCount: lastData.count
        )
    }

    private static func resizedImage(_ image: UIImage, scale: CGFloat) -> UIImage? {
        guard scale > 0, scale < 1 else { return image }
        let size = CGSize(
            width: max(1, floor(image.size.width * scale)),
            height: max(1, floor(image.size.height * scale))
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
