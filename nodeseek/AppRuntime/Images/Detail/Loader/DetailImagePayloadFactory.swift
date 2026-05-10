//
//  DetailImagePayloadFactory.swift
//  nodeseek
//
//  Created by Codex on 2026/5/10.
//

import Foundation
import UIKit

enum DetailImagePayloadFactory {
    static func decodedPayload(
        resolvedURL: URL,
        data: Data,
        mimeType: String?
    ) -> DetailDecodedImagePayload {
        let image = ImageRenderer.image(data: data, mimeType: mimeType)

        guard let image else {
            AppLog.error(.image, "attachment 图片解码失败，使用兜底图 url=\(resolvedURL.absoluteString), bytes=\(data.count), mime=\(mimeType ?? "unknown")")
            return DetailImageFallback.decodedPayload
        }

        let imageSize = image.size
        guard isValidImageSize(imageSize) else {
            AppLog.error(.image, "attachment 图片尺寸异常，使用兜底图 url=\(resolvedURL.absoluteString), size=\(NSCoder.string(for: imageSize)), bytes=\(data.count), mime=\(mimeType ?? "unknown")")
            return DetailImageFallback.decodedPayload
        }

        if let mimeType, mimeType.lowercased().hasPrefix("image/") == false {
            AppLog.warning(.image, "attachment MIME非image但已解码成功，继续展示 url=\(resolvedURL.absoluteString), mime=\(mimeType)")
        }

        AppLog.debug(.image, "attachment 下载并校验通过 url=\(resolvedURL.absoluteString), size=\(NSCoder.string(for: imageSize)), bytes=\(data.count), mime=\(mimeType ?? "unknown")")
        return DetailDecodedImagePayload(
            data: data,
            mimeType: mimeType,
            image: image,
            isFallback: false
        )
    }

    static func originalDataPayload(
        resolvedURL: URL,
        data: Data,
        mimeType: String?,
        source: DetailImageLoadSource
    ) -> DetailOriginalDataPayload {
        guard let imageSize = ImageRenderer.pixelSize(data: data, mimeType: mimeType) else {
            AppLog.error(.image, "attachment 图片解码失败，使用兜底图 url=\(resolvedURL.absoluteString), bytes=\(data.count), mime=\(mimeType ?? "unknown")")
            return DetailImageFallback.originalDataPayload(source: source)
        }

        guard isValidImageSize(imageSize) else {
            AppLog.error(.image, "attachment 图片尺寸异常，使用兜底图 url=\(resolvedURL.absoluteString), size=\(NSCoder.string(for: imageSize)), bytes=\(data.count), mime=\(mimeType ?? "unknown")")
            return DetailImageFallback.originalDataPayload(source: source)
        }

        return DetailOriginalDataPayload(
            data: data,
            mimeType: mimeType,
            pixelSize: imageSize,
            isFallback: false,
            source: source
        )
    }

    static func loadSource(from source: ImageDataSource) -> DetailImageLoadSource {
        switch source {
        case .dataURL:
            return .dataURL
        case .disk:
            return .disk
        case .network:
            return .network
        }
    }

    static func resolvedKind(from data: Data, mimeType: String?) -> DetailImageKind? {
        DetailSVGContentRules.isReportLikeSVG(data, mimeType: mimeType) ? .report : nil
    }

    private static func isValidImageSize(_ imageSize: CGSize) -> Bool {
        imageSize.width.isFinite
            && imageSize.height.isFinite
            && imageSize.width > 0
            && imageSize.height > 0
            && imageSize.width <= DetailImageLimits.maxPixelSide
            && imageSize.height <= DetailImageLimits.maxPixelSide
    }
}
