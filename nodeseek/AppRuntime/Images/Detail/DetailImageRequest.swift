//
//  DetailImageRequest.swift
//  nodeseek
//
//  Created by Codex on 2026/5/9.
//

import CoreGraphics
import UIKit

struct DetailInlineImageRequest {
    let url: URL?
    let maxPixelWidth: CGFloat
    let displayScale: CGFloat
    let allowsOptimization: Bool

    /// 加载正文 inline 图片，只返回最终展示用 UIImage。
    func load(_ completion: @escaping (UIImage?) -> Void) {
        guard let url else {
            completion(nil)
            return
        }

        DetailImageLoader.shared.loadImageForInline(
            url,
            maxPixelWidth: maxPixelWidth,
            displayScale: displayScale,
            allowsOptimization: allowsOptimization,
            completion: completion
        )
    }

    /// 加载正文 inline 图片结果，保留 report-like SVG 等类型信息。
    func loadResult(_ completion: @escaping (DetailInlineImageResult) -> Void) {
        guard let url else {
            completion(DetailInlineImageResult(image: nil, resolvedKind: nil))
            return
        }

        DetailImageLoader.shared.loadImageForInlineResult(
            url,
            maxPixelWidth: maxPixelWidth,
            displayScale: displayScale,
            allowsOptimization: allowsOptimization,
            completion: completion
        )
    }
}

struct DetailPreviewImageRequest {
    let url: URL?

    /// 加载预览用 UIImage；URL 缺失时返回 nil。
    func load(_ completion: @escaping (UIImage?) -> Void) {
        guard let url else {
            completion(nil)
            return
        }

        DetailImageLoader.shared.loadImageForPreview(url, completion: completion)
    }
}

struct DetailOriginalPayloadRequest {
    let url: URL?

    /// 加载原始图片 payload；URL 缺失或原图不可用时返回 `.unavailable`。
    func load(
        _ completion: @escaping (Result<DetailOriginalFilePayload, DetailOriginalFileError>) -> Void
    ) {
        guard let url else {
            completion(.failure(.unavailable))
            return
        }

        DetailImageLoader.shared.loadOriginalImagePayload(for: url, completion: completion)
    }
}
