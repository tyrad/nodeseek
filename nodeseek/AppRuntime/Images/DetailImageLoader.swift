//
//  DetailImageLoader.swift
//  nodeseek
//
//  Created by Codex on 2026/4/28.
//

import Foundation
import ImageIO
import OSLog
import SwiftDraw
import UIKit

final class DetailImageLoader {
    private struct ImagePayload {
        let data: Data
        let mimeType: String?
        let image: UIImage
        let isFallback: Bool
    }

    private struct InlineImageCacheKey: Hashable {
        let url: URL
        let maxPixelWidth: Int
        let displayScaleKey: Int
    }

    private typealias PayloadCompletion = (ImagePayload) -> Void
    private typealias InlineImageCompletion = (UIImage?) -> Void

    static let shared = DetailImageLoader()

    private enum Limits {
        static let maxPixelSide: CGFloat = 16_384
        static let maxSVGPixelSide: CGFloat = 2_048
        static let fallbackSize = CGSize(width: 8, height: 8)
    }

    private let logger = Logger(subsystem: "com.nodeseek.app", category: "DetailImageLoader")
    private let session: URLSession
    private let stateQueue = DispatchQueue(label: "com.nodeseek.app.detailimage.state")
    private var payloadCache: [URL: ImagePayload] = [:]
    private var inFlightCallbacks: [URL: [PayloadCompletion]] = [:]
    private var inlineImageCache: [InlineImageCacheKey: UIImage] = [:]
    private var inlineImageCallbacks: [InlineImageCacheKey: [InlineImageCompletion]] = [:]

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 20
        self.session = URLSession(configuration: configuration)
    }

    func loadImageForPreview(_ imageURL: URL, completion: @escaping (UIImage?) -> Void) {
        fetchPayload(for: imageURL) { payload in
            completion(payload.image)
        }
    }

    func loadImageForInline(
        _ imageURL: URL,
        maxPixelWidth: CGFloat,
        displayScale: CGFloat,
        completion: @escaping (UIImage?) -> Void
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
                "inline cache hit url=\(cacheURL.absoluteString) maxPixelWidth=\(pixelWidth) imageSize=\(Self.string(from: cachedImage.size))"
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
            self.logDiagnostics(
                "inline load payload url=\(imageURL.absoluteString) fallback=\(payload.isFallback) payloadImageSize=\(Self.string(from: payload.image.size)) finalImageSize=\(Self.string(from: image.size))"
            )
            let callbacks = self.stateQueue.sync {
                if payload.isFallback == false {
                    self.inlineImageCache[key] = image
                }
                return self.inlineImageCallbacks.removeValue(forKey: key) ?? []
            }
            callbacks.forEach { $0(image) }
        }
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
            logger.error("attachment URL 非法，使用兜底图 url=\(imageURL.absoluteString, privacy: .public)")
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
            logger.error(
                "attachment 下载失败，使用兜底图 url=\(resolvedURL.absoluteString, privacy: .public), error=\(error?.localizedDescription ?? "unknown", privacy: .public)"
            )
            return Self.fallbackPayload
        }

        if dataLooksLikeHTML(data) {
            logger.error(
                "attachment 返回HTML内容，使用兜底图 url=\(resolvedURL.absoluteString, privacy: .public), bytes=\(data.count, privacy: .public), snippet=\(self.snippet(from: data), privacy: .public)"
            )
            return Self.fallbackPayload
        }

        let decodedImage = UIImage(data: data)
        let renderedSVGImage = decodedImage == nil && shouldRenderSVG(data: data, mimeType: mimeType)
            ? renderSVGImage(data: data)
            : nil

        guard let image = decodedImage ?? renderedSVGImage else {
            logger.error(
                "attachment 图片解码失败，使用兜底图 url=\(resolvedURL.absoluteString, privacy: .public), bytes=\(data.count, privacy: .public), mime=\(mimeType ?? "unknown", privacy: .public)"
            )
            return Self.fallbackPayload
        }

        let imageSize = image.size
        guard imageSize.width.isFinite,
              imageSize.height.isFinite,
              imageSize.width > 0,
              imageSize.height > 0,
              imageSize.width <= Limits.maxPixelSide,
              imageSize.height <= Limits.maxPixelSide else {
            logger.error(
                "attachment 图片尺寸异常，使用兜底图 url=\(resolvedURL.absoluteString, privacy: .public), size=\(NSCoder.string(for: imageSize), privacy: .public), bytes=\(data.count, privacy: .public), mime=\(mimeType ?? "unknown", privacy: .public)"
            )
            return Self.fallbackPayload
        }

        if let mimeType, mimeType.lowercased().hasPrefix("image/") == false {
            logger.warning(
                "attachment MIME非image但已解码成功，继续展示 url=\(resolvedURL.absoluteString, privacy: .public), mime=\(mimeType, privacy: .public)"
            )
        }

        logger.debug(
            "attachment 下载并校验通过 url=\(resolvedURL.absoluteString, privacy: .public), size=\(NSCoder.string(for: imageSize), privacy: .public), bytes=\(data.count, privacy: .public), mime=\(mimeType ?? "unknown", privacy: .public)"
        )
        return ImagePayload(
            data: data,
            mimeType: mimeType,
            image: image,
            isFallback: false
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

    private func shouldRenderSVG(data: Data, mimeType: String?) -> Bool {
        if mimeType?.lowercased().contains("svg") == true {
            return true
        }
        return dataLooksLikeSVG(data)
    }

    private func renderSVGImage(data: Data) -> UIImage? {
        guard let svg = SVG(data: data, options: .hideUnsupportedFilters) else {
            return nil
        }

        let size = normalizedSVGSize(svg.size)
        guard size.width > 0, size.height > 0 else { return nil }
        return svg.rasterize(size: size, scale: 1)
    }

    private func normalizedSVGSize(_ size: CGSize) -> CGSize {
        let fallbackSize = CGSize(width: 320, height: 180)
        let sourceWidth = size.width.isFinite && size.width > 0 ? size.width : fallbackSize.width
        let sourceHeight = size.height.isFinite && size.height > 0 ? size.height : fallbackSize.height
        let maxSide = Limits.maxSVGPixelSide

        guard max(sourceWidth, sourceHeight) > maxSide else {
            return CGSize(width: sourceWidth, height: sourceHeight)
        }

        let scale = maxSide / max(sourceWidth, sourceHeight)
        return CGSize(width: sourceWidth * scale, height: sourceHeight * scale)
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
        logger.info("\(message, privacy: .public)")
    }

    private static func string(from size: CGSize) -> String {
        "\(numberString(size.width))x\(numberString(size.height))"
    }

    private static func numberString(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }
}
