//
//  DetailImageFallback.swift
//  nodeseek
//
//  Created by Codex on 2026/5/10.
//

import Foundation
import UIKit

enum DetailImageFallback {
    static let pngData: Data = {
        let renderer = UIGraphicsImageRenderer(size: DetailImageLimits.fallbackSize)
        let image = renderer.image { context in
            UIColor(white: 0.88, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: DetailImageLimits.fallbackSize))
        }
        return image.pngData() ?? Data()
    }()

    static let image: UIImage = .init(data: pngData) ?? UIImage()

    static let decodedPayload = DetailDecodedImagePayload(
        data: pngData,
        mimeType: "image/png",
        image: image,
        isFallback: true
    )

    static func originalDataPayload(source: DetailImageLoadSource) -> DetailOriginalDataPayload {
        DetailOriginalDataPayload(
            data: pngData,
            mimeType: "image/png",
            pixelSize: image.size,
            isFallback: true,
            source: source
        )
    }
}
