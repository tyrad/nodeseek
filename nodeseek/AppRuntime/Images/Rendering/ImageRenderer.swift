//
//  ImageRenderer.swift
//  nodeseek
//
//  Created by Codex on 2026/5/9.
//

import Foundation
import ImageIO
import UIKit

enum ImageRenderer {
    private enum Limits {
        static let maxSVGPixelSide: CGFloat = 2048
        static let svgFallbackSize = CGSize(width: 320, height: 180)
    }

    static func image(
        data: Data,
        mimeType: String?,
        maxPixelSize: Int? = nil
    ) -> UIImage? {
        if shouldRenderSVG(data: data, mimeType: mimeType) {
            return renderSVGImage(data: data, maxPixelSize: maxPixelSize)
        }

        if let maxPixelSize, let image = downsampledImage(data: data, maxPixelSize: maxPixelSize) {
            return image
        }

        return UIImage(data: data)
    }

    static func pixelSize(data: Data, mimeType: String?) -> CGSize? {
        if shouldRenderSVG(data: data, mimeType: mimeType) {
            return renderSVGImage(data: data)?.size
        }

        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber
        else {
            return nil
        }

        return CGSize(width: CGFloat(width.doubleValue), height: CGFloat(height.doubleValue))
    }

    static func downsampledImage(data: Data, maxPixelSize: Int) -> UIImage? {
        guard maxPixelSize > 0 else { return nil }

        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }

        // 在解码阶段直接生成目标尺寸缩略图，避免先把大图完整解码进内存再缩放。
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else {
            return nil
        }

        return UIImage(cgImage: image, scale: 1, orientation: .up)
    }

    private static func shouldRenderSVG(data: Data, mimeType: String?) -> Bool {
        if mimeType?.lowercased().contains("svg") == true {
            return true
        }
        return SVGContentInspector.looksLikeSVG(data)
    }

    private static func renderSVGImage(data: Data, maxPixelSize: Int? = nil) -> UIImage? {
        guard let size = SVGImageRenderer.imageSize(
            from: data,
            fallbackSize: Limits.svgFallbackSize,
            maxPixelSide: Limits.maxSVGPixelSide
        ) else { return nil }
        return SVGImageRenderer.image(from: data, size: normalizedSize(size, maxPixelSize: maxPixelSize))
    }

    private static func normalizedSize(_ size: CGSize, maxPixelSize: Int?) -> CGSize {
        guard let maxPixelSize, maxPixelSize > 0 else { return size }
        let maxSide = max(size.width, size.height)
        guard maxSide > CGFloat(maxPixelSize) else { return size }
        let scale = CGFloat(maxPixelSize) / maxSide
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}
