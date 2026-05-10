//
//  DetailImageLoader.swift
//  nodeseek
//
//  Created by Codex on 2026/4/28.
//

import Foundation
import UIKit

final class DetailImageLoader {
    // MARK: - Types

    private typealias DecodedPayloadCompletion = (DetailDecodedImagePayload) -> Void
    private typealias OriginalDataCompletion = (DetailOriginalDataPayload) -> Void
    private typealias InlineImageCompletion = (DetailInlineImageResult) -> Void

    // MARK: - Shared Instance

    static let shared = DetailImageLoader()

    // MARK: - Dependencies

    private let imageDataLoader: ImageDataLoader
    private let thumbnailLoader: DetailThumbnailLoader
    private let optimizationModeProvider: () -> DetailImageOptimizationMode

    // MARK: - State

    private let stateQueue = DispatchQueue(label: "com.nodeseek.app.detailimage.state")
    private var decodedPayloadCache: [URL: DetailDecodedImagePayload] = [:]
    private var decodedPayloadCallbacks: [URL: [DecodedPayloadCompletion]] = [:]
    private var inlineImageCache: [DetailInlineImageCacheKey: DetailInlineImageResult] = [:]
    private var inlineImageCallbacks: [DetailInlineImageCacheKey: [InlineImageCompletion]] = [:]

    // MARK: - Initialization

    /// 使用默认缓存目录和全局图片 data loader。
    convenience init() {
        let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("DetailImages", isDirectory: true)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("DetailImages", isDirectory: true)
        self.init(
            imageDataLoader: .shared,
            cacheDirectory: cacheDirectory,
            optimizationModeProvider: { DetailImageConfig.optimizationMode }
        )
    }

    /// 测试或定制场景使用的初始化入口，可注入 URLSession 和缓存目录。
    convenience init(
        session: URLSession,
        cacheDirectory: URL,
        optimizationModeProvider: @escaping () -> DetailImageOptimizationMode = { DetailImageConfig.optimizationMode }
    ) {
        self.init(
            imageDataLoader: ImageDataLoader(
                session: session,
                diskCache: ImageDiskCache(directory: cacheDirectory.appendingPathComponent("originals", isDirectory: true))
            ),
            cacheDirectory: cacheDirectory,
            optimizationModeProvider: optimizationModeProvider
        )
    }

    /// 指定原图 data loader、缓存目录和优化配置来源。
    init(
        imageDataLoader: ImageDataLoader,
        cacheDirectory: URL,
        optimizationModeProvider: @escaping () -> DetailImageOptimizationMode = { DetailImageConfig.optimizationMode }
    ) {
        self.imageDataLoader = imageDataLoader
        self.thumbnailLoader = DetailThumbnailLoader(cacheDirectory: cacheDirectory)
        self.optimizationModeProvider = optimizationModeProvider
    }

    // MARK: - Preview Loading

    /// 加载用于大图预览的 UIImage；解码失败时返回 fallback 图，避免预览链路拿到空结果。
    func loadImageForPreview(_ imageURL: URL, completion: @escaping (UIImage?) -> Void) {
        loadOriginalDataPayload(for: imageURL) { [weak self] payload in
            guard let self else { return }
            let image = ImageRenderer.image(data: payload.data, mimeType: payload.mimeType)
            self.logOptimization(
                mode: self.optimizationModeProvider(),
                "preview load source=\(payload.source.rawValue) fallback=\(payload.isFallback) url=\(imageURL.absoluteString) bytes=\(payload.data.count) pixelSize=\(Self.string(from: payload.pixelSize))"
            )
            completion(image ?? DetailImageFallback.image)
        }
    }

    // MARK: - Original File Loading

    /// 加载原始图片 payload，用于保存、分享或写入临时文件；不可用时返回 `.unavailable`。
    func loadOriginalImagePayload(
        for imageURL: URL,
        completion: @escaping (Result<DetailOriginalFilePayload, DetailOriginalFileError>) -> Void
    ) {
        loadOriginalDataPayload(for: imageURL) { payload in
            guard payload.isFallback == false else {
                completion(.failure(.unavailable))
                return
            }

            completion(.success(DetailOriginalFilePayload(
                data: payload.data,
                mimeType: payload.mimeType,
                suggestedFileExtension: Self.suggestedFileExtension(for: imageURL, mimeType: payload.mimeType)
            )))
        }
    }

    // MARK: - Inline Image Loading

