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
