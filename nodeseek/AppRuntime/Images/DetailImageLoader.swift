//
//  DetailImageLoader.swift
//  nodeseek
//
//  Created by Codex on 2026/4/28.
//

import Foundation
import CryptoKit
import ImageIO
import UIKit

struct DetailOriginalImagePayload: Equatable {
    let data: Data
    let mimeType: String?
    let suggestedFileExtension: String
}

enum DetailOriginalImageError: Error, Equatable {
    case unavailable
}

struct DetailInlineImageResult {
    let image: UIImage?
    let resolvedKind: DetailImageKind?
}

final class DetailImageLoader {
    private enum ImageLoadSource: String {
        case dataURL
        case disk
        case memory
        case network
    }

    private struct ImagePayload {
        let data: Data
        let mimeType: String?
        let image: UIImage
        let isFallback: Bool
    }

    private struct ImageDataPayload {
        let data: Data
        let mimeType: String?
        let pixelSize: CGSize
        let isFallback: Bool
        let source: ImageLoadSource
    }

    private struct InlineImageCacheKey: Hashable {
        let url: URL
        let maxPixelWidth: Int
        let displayScaleKey: Int
    }

    private struct ThumbnailResult {
        let cacheData: Data?
        let image: UIImage
        let quality: CGFloat
        let byteCount: Int
    }

    private typealias PayloadCompletion = (ImagePayload) -> Void
    private typealias ImageDataCompletion = (ImageDataPayload) -> Void
    private typealias InlineImageCompletion = (DetailInlineImageResult) -> Void

    static let shared = DetailImageLoader()

    private enum Limits {
        static let maxPixelSide: CGFloat = 16_384
        static let maxSVGPixelSide: CGFloat = 2_048
        static let fallbackSize = CGSize(width: 8, height: 8)
        static let thumbnailInitialQuality: CGFloat = 0.82
        static let thumbnailMinimumQuality: CGFloat = 0.55
        static let thumbnailMinimumPixelSide: CGFloat = 64
    }

    private let session: URLSession
    private let cacheDirectory: URL
    private let optimizationModeProvider: () -> DetailImageOptimizationMode
    private let stateQueue = DispatchQueue(label: "com.nodeseek.app.detailimage.state")
    private var payloadCache: [URL: ImagePayload] = [:]
    private var inFlightCallbacks: [URL: [PayloadCompletion]] = [:]
    private var originalDataCallbacks: [URL: [ImageDataCompletion]] = [:]
    private var thumbnailCallbacks: [URL: [InlineImageCompletion]] = [:]
    private var thumbnailImageCache: [URL: DetailInlineImageResult] = [:]
    private var inlineImageCache: [InlineImageCacheKey: DetailInlineImageResult] = [:]
    private var inlineImageCallbacks: [InlineImageCacheKey: [InlineImageCompletion]] = [:]

    convenience init() {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 20
        self.init(
            session: URLSession(configuration: configuration),
            cacheDirectory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent("DetailImages", isDirectory: true)
                ?? FileManager.default.temporaryDirectory.appendingPathComponent("DetailImages", isDirectory: true),
            optimizationModeProvider: { DetailImageConfig.optimizationMode }
        )
    }

    init(
        session: URLSession,
        cacheDirectory: URL,
        optimizationModeProvider: @escaping () -> DetailImageOptimizationMode = { DetailImageConfig.optimizationMode }
    ) {
        self.session = session
        self.cacheDirectory = cacheDirectory
        self.optimizationModeProvider = optimizationModeProvider
    }

    func loadImageForPreview(_ imageURL: URL, completion: @escaping (UIImage?) -> Void) {
        fetchOriginalData(for: imageURL) { [weak self] payload in
            guard let self else { return }
            let image = self.decodedImage(data: payload.data, mimeType: payload.mimeType)
            self.logOptimization(
                mode: self.optimizationModeProvider(),
                "preview load source=\(payload.source.rawValue) fallback=\(payload.isFallback) url=\(imageURL.absoluteString) bytes=\(payload.data.count) pixelSize=\(Self.string(from: payload.pixelSize))"
            )
            completion(image ?? Self.fallbackImage)
        }
    }