    /// 加载正文 inline 展示图，只返回 UIImage；不关心 SVG report 等额外类型信息时使用。
    func loadImageForInline(
        _ imageURL: URL,
        maxPixelWidth: CGFloat,
        displayScale: CGFloat,
        allowsOptimization: Bool = true,
        completion: @escaping (UIImage?) -> Void
    ) {
        loadImageForInlineResult(
            imageURL,
            maxPixelWidth: maxPixelWidth,
            displayScale: displayScale,
            allowsOptimization: allowsOptimization
        ) { result in
            completion(result.image)
        }
    }

    /// 加载正文 inline 展示结果；优化开启时走 thumbnail，否则按原始 data downsample。
    func loadImageForInlineResult(
        _ imageURL: URL,
        maxPixelWidth: CGFloat,
        displayScale: CGFloat,
        allowsOptimization: Bool = true,
        completion: @escaping (DetailInlineImageResult) -> Void
    ) {
        let mode = optimizationModeProvider()
        if allowsOptimization,
           isOptimizableDetailImageURL(imageURL),
           case let .enabled(maxThumbnailBytes, _) = mode
        {
            thumbnailLoader.loadThumbnail(
                imageURL: imageURL,
                maxPixelWidth: maxPixelWidth,
                maxThumbnailBytes: maxThumbnailBytes,
                mode: mode,
                loadOriginalDataPayload: { url, completion in
                    self.loadOriginalDataPayload(for: url, completion: completion)
                },
                completion: completion
            )
            return
        }

        loadInlineImageWithoutThumbnail(
            imageURL,
            maxPixelWidth: maxPixelWidth,
            displayScale: displayScale,
            completion: completion
        )
    }

    // MARK: - Cache Management

    /// 清理详情图的内存缓存和 thumbnail 磁盘缓存，不清理通用原图 data 缓存。
    func clearDetailImageCache() throws {
        stateQueue.sync {
            decodedPayloadCache.removeAll()
            decodedPayloadCallbacks.removeAll()
            inlineImageCache.removeAll()
            inlineImageCallbacks.removeAll()
        }
        try thumbnailLoader.clearCache()
    }

    /// 返回详情图 thumbnail 磁盘缓存大小，单位为 byte。
    func detailImageCacheByteSize() -> Int {
        thumbnailLoader.cacheByteSize()
    }

    // MARK: - Inline Pipeline

    private func loadInlineImageWithoutThumbnail(
        _ imageURL: URL,
        maxPixelWidth: CGFloat,
        displayScale: CGFloat,
        completion: @escaping InlineImageCompletion
    ) {
        let pixelWidth = max(1, Int(ceil(maxPixelWidth)))
        let imageScale = max(displayScale, 1)
        let cacheURL = ImageURLResolver.resolve(imageURL) ?? imageURL
        let key = DetailInlineImageCacheKey(
            url: cacheURL,
            maxPixelWidth: pixelWidth,
            displayScaleKey: Int((imageScale * 100).rounded())
        )

        if let cachedImage = stateQueue.sync(execute: { inlineImageCache[key] }) {
            logDiagnostics(
                "inline cache hit url=\(cacheURL.absoluteString) maxPixelWidth=\(pixelWidth) imageSize=\(Self.string(from: cachedImage.image?.size ?? .zero))"
            )
            completion(cachedImage)
            return
        }

        let shouldStartLoad = stateQueue.sync { () -> Bool in
            DetailImageCallbackQueue.enqueue(completion, for: key, in: &inlineImageCallbacks)
        }
        guard shouldStartLoad else { return }

        logDiagnostics(
            "inline load start url=\(imageURL.absoluteString) resolved=\(cacheURL.absoluteString) maxPixelWidth=\(pixelWidth) displayScale=\(Self.numberString(imageScale))"
        )
        loadDecodedInlinePayload(for: imageURL) { [weak self] payload in
            guard let self else { return }
            let image = ImageRenderer.downsampledImage(
                data: payload.data,
                maxPixelSize: pixelWidth
            ) ?? payload.image
            let result = DetailInlineImageResult(
                image: image,
                resolvedKind: DetailImagePayloadFactory.resolvedKind(from: payload.data, mimeType: payload.mimeType)
            )
            self.logDiagnostics(
                "inline load payload url=\(imageURL.absoluteString) fallback=\(payload.isFallback) payloadImageSize=\(Self.string(from: payload.image.size)) finalImageSize=\(Self.string(from: image.size))"
            )
            let callbacks = self.stateQueue.sync {
                if payload.isFallback == false {
                    self.inlineImageCache[key] = result
                }
                return DetailImageCallbackQueue.take(for: key, from: &self.inlineImageCallbacks)
            }
            callbacks.forEach { $0(result) }
        }
    }

