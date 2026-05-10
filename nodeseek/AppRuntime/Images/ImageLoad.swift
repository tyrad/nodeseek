//
//  ImageLoad.swift
//  nodeseek
//
//  Created by Codex on 2026/5/9.
//

import CoreGraphics
import Foundation

enum ImageLoad {
    static func url(_ url: URL?) -> ImageLoadRequest {
        ImageLoadRequest(url: url)
    }
}

struct ImageLoadRequest {
    let url: URL?

    func toAvatar(requestID: String) -> AvatarImageRequest {
        AvatarImageRequest(url: url, requestID: requestID)
    }

    func toDetailInline(
        maxPixelWidth: CGFloat,
        displayScale: CGFloat,
        allowsOptimization: Bool = true
    ) -> DetailInlineImageRequest {
        DetailInlineImageRequest(
            url: url,
            maxPixelWidth: maxPixelWidth,
            displayScale: displayScale,
            allowsOptimization: allowsOptimization
        )
    }

    func toDetailPreview() -> DetailPreviewImageRequest {
        DetailPreviewImageRequest(url: url)
    }

    func toOriginalPayload() -> DetailOriginalPayloadRequest {
        DetailOriginalPayloadRequest(url: url)
    }
}
