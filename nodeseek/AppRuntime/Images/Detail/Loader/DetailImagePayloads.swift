//
//  DetailImagePayloads.swift
//  nodeseek
//
//  Created by Codex on 2026/5/10.
//

import Foundation
import UIKit

struct DetailOriginalFilePayload: Equatable {
    let data: Data
    let mimeType: String?
    let suggestedFileExtension: String
}

enum DetailOriginalFileError: Error, Equatable {
    case unavailable
}

struct DetailInlineImageResult {
    let image: UIImage?
    let resolvedKind: DetailImageKind?
    // 布局使用原图尺寸，不能把降采样后的像素尺寸当作小图。
    var originalSize: CGSize? = nil
}

enum DetailImageLoadSource: String {
    case dataURL
    case disk
    case network
}

struct DetailDecodedImagePayload {
    let data: Data
    let mimeType: String?
    let image: UIImage
    let isFallback: Bool
}

struct DetailOriginalDataPayload {
    let data: Data
    let mimeType: String?
    let pixelSize: CGSize
    let isFallback: Bool
    let source: DetailImageLoadSource
    // 仅在本次请求内复用 SVG 渲染结果，不常驻原图解码缓存。
    var renderedSVGImage: UIImage? = nil
}

struct DetailInlineImageCacheKey: Hashable {
    let url: URL
    let maxPixelWidth: Int
    let displayScaleKey: Int
}

struct DetailThumbnailResult {
    let cacheData: Data?
    let image: UIImage
    let quality: CGFloat
    let byteCount: Int
}