    // MARK: - Payload Loading

    private func loadDecodedInlinePayload(for imageURL: URL, completion: @escaping DecodedPayloadCompletion) {
        guard let resolvedURL = ImageURLResolver.resolve(imageURL) else {
            AppLog.error(.image, "attachment URL 非法，使用兜底图 url=\(imageURL.absoluteString)")
            completion(DetailImageFallback.decodedPayload)
            return
        }

        if let cachedPayload = stateQueue.sync(execute: { decodedPayloadCache[resolvedURL] }) {
            logDiagnostics(
                "payload cache hit url=\(resolvedURL.absoluteString) imageSize=\(Self.string(from: cachedPayload.image.size))"
            )
            completion(cachedPayload)
            return
        }

        let shouldStartLoad = stateQueue.sync { () -> Bool in
            DetailImageCallbackQueue.enqueue(completion, for: resolvedURL, in: &decodedPayloadCallbacks)
        }
        guard shouldStartLoad else { return }

        logDiagnostics("payload request start url=\(resolvedURL.absoluteString)")
        imageDataLoader.loadData(for: imageURL) { [weak self] result in
            guard let self else { return }
            let payload: DetailDecodedImagePayload
            switch result {
            case .success(let dataPayload):
                payload = DetailImagePayloadFactory.decodedPayload(
                    resolvedURL: dataPayload.resolvedURL,
                    data: dataPayload.data,
                    mimeType: dataPayload.mimeType
                )
            case .failure:
                AppLog.error(.image, "attachment 下载失败，使用兜底图 url=\(resolvedURL.absoluteString)")
                payload = DetailImageFallback.decodedPayload
            }
            self.completeDecodedPayload(for: resolvedURL, payload: payload)
        }
    }

    private func loadOriginalDataPayload(for imageURL: URL, completion: @escaping OriginalDataCompletion) {
        guard let resolvedURL = ImageURLResolver.resolve(imageURL) else {
            AppLog.error(.image, "attachment URL 非法，使用兜底图 url=\(imageURL.absoluteString)")
            completion(DetailImageFallback.originalDataPayload(source: .network))
            return
        }

        imageDataLoader.loadData(for: imageURL) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let dataPayload):
                completion(DetailImagePayloadFactory.originalDataPayload(
                    resolvedURL: dataPayload.resolvedURL,
                    data: dataPayload.data,
                    mimeType: dataPayload.mimeType,
                    source: DetailImagePayloadFactory.loadSource(from: dataPayload.source)
                ))
            case .failure:
                AppLog.error(.image, "attachment 下载失败，使用兜底图 url=\(resolvedURL.absoluteString)")
                completion(DetailImageFallback.originalDataPayload(source: .network))
            }
        }
    }

    // MARK: - Cache Completion

    private func completeDecodedPayload(for url: URL, payload: DetailDecodedImagePayload) {
        let callbacks: [DecodedPayloadCompletion] = stateQueue.sync {
            if payload.isFallback == false {
                decodedPayloadCache[url] = payload
            }
            return DetailImageCallbackQueue.take(for: url, from: &decodedPayloadCallbacks)
        }
        callbacks.forEach { $0(payload) }
    }

    // MARK: - Rules

    private func isOptimizableDetailImageURL(_ url: URL) -> Bool {
        if StickerImageRules.isStickerURL(url) {
            return false
        }

        switch url.pathExtension.lowercased() {
        case "mp4", "mov", "m4v", "webm":
            return false
        default:
            return true
        }
    }

    // MARK: - File Metadata

    /// 根据 URL 扩展名或 MIME 推断原图保存时使用的文件扩展名。
    static func suggestedFileExtension(for imageURL: URL, mimeType: String?) -> String {
        DetailImageFileExtension.suggested(for: imageURL, mimeType: mimeType)
    }

    // MARK: - Logging

    private func logDiagnostics(_ message: String) {
        guard NodeSeekDebugConfig.enableDetailRenderDiagnostics else { return }
        AppLog.info(.image, message)
    }

    private func logOptimization(mode: DetailImageOptimizationMode, _ message: String) {
        guard case let .enabled(_, loggingEnabled) = mode, loggingEnabled else { return }
        AppLog.info(.image, message)
    }

    // MARK: - Formatting

    private static func string(from size: CGSize) -> String {
        "\(numberString(size.width))x\(numberString(size.height))"
    }

    private static func numberString(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }
}
