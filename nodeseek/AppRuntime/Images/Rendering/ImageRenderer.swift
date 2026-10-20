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

    static func boundedImage(_ image: UIImage, maxPixelSize: Int) -> UIImage {
        let maxSide = max(image.size.width, image.size.height)
        guard maxPixelSize > 0, maxSide > CGFloat(maxPixelSize) else { return image }
        let ratio = CGFloat(maxPixelSize) / maxSide
        let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    static func pixelSize(data: Data, mimeType: String?) -> CGSize? {
        if shouldRenderSVG(data: data, mimeType: mimeType) {
            return renderSVGImage(data: data)?.size
        }

        return rasterPixelSize(data: data)
    }

    static func rasterPixelSize(data: Data) -> CGSize? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber
        else {
            return nil
        }

        // 元数据尺寸与自动旋转后的缩略图方向保持一致。
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        if (5 ... 8).contains(orientation) {
            return CGSize(width: CGFloat(height.doubleValue), height: CGFloat(width.doubleValue))
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

    static func shouldRenderSVG(data: Data, mimeType: String?) -> Bool {
        if mimeType?.lowercased().contains("svg") == true {
            return true
        }
        return SVGContentInspector.looksLikeSVG(data)
    }

    private static func renderSVGImage(data: Data, maxPixelSize: Int? = nil) -> UIImage? {
        SVGImageRenderer.image(
            from: data,
            fallbackSize: Limits.svgFallbackSize,
            maxPixelSide: min(Limits.maxSVGPixelSide, maxPixelSize.map(CGFloat.init) ?? Limits.maxSVGPixelSide)
        )
    }
}
