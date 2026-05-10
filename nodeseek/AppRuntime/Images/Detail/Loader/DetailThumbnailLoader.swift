//
//  DetailThumbnailLoader.swift
//  nodeseek
//
//  Created by Codex on 2026/5/10.
//

import Foundation
import UIKit

final class DetailThumbnailLoader {
    typealias Completion = (DetailInlineImageResult) -> Void
    typealias OriginalDataProvider = (URL, @escaping (DetailOriginalDataPayload) -> Void) -> Void

    private let cacheFiles: DetailImageCacheFiles
    private let stateQueue = DispatchQueue(label: "com.nodeseek.app.detailimage.thumbnail")
    private var thumbnailCallbacks: [URL: [Completion]] = [:]
    private var thumbnailImageCache: [URL: DetailInlineImageResult] = [:]

    /// 使用详情图缓存目录初始化 thumbnail 缓存管理。
    init(cacheDirectory: URL) {
        self.cacheFiles = DetailImageCacheFiles(cacheDirectory: cacheDirectory)
    }

    /// 加载正文展示用 thumbnail；原图 data 由调用方提供，避免 thumbnail 路径单独发起网络请求。
    func loadThumbnail(
        imageURL: URL,
        maxPixelWidth: CGFloat,
        maxThumbnailBytes: Int,
        mode: DetailImageOptimizationMode,
        loadOriginalDataPayload: @escaping OriginalDataProvider,
        completion: @escaping Completion
    ) {
        let pixelSide = max(1, Int(ceil(maxPixelWidth)))
        guard let resolvedURL = ImageURLResolver.resolve(imageURL) else {
            AppLog.error(.image, "attachment URL 非法，使用兜底图 url=\(imageURL.absoluteString)")
            completion(DetailInlineImageResult(image: DetailImageFallback.image, resolvedKind: nil))
            return
        }

        if let cachedThumbnail = cachedThumbnailResult(for: resolvedURL, mode: mode) {
            completion(cachedThumbnail)
            return
        }

        let shouldStartLoad = stateQueue.sync { () -> Bool in
            DetailImageCallbackQueue.enqueue(completion, for: resolvedURL, in: &thumbnailCallbacks)
        }
        guard shouldStartLoad else { return }

        loadOriginalDataPayload(imageURL) { [weak self] payload in
            guard let self else { return }
            if DetailImagePayloadFactory.resolvedKind(from: payload.data, mimeType: payload.mimeType) == .report {
                let image = ImageRenderer.image(data: payload.data, mimeType: payload.mimeType) ?? DetailImageFallback.image
                let result = DetailInlineImageResult(image: image, resolvedKind: .report)
                try? FileManager.default.removeItem(at: self.cacheFiles.thumbnailCacheURL(for: resolvedURL))
                self.logOptimization(
                    mode: mode,
                    "report svg inline original url=\(resolvedURL.absoluteString) source=\(payload.source.rawValue) bytes=\(payload.data.count) imageSize=\(Self.string(from: image.size))"
                )
                self.completeThumbnailLoad(for: resolvedURL, result: result, cacheInMemory: false)
                return
            }

            let downsampled = ImageRenderer.image(
                data: payload.data,
                mimeType: payload.mimeType,
                maxPixelSize: min(pixelSide, Int(DetailImageLimits.maxPixelSide))
            ) ?? DetailImageFallback.image
            let thumbnail = DetailThumbnailBuilder.makeBoundedThumbnail(
                from: downsampled,
                maxBytes: maxThumbnailBytes
            )
            let result = DetailInlineImageResult(image: thumbnail.image, resolvedKind: nil)
            if payload.isFallback == false, let cacheData = thumbnail.cacheData {
                try? self.cacheFiles.writeData(cacheData, to: self.cacheFiles.thumbnailCacheURL(for: resolvedURL))
            }

            self.logOptimization(
                mode: mode,
                "thumbnail generated url=\(resolvedURL.absoluteString) source=\(payload.source.rawValue) originalBytes=\(payload.data.count) originalPixels=\(Self.string(from: payload.pixelSize)) thumbnailBytes=\(thumbnail.byteCount) thumbnailCached=\(thumbnail.cacheData != nil) thumbnailPixels=\(Self.string(from: thumbnail.image.size)) quality=\(Self.numberString(thumbnail.quality)) targetPixelSide=\(pixelSide) maxBytes=\(maxThumbnailBytes)"
            )

            self.completeThumbnailLoad(
                for: resolvedURL,
                result: result,
                cacheInMemory: payload.isFallback == false && thumbnail.cacheData != nil
            )
        }
    }

    /// 清理 thumbnail 内存缓存、等待回调和磁盘缓存。
    func clearCache() throws {
        stateQueue.sync {
            thumbnailCallbacks.removeAll()
            thumbnailImageCache.removeAll()
        }
        try cacheFiles.clearThumbnails()
    }

    /// 返回 thumbnail 磁盘缓存大小，单位为 byte。
    func cacheByteSize() -> Int {
        cacheFiles.thumbnailByteSize()
    }

    private func cachedThumbnailResult(
        for resolvedURL: URL,
        mode: DetailImageOptimizationMode
    ) -> DetailInlineImageResult? {
        if let cachedImage = stateQueue.sync(execute: { thumbnailImageCache[resolvedURL] }) {
            logOptimization(
                mode: mode,
                "thumbnail memory hit url=\(resolvedURL.absoluteString) imageSize=\(Self.string(from: cachedImage.image?.size ?? .zero))"
            )
            return cachedImage
        }

        guard shouldInspectOriginalBeforeUsingThumbnailDiskCache(for: resolvedURL) == false,
              let diskData = try? Data(contentsOf: cacheFiles.thumbnailCacheURL(for: resolvedURL)),
              let diskImage = UIImage(data: diskData)
        else {
            return nil
        }

        let result = DetailInlineImageResult(image: diskImage, resolvedKind: nil)
        stateQueue.sync {
            thumbnailImageCache[resolvedURL] = result
        }
        logOptimization(
            mode: mode,
            "thumbnail disk hit url=\(resolvedURL.absoluteString) bytes=\(diskData.count) imageSize=\(Self.string(from: diskImage.size))"
        )
        return result
    }

    private func completeThumbnailLoad(
        for resolvedURL: URL,
        result: DetailInlineImageResult,
        cacheInMemory: Bool
    ) {
        let callbacks = stateQueue.sync {
            if cacheInMemory {
                thumbnailImageCache[resolvedURL] = result
            }
            return DetailImageCallbackQueue.take(for: resolvedURL, from: &thumbnailCallbacks)
        }
        callbacks.forEach { $0(result) }
    }

    private func shouldInspectOriginalBeforeUsingThumbnailDiskCache(for resolvedURL: URL) -> Bool {
        if resolvedURL.pathExtension.lowercased() == "svg" {
            return true
        }

        if resolvedURL.pathExtension.isEmpty,
           DetailImageURLRules.isLikelyImageURL(resolvedURL)
        {
            return true
        }

        return resolvedURL.absoluteString.lowercased().hasPrefix("data:image/svg")
    }

    private func logOptimization(mode: DetailImageOptimizationMode, _ message: String) {
        guard case let .enabled(_, loggingEnabled) = mode, loggingEnabled else { return }
        AppLog.info(.image, message)
    }

    private static func string(from size: CGSize) -> String {
        "\(numberString(size.width))x\(numberString(size.height))"
    }

    private static func numberString(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }
}