    func loadOriginalImagePayload(
        for imageURL: URL,
        completion: @escaping (Result<DetailOriginalImagePayload, DetailOriginalImageError>) -> Void
    ) {
        fetchOriginalData(for: imageURL) { payload in
            guard payload.isFallback == false else {
                completion(.failure(.unavailable))
                return
            }

            completion(.success(DetailOriginalImagePayload(
                data: payload.data,
                mimeType: payload.mimeType,
                suggestedFileExtension: Self.suggestedFileExtension(for: imageURL, mimeType: payload.mimeType)
            )))
        }
    }

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
           case .enabled(let maxPixelSide, let maxThumbnailBytes, _) = mode {
            loadOptimizedThumbnail(
                imageURL,
                maxPixelSide: maxPixelSide,
                maxThumbnailBytes: maxThumbnailBytes,
                mode: mode,
                completion: completion
            )
            return
        }

        loadLegacyInlineImage(
            imageURL,
            maxPixelWidth: maxPixelWidth,
            displayScale: displayScale,
            completion: completion
        )
    }

    func clearDetailImageCache() throws {
        stateQueue.sync {
            payloadCache.removeAll()
            inlineImageCache.removeAll()
            thumbnailImageCache.removeAll()
        }
        if FileManager.default.fileExists(atPath: cacheDirectory.path) {
            try FileManager.default.removeItem(at: cacheDirectory)
        }
    }

    func detailImageCacheByteSize() -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
            total += values?.fileSize ?? 0
        }
        return total
    }

    func cachedOriginalData(for imageURL: URL) -> Data? {
        guard let resolvedURL = resolvedCacheURL(for: imageURL) else { return nil }
        return try? Data(contentsOf: originalCacheURL(for: resolvedURL))
    }

    func cachedThumbnailData(for imageURL: URL) -> Data? {
        guard let resolvedURL = resolvedCacheURL(for: imageURL) else { return nil }
        return try? Data(contentsOf: thumbnailCacheURL(for: resolvedURL))
    }

    private func loadLegacyInlineImage(
        _ imageURL: URL,
        maxPixelWidth: CGFloat,
        displayScale: CGFloat,
        completion: @escaping InlineImageCompletion
    ) {
        let pixelWidth = max(1, Int(ceil(maxPixelWidth)))
        let imageScale = max(displayScale, 1)
        let cacheURL = AvatarImageLoader.resolveImageURL(imageURL) ?? imageURL
        let key = InlineImageCacheKey(
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
            if var callbacks = inlineImageCallbacks[key] {
                callbacks.append(completion)
                inlineImageCallbacks[key] = callbacks
                return false
            }
            inlineImageCallbacks[key] = [completion]
            return true
        }
        guard shouldStartLoad else { return }

        logDiagnostics(
            "inline load start url=\(imageURL.absoluteString) resolved=\(cacheURL.absoluteString) maxPixelWidth=\(pixelWidth) displayScale=\(Self.numberString(imageScale))"
        )
        fetchPayload(for: imageURL) { [weak self] payload in
            guard let self else { return }
            let image = self.downsampleImage(
                data: payload.data,
                maxPixelSize: pixelWidth
            ) ?? payload.image
            let result = DetailInlineImageResult(
                image: image,
                resolvedKind: Self.resolvedKind(from: payload.data, mimeType: payload.mimeType)
            )
            self.logDiagnostics(
                "inline load payload url=\(imageURL.absoluteString) fallback=\(payload.isFallback) payloadImageSize=\(Self.string(from: payload.image.size)) finalImageSize=\(Self.string(from: image.size))"
            )
            let callbacks = self.stateQueue.sync {
                if payload.isFallback == false {
                    self.inlineImageCache[key] = result
                }
                return self.inlineImageCallbacks.removeValue(forKey: key) ?? []
            }
            callbacks.forEach { $0(result) }
        }
    }

    private func loadOptimizedThumbnail(
        _ imageURL: URL,
        maxPixelSide: CGFloat,
        maxThumbnailBytes: Int,
        mode: DetailImageOptimizationMode,
        completion: @escaping InlineImageCompletion
    ) {
        let pixelSide = max(1, Int(ceil(maxPixelSide)))
        guard let resolvedURL = resolvedCacheURL(for: imageURL) else {
            AppLog.error(.image, "attachment URL 非法，使用兜底图 url=\(imageURL.absoluteString)")
            completion(DetailInlineImageResult(image: Self.fallbackImage, resolvedKind: nil))
            return
        }

        if let cachedImage = stateQueue.sync(execute: { thumbnailImageCache[resolvedURL] }) {
            logOptimization(
                mode: mode,
                "thumbnail memory hit url=\(resolvedURL.absoluteString) imageSize=\(Self.string(from: cachedImage.image?.size ?? .zero))"
            )
            completion(cachedImage)
            return
        }

        if shouldInspectOriginalBeforeUsingThumbnailDiskCache(for: resolvedURL) == false,
           let diskData = try? Data(contentsOf: thumbnailCacheURL(for: resolvedURL)),
           let diskImage = UIImage(data: diskData) {
            let result = DetailInlineImageResult(image: diskImage, resolvedKind: nil)
            stateQueue.sync {
                thumbnailImageCache[resolvedURL] = result
            }
            logOptimization(
                mode: mode,
                "thumbnail disk hit url=\(resolvedURL.absoluteString) bytes=\(diskData.count) imageSize=\(Self.string(from: diskImage.size))"
            )
            completion(result)
            return
        }

        let shouldStartLoad = stateQueue.sync { () -> Bool in
            if var callbacks = thumbnailCallbacks[resolvedURL] {
                callbacks.append(completion)
                thumbnailCallbacks[resolvedURL] = callbacks
                return false
            }
            thumbnailCallbacks[resolvedURL] = [completion]
            return true
        }
        guard shouldStartLoad else { return }

        fetchOriginalData(for: imageURL) { [weak self] payload in
            guard let self else { return }
            if Self.resolvedKind(from: payload.data, mimeType: payload.mimeType) == .report {
                let image = self.decodedImage(data: payload.data, mimeType: payload.mimeType) ?? Self.fallbackImage
                let result = DetailInlineImageResult(image: image, resolvedKind: .report)
                try? FileManager.default.removeItem(at: self.thumbnailCacheURL(for: resolvedURL))
                self.logOptimization(
                    mode: mode,
                    "report svg inline original url=\(resolvedURL.absoluteString) source=\(payload.source.rawValue) bytes=\(payload.data.count) imageSize=\(Self.string(from: image.size))"
                )
                let callbacks = self.stateQueue.sync {
                    self.thumbnailCallbacks.removeValue(forKey: resolvedURL) ?? []
                }
                callbacks.forEach { $0(result) }
                return
            }

            let downsampled = self.downsampleImage(
                data: payload.data,
                maxPixelSize: min(pixelSide, Int(Limits.maxPixelSide))
            ) ?? self.decodedImage(data: payload.data, mimeType: payload.mimeType) ?? Self.fallbackImage
            let thumbnail = self.makeBoundedThumbnail(
                from: downsampled,
                maxBytes: maxThumbnailBytes
            )
            let result = DetailInlineImageResult(image: thumbnail.image, resolvedKind: nil)
            if payload.isFallback == false, let cacheData = thumbnail.cacheData {
                try? self.writeData(cacheData, to: self.thumbnailCacheURL(for: resolvedURL))
            }

            self.logOptimization(
                mode: mode,
                "thumbnail generated url=\(resolvedURL.absoluteString) source=\(payload.source.rawValue) originalBytes=\(payload.data.count) originalPixels=\(Self.string(from: payload.pixelSize)) thumbnailBytes=\(thumbnail.byteCount) thumbnailCached=\(thumbnail.cacheData != nil) thumbnailPixels=\(Self.string(from: thumbnail.image.size)) quality=\(Self.numberString(thumbnail.quality)) maxPixelSide=\(pixelSide) maxBytes=\(maxThumbnailBytes)"
            )

            let callbacks = self.stateQueue.sync {
                if payload.isFallback == false, thumbnail.cacheData != nil {
                    self.thumbnailImageCache[resolvedURL] = result
                }
                return self.thumbnailCallbacks.removeValue(forKey: resolvedURL) ?? []
            }
            callbacks.forEach { $0(result) }
        }
    }

    private func shouldInspectOriginalBeforeUsingThumbnailDiskCache(for resolvedURL: URL) -> Bool {
        if resolvedURL.pathExtension.lowercased() == "svg" {
            return true
        }

        return resolvedURL.absoluteString.lowercased().hasPrefix("data:image/svg")
    }

    private func fetchPayload(for imageURL: URL, completion: @escaping PayloadCompletion) {
        if let dataURLPayload = decodeDataURL(imageURL) {
            logDiagnostics("payload dataURL url=\(String(imageURL.absoluteString.prefix(80))) bytes=\(dataURLPayload.data.count)")
            completion(validatePayload(
                resolvedURL: imageURL,
                data: dataURLPayload.data,
                mimeType: dataURLPayload.mimeType,
                error: nil
            ))
            return
        }

        guard let resolvedURL = AvatarImageLoader.resolveImageURL(imageURL) else {
            AppLog.error(.image, "attachment URL 非法，使用兜底图 url=\(imageURL.absoluteString)")
            completion(Self.fallbackPayload)
            return
        }

        if let cachedPayload = stateQueue.sync(execute: { payloadCache[resolvedURL] }) {
            logDiagnostics(
                "payload cache hit url=\(resolvedURL.absoluteString) imageSize=\(Self.string(from: cachedPayload.image.size))"
            )
            completion(cachedPayload)
            return
        }

        let shouldStartRequest = stateQueue.sync { () -> Bool in
            if var callbacks = inFlightCallbacks[resolvedURL] {
                callbacks.append(completion)
                inFlightCallbacks[resolvedURL] = callbacks
                return false
            }
            inFlightCallbacks[resolvedURL] = [completion]
            return true
        }
        guard shouldStartRequest else { return }

        logDiagnostics("payload request start url=\(resolvedURL.absoluteString)")
        var request = URLRequest(url: resolvedURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.cachePolicy = .returnCacheDataElseLoad
        WebRequestFingerprint.applyImageHeaders(to: &request)

        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            let payload = self.validatePayload(
                resolvedURL: resolvedURL,
                data: data,
                mimeType: response?.mimeType,
                error: error
            )
            self.completePayload(for: resolvedURL, payload: payload)
        }.resume()
    }

    private func fetchOriginalData(for imageURL: URL, completion: @escaping ImageDataCompletion) {
        if let dataURLPayload = decodeDataURL(imageURL) {
            logDiagnostics("original dataURL url=\(String(imageURL.absoluteString.prefix(80))) bytes=\(dataURLPayload.data.count)")
            completion(validateImageDataPayload(
                resolvedURL: imageURL,
                data: dataURLPayload.data,
                mimeType: dataURLPayload.mimeType,
                error: nil,
                source: .dataURL
            ))
            return
        }

        guard let resolvedURL = AvatarImageLoader.resolveImageURL(imageURL) else {
            AppLog.error(.image, "attachment URL 非法，使用兜底图 url=\(imageURL.absoluteString)")
            completion(Self.fallbackDataPayload(source: .network))
            return
        }

        if let diskData = try? Data(contentsOf: originalCacheURL(for: resolvedURL)) {
            completion(validateImageDataPayload(
                resolvedURL: resolvedURL,
                data: diskData,
                mimeType: nil,
                error: nil,
                source: .disk
            ))
            return
        }

        let shouldStartRequest = stateQueue.sync { () -> Bool in
            if var callbacks = originalDataCallbacks[resolvedURL] {
                callbacks.append(completion)
                originalDataCallbacks[resolvedURL] = callbacks
                return false
            }
            originalDataCallbacks[resolvedURL] = [completion]
            return true
        }
        guard shouldStartRequest else { return }

        var request = URLRequest(url: resolvedURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.cachePolicy = .returnCacheDataElseLoad
        WebRequestFingerprint.applyImageHeaders(to: &request)

        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            let payload = self.validateImageDataPayload(
                resolvedURL: resolvedURL,
                data: data,
                mimeType: response?.mimeType,
                error: error,
                source: .network
            )
            if payload.isFallback == false {
                try? self.writeData(payload.data, to: self.originalCacheURL(for: resolvedURL))
            }
            let callbacks = self.stateQueue.sync {
                self.originalDataCallbacks.removeValue(forKey: resolvedURL) ?? []
            }
            callbacks.forEach { $0(payload) }
        }.resume()
    }

    private func isOptimizableDetailImageURL(_ url: URL) -> Bool {
        let absolute = url.absoluteString.lowercased()
        if absolute.contains("sticker") {
            return false
        }

        switch url.pathExtension.lowercased() {
        case "mp4", "mov", "m4v", "webm":
            return false
        default:
            return true
        }
    }

    private func resolvedCacheURL(for imageURL: URL) -> URL? {
        if imageURL.absoluteString.lowercased().hasPrefix("data:") {
            return imageURL
        }
        return AvatarImageLoader.resolveImageURL(imageURL)
    }

    static func suggestedFileExtension(for imageURL: URL, mimeType: String?) -> String {
        let extensionFromURL = imageURL.pathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if extensionFromURL.isEmpty == false {
            return extensionFromURL == "jpeg" ? "jpg" : extensionFromURL
        }

        switch mimeType?.lowercased().split(separator: ";", maxSplits: 1).first.map(String.init) {
        case "image/jpeg", "image/jpg":
            return "jpg"
        case "image/png":
            return "png"
        case "image/gif":
            return "gif"
        case "image/webp":
            return "webp"
        case "image/heic":
            return "heic"
        case "image/heif":
            return "heif"
        case "image/tiff":
            return "tiff"
        case "image/bmp":
            return "bmp"
        default:
            return "jpg"
        }
    }

    private func completePayload(for url: URL, payload: ImagePayload) {
        let callbacks: [PayloadCompletion] = stateQueue.sync {
            if payload.isFallback == false {
                payloadCache[url] = payload
            }
            return inFlightCallbacks.removeValue(forKey: url) ?? []
        }
        callbacks.forEach { $0(payload) }
    }

    private func validatePayload(
        resolvedURL: URL,
        data: Data?,
        mimeType: String?,
        error: Error?
    ) -> ImagePayload {
        guard let data else {
            AppLog.error(.image, "attachment 下载失败，使用兜底图 url=\(resolvedURL.absoluteString), error=\(error?.localizedDescription ?? "unknown")")
            return Self.fallbackPayload
        }

        if dataLooksLikeHTML(data) {
            AppLog.error(.image, "attachment 返回HTML内容，使用兜底图 url=\(resolvedURL.absoluteString), bytes=\(data.count), snippet=\(self.snippet(from: data))")
            return Self.fallbackPayload
        }

        let image = decodedImage(data: data, mimeType: mimeType)

        guard let image else {
            AppLog.error(.image, "attachment 图片解码失败，使用兜底图 url=\(resolvedURL.absoluteString), bytes=\(data.count), mime=\(mimeType ?? "unknown")")
            return Self.fallbackPayload
        }

        let imageSize = image.size
        guard imageSize.width.isFinite,
              imageSize.height.isFinite,
              imageSize.width > 0,
              imageSize.height > 0,
              imageSize.width <= Limits.maxPixelSide,
              imageSize.height <= Limits.maxPixelSide else {
            AppLog.error(.image, "attachment 图片尺寸异常，使用兜底图 url=\(resolvedURL.absoluteString), size=\(NSCoder.string(for: imageSize)), bytes=\(data.count), mime=\(mimeType ?? "unknown")")
            return Self.fallbackPayload
        }

        if let mimeType, mimeType.lowercased().hasPrefix("image/") == false {
            AppLog.warning(.image, "attachment MIME非image但已解码成功，继续展示 url=\(resolvedURL.absoluteString), mime=\(mimeType)")
        }

        AppLog.debug(.image, "attachment 下载并校验通过 url=\(resolvedURL.absoluteString), size=\(NSCoder.string(for: imageSize)), bytes=\(data.count), mime=\(mimeType ?? "unknown")")
        return ImagePayload(
            data: data,
            mimeType: mimeType,
            image: image,
            isFallback: false
        )
    }

    private func validateImageDataPayload(
        resolvedURL: URL,
        data: Data?,
        mimeType: String?,
        error: Error?,
        source: ImageLoadSource
    ) -> ImageDataPayload {
        guard let data else {
            AppLog.error(.image, "attachment 下载失败，使用兜底图 url=\(resolvedURL.absoluteString), error=\(error?.localizedDescription ?? "unknown")")
            return Self.fallbackDataPayload(source: source)
        }

        if dataLooksLikeHTML(data) {
            AppLog.error(.image, "attachment 返回HTML内容，使用兜底图 url=\(resolvedURL.absoluteString), bytes=\(data.count), snippet=\(self.snippet(from: data))")
            return Self.fallbackDataPayload(source: source)
        }

        guard let imageSize = imagePixelSize(data: data, mimeType: mimeType) else {
            AppLog.error(.image, "attachment 图片解码失败，使用兜底图 url=\(resolvedURL.absoluteString), bytes=\(data.count), mime=\(mimeType ?? "unknown")")
            return Self.fallbackDataPayload(source: source)
        }

        guard imageSize.width.isFinite,
              imageSize.height.isFinite,
              imageSize.width > 0,
              imageSize.height > 0,
              imageSize.width <= Limits.maxPixelSide,
              imageSize.height <= Limits.maxPixelSide else {
            AppLog.error(.image, "attachment 图片尺寸异常，使用兜底图 url=\(resolvedURL.absoluteString), size=\(NSCoder.string(for: imageSize)), bytes=\(data.count), mime=\(mimeType ?? "unknown")")
            return Self.fallbackDataPayload(source: source)
        }

        return ImageDataPayload(
            data: data,
            mimeType: mimeType,
            pixelSize: imageSize,
            isFallback: false,
            source: source
        )
    }

    private func downsampleImage(data: Data, maxPixelSize: Int) -> UIImage? {
        guard maxPixelSize > 0 else { return nil }

        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }

        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else {
            return nil
        }

        return UIImage(cgImage: image, scale: 1, orientation: .up)
    }

    private func makeBoundedThumbnail(from image: UIImage, maxBytes: Int) -> ThumbnailResult {
        let byteLimit = max(maxBytes, 1)
        var workingImage = image
        var lastData = image.jpegData(compressionQuality: Limits.thumbnailMinimumQuality) ?? Self.fallbackPNGData
        var lastQuality = Limits.thumbnailMinimumQuality

        for _ in 0..<8 {
            var quality = Limits.thumbnailInitialQuality
            while quality >= Limits.thumbnailMinimumQuality {
                if let data = workingImage.jpegData(compressionQuality: quality) {
                    lastData = data
                    lastQuality = quality
                    if data.count <= byteLimit {
                        return ThumbnailResult(
                            cacheData: data,
                            image: workingImage,
                            quality: quality,
                            byteCount: data.count
                        )
                    }
                }
                quality -= 0.09
            }

            let currentMaxSide = max(workingImage.size.width, workingImage.size.height)
            guard currentMaxSide > Limits.thumbnailMinimumPixelSide else {
                break
            }

            let ratio = sqrt(CGFloat(byteLimit) / CGFloat(max(lastData.count, 1)))
            let resizeRatio = min(max(ratio * 0.9, 0.5), 0.85)
            guard let resizedImage = resizedImage(workingImage, scale: resizeRatio) else {
                break
            }
            workingImage = resizedImage
        }

        return ThumbnailResult(
            cacheData: nil,
            image: workingImage,
            quality: lastQuality,
            byteCount: lastData.count
        )
    }

    private func resizedImage(_ image: UIImage, scale: CGFloat) -> UIImage? {
        guard scale > 0, scale < 1 else { return image }
        let size = CGSize(
            width: max(1, floor(image.size.width * scale)),
            height: max(1, floor(image.size.height * scale))
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private func decodedImage(data: Data, mimeType: String?) -> UIImage? {
        let decodedImage = UIImage(data: data)
        let renderedSVGImage = decodedImage == nil && shouldRenderSVG(data: data, mimeType: mimeType)
            ? renderSVGImage(data: data)
            : nil
        return decodedImage ?? renderedSVGImage
    }

    private func imagePixelSize(data: Data, mimeType: String?) -> CGSize? {
        if shouldRenderSVG(data: data, mimeType: mimeType) {
            return renderSVGImage(data: data)?.size
        }

        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            return nil
        }

        return CGSize(width: CGFloat(width.doubleValue), height: CGFloat(height.doubleValue))
    }

    private func shouldRenderSVG(data: Data, mimeType: String?) -> Bool {
        if mimeType?.lowercased().contains("svg") == true {
            return true
        }
        return dataLooksLikeSVG(data)
    }

    private static func resolvedKind(from data: Data, mimeType: String?) -> DetailImageKind? {
        DetailSVGContentRules.isReportLikeSVG(data, mimeType: mimeType) ? .report : nil
    }

    private func renderSVGImage(data: Data) -> UIImage? {
        guard let size = SVGImageRenderer.imageSize(
            from: data,
            fallbackSize: CGSize(width: 320, height: 180),
            maxPixelSide: Limits.maxSVGPixelSide
        ) else { return nil }
        return SVGImageRenderer.image(from: data, size: size)
    }

    private static let fallbackPNGData: Data = {
        let renderer = UIGraphicsImageRenderer(size: Limits.fallbackSize)
        let image = renderer.image { context in
            UIColor(white: 0.88, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: Limits.fallbackSize))
        }
        return image.pngData() ?? Data()
    }()

    private static let fallbackImage: UIImage = UIImage(data: fallbackPNGData) ?? UIImage()

    private static let fallbackPayload = ImagePayload(
        data: fallbackPNGData,
        mimeType: "image/png",
        image: fallbackImage,
        isFallback: true
    )

    private static func fallbackDataPayload(source: ImageLoadSource) -> ImageDataPayload {
        ImageDataPayload(
            data: fallbackPNGData,
            mimeType: "image/png",
            pixelSize: fallbackImage.size,
            isFallback: true,
            source: source
        )
    }

    private var originalCacheDirectory: URL {
        cacheDirectory.appendingPathComponent("originals", isDirectory: true)
    }

    private var thumbnailCacheDirectory: URL {
        cacheDirectory.appendingPathComponent("thumbnails", isDirectory: true)
    }

    private func originalCacheURL(for imageURL: URL) -> URL {
        originalCacheDirectory.appendingPathComponent(cacheKey(for: imageURL), isDirectory: false)
    }

    private func thumbnailCacheURL(for imageURL: URL) -> URL {
        thumbnailCacheDirectory.appendingPathComponent("\(cacheKey(for: imageURL)).jpg", isDirectory: false)
    }

    private func cacheKey(for imageURL: URL) -> String {
        let data = Data(imageURL.absoluteString.utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func writeData(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: [.atomic])
    }

    private func dataLooksLikeHTML(_ data: Data) -> Bool {
        guard let prefix = String(data: data.prefix(256), encoding: .utf8)?
            .lowercased()
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ") else {
            return false
        }
        return prefix.contains("<html")
            || prefix.contains("<!doctype html")
            || prefix.contains("<body")
            || prefix.contains("challenge-platform")
            || prefix.contains("cf_chl")
    }

    private func dataLooksLikeSVG(_ data: Data) -> Bool {
        guard let prefix = String(data: data.prefix(512), encoding: .utf8)?
            .lowercased()
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ") else {
            return false
        }
        return prefix.contains("<svg")
            || prefix.contains("</svg>")
            || (prefix.contains("<?xml") && prefix.contains("svg"))
    }

    private func snippet(from data: Data) -> String {
        String(data: data.prefix(120), encoding: .utf8)?
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            ?? ""
    }

    private func decodeDataURL(_ url: URL) -> (data: Data, mimeType: String?)? {
        let raw = url.absoluteString
        guard raw.lowercased().hasPrefix("data:"),
              let commaIndex = raw.firstIndex(of: ",") else {
            return nil
        }

        let header = String(raw[raw.startIndex..<commaIndex]).lowercased()
        let payloadStart = raw.index(after: commaIndex)
        let payload = String(raw[payloadStart...])

        guard header.contains(";base64"),
              let data = Data(base64Encoded: payload, options: .ignoreUnknownCharacters) else {
            return nil
        }

        let mimeType = header
            .replacingOccurrences(of: "data:", with: "")
            .components(separatedBy: ";")
            .first
        return (data, mimeType)
    }

    private func logDiagnostics(_ message: String) {
        guard NodeSeekDebugConfig.enableDetailRenderDiagnostics else { return }
        AppLog.info(.image, message)
    }

    private func logOptimization(mode: DetailImageOptimizationMode, _ message: String) {
        guard case .enabled(_, _, let loggingEnabled) = mode, loggingEnabled else { return }
        AppLog.info(.image, message)
    }

    private static func string(from size: CGSize) -> String {
        "\(numberString(size.width))x\(numberString(size.height))"
    }

    private static func numberString(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }
}
