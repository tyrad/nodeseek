//
//  AvatarImageLoader.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation
import Kingfisher
import OSLog
import SwiftDraw
import UIKit

@MainActor
final class AvatarImageLoader {

    enum LoadResult {
        case success(url: URL, cacheType: CacheType)
        case failure(url: URL, reason: String)
    }

    typealias Completion = (LoadResult) -> Void

    static let shared = AvatarImageLoader()

    private enum AvatarRender {
        static let size = CGSize(width: 56, height: 56)
    }

    private static let placeholderImage: UIImage = {
        let size = CGSize(width: 8, height: 8)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor(white: 0.9, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }()

    private let logger = Logger(subsystem: "com.nodeseek.app", category: "PostListAvatar")
    private let downloader: ImageDownloader
    private let directSession: URLSession
    private let cookieBridge: CookieBridge
    private var requestTokens: [ObjectIdentifier: UUID] = [:]
    private let svgImageCache = NSCache<NSString, UIImage>()
    private var knownSVGURLs = Set<String>()

    convenience init() {
        self.init(cookieBridge: CookieBridge())
    }

    init(cookieBridge: CookieBridge) {
        self.cookieBridge = cookieBridge

        let downloaderConfiguration = Self.makeSessionConfiguration()
        self.downloader = ImageDownloader(name: "NodeSeekAvatarDownloader")
        self.downloader.sessionConfiguration = downloaderConfiguration

        self.directSession = URLSession(configuration: Self.makeSessionConfiguration())
    }

    func cancel(on imageView: UIImageView) {
        requestTokens.removeValue(forKey: ObjectIdentifier(imageView))
        imageView.kf.cancelDownloadTask()
    }

    func loadAvatar(
        into imageView: UIImageView,
        postID: String,
        avatarURL: URL?,
        completion: Completion? = nil
    ) {
        let token = beginRequest(for: imageView)
        imageView.image = Self.placeholderImage

        guard let avatarURL else {
            logger.notice("头像URL缺失 id=\(postID, privacy: .public)")
            finishIfCurrent(token, for: imageView)
            return
        }

        if knownSVGURLs.contains(avatarURL.absoluteString) {
            logger.debug("命中已知 SVG 快速路径 id=\(postID, privacy: .public), url=\(avatarURL.absoluteString, privacy: .public)")
            loadKnownSVGAvatar(
                into: imageView,
                token: token,
                postID: postID,
                avatarURL: avatarURL,
                allowCookieRetry: true,
                completion: completion
            )
            return
        }

        logger.debug("开始加载头像 id=\(postID, privacy: .public), url=\(avatarURL.absoluteString, privacy: .public)")
        loadWithKingfisher(
            into: imageView,
            token: token,
            postID: postID,
            avatarURL: avatarURL,
            allowCookieRetry: true,
            completion: completion
        )
    }

    private func beginRequest(for imageView: UIImageView) -> UUID {
        let viewID = ObjectIdentifier(imageView)
        let token = UUID()
        requestTokens[viewID] = token
        imageView.kf.cancelDownloadTask()
        return token
    }

    private func loadWithKingfisher(
        into imageView: UIImageView,
        token: UUID,
        postID: String,
        avatarURL: URL,
        allowCookieRetry: Bool,
        completion: Completion?
    ) {
        guard isCurrent(token, for: imageView) else { return }

        imageView.kf.setImage(
            with: avatarURL,
            placeholder: Self.placeholderImage,
            options: optionsInfo,
            completionHandler: { [weak self, weak imageView] result in
                guard let self, let imageView else { return }
                guard self.isCurrent(token, for: imageView) else {
                    self.logger.debug("忽略过期头像回调 id=\(postID, privacy: .public)")
                    return
                }

                switch result {
                case .success(let retrieveResult):
                    self.logger.debug(
                        "头像加载成功 id=\(postID, privacy: .public), cache=\(String(describing: retrieveResult.cacheType), privacy: .public)"
                    )
                    self.completeSuccess(
                        token: token,
                        imageView: imageView,
                        url: avatarURL,
                        cacheType: retrieveResult.cacheType,
                        completion: completion
                    )

                case .failure(let error):
                    self.handleKingfisherFailure(
                        error,
                        imageView: imageView,
                        token: token,
                        postID: postID,
                        avatarURL: avatarURL,
                        allowCookieRetry: allowCookieRetry,
                        completion: completion
                    )
                }
            }
        )
    }

    private func handleKingfisherFailure(
        _ error: KingfisherError,
        imageView: UIImageView,
        token: UUID,
        postID: String,
        avatarURL: URL,
        allowCookieRetry: Bool,
        completion: Completion?
    ) {
        if let svgData = svgDataIfAvailable(from: error) {
            knownSVGURLs.insert(avatarURL.absoluteString)
            logger.info(
                "检测到 SVG 头像，准备渲染 id=\(postID, privacy: .public), url=\(avatarURL.absoluteString, privacy: .public)"
            )
            Task { @MainActor [weak self, weak imageView] in
                guard let self, let imageView else { return }
                guard self.isCurrent(token, for: imageView) else { return }
                await self.renderAndDisplaySVG(
                    data: svgData,
                    into: imageView,
                    token: token,
                    postID: postID,
                    avatarURL: avatarURL,
                    completion: completion
                )
            }
            return
        }

        if allowCookieRetry, shouldRetryAfterCookieSync(error: error) {
            logger.warning(
                "头像疑似 challenge 页面，准备同步 Cookie 后重试 id=\(postID, privacy: .public), url=\(avatarURL.absoluteString, privacy: .public)"
            )
            Task { @MainActor [weak self, weak imageView] in
                guard let self, let imageView else { return }
                guard self.isCurrent(token, for: imageView) else { return }
                await self.cookieBridge.syncWebViewCookiesToURLSession()
                guard self.isCurrent(token, for: imageView) else { return }
                self.logger.info("头像重试前已同步 WebView Cookie 到 URLSession id=\(postID, privacy: .public)")
                self.loadWithKingfisher(
                    into: imageView,
                    token: token,
                    postID: postID,
                    avatarURL: avatarURL,
                    allowCookieRetry: false,
                    completion: completion
                )
            }
            return
        }

        let details = failureDetails(for: error)
        logger.error(
            "头像加载失败 id=\(postID, privacy: .public), url=\(avatarURL.absoluteString, privacy: .public), error=\(details, privacy: .public)"
        )
        completeFailure(
            token: token,
            imageView: imageView,
            url: avatarURL,
            reason: details,
            completion: completion
        )
    }

    private func loadKnownSVGAvatar(
        into imageView: UIImageView,
        token: UUID,
        postID: String,
        avatarURL: URL,
        allowCookieRetry: Bool,
        completion: Completion?
    ) {
        let cacheKey = avatarURL.absoluteString as NSString
        if let cachedImage = svgImageCache.object(forKey: cacheKey) {
            imageView.image = cachedImage
            logger.debug("SVG 快速路径缓存命中 id=\(postID, privacy: .public), url=\(avatarURL.absoluteString, privacy: .public)")
            completeSuccess(token: token, imageView: imageView, url: avatarURL, cacheType: .memory, completion: completion)
            return
        }

        Task { @MainActor [weak self, weak imageView] in
            guard let self, let imageView else { return }
            guard self.isCurrent(token, for: imageView) else { return }

            do {
                let data = try await self.downloadAvatarData(url: avatarURL)
                guard self.isCurrent(token, for: imageView) else { return }

                if self.dataLooksLikeSVG(data) {
                    await self.renderAndDisplaySVG(
                        data: data,
                        into: imageView,
                        token: token,
                        postID: postID,
                        avatarURL: avatarURL,
                        completion: completion
                    )
                    return
                }

                if self.dataLooksLikeHTML(data), allowCookieRetry {
                    self.logger.warning("SVG 快速路径疑似 challenge 页面，准备同步 Cookie 后重试 id=\(postID, privacy: .public)")
                    await self.cookieBridge.syncWebViewCookiesToURLSession()
                    guard self.isCurrent(token, for: imageView) else { return }
                    self.loadKnownSVGAvatar(
                        into: imageView,
                        token: token,
                        postID: postID,
                        avatarURL: avatarURL,
                        allowCookieRetry: false,
                        completion: completion
                    )
                    return
                }

                if let bitmapImage = UIImage(data: data) {
                    self.knownSVGURLs.remove(avatarURL.absoluteString)
                    imageView.image = bitmapImage
                    self.logger.notice(
                        "已知 SVG URL 返回位图，已回退普通路径 id=\(postID, privacy: .public), url=\(avatarURL.absoluteString, privacy: .public)"
                    )
                    self.completeSuccess(token: token, imageView: imageView, url: avatarURL, cacheType: .none, completion: completion)
                    return
                }

                throw SVGRenderError.unsupportedData
            } catch {
                guard self.isCurrent(token, for: imageView) else { return }
                self.logger.error(
                    "SVG 快速路径失败 id=\(postID, privacy: .public), url=\(avatarURL.absoluteString, privacy: .public), error=\(error.localizedDescription, privacy: .public)"
                )
                self.completeFailure(
                    token: token,
                    imageView: imageView,
                    url: avatarURL,
                    reason: error.localizedDescription,
                    completion: completion
                )
            }
        }
    }

    private func renderAndDisplaySVG(
        data: Data,
        into imageView: UIImageView,
        token: UUID,
        postID: String,
        avatarURL: URL,
        completion: Completion?
    ) async {
        let cacheKey = avatarURL.absoluteString as NSString
        if let cachedImage = svgImageCache.object(forKey: cacheKey) {
            imageView.image = cachedImage
            logger.debug("SVG 头像缓存命中 id=\(postID, privacy: .public), url=\(avatarURL.absoluteString, privacy: .public)")
            completeSuccess(token: token, imageView: imageView, url: avatarURL, cacheType: .memory, completion: completion)
            return
        }

        do {
            let renderedImage = try await Self.renderSVGImage(
                data: data,
                targetSize: AvatarRender.size,
                scale: displayScale(for: imageView)
            )
            guard isCurrent(token, for: imageView) else { return }
            imageView.image = renderedImage
            svgImageCache.setObject(renderedImage, forKey: cacheKey)
            logger.info("SVG 头像渲染成功 id=\(postID, privacy: .public), url=\(avatarURL.absoluteString, privacy: .public)")
            completeSuccess(token: token, imageView: imageView, url: avatarURL, cacheType: .none, completion: completion)
        } catch {
            guard isCurrent(token, for: imageView) else { return }
            logger.error(
                "SVG 头像渲染失败 id=\(postID, privacy: .public), url=\(avatarURL.absoluteString, privacy: .public), error=\(error.localizedDescription, privacy: .public)"
            )
            completeFailure(
                token: token,
                imageView: imageView,
                url: avatarURL,
                reason: error.localizedDescription,
                completion: completion
            )
        }
    }

    private func completeSuccess(
        token: UUID,
        imageView: UIImageView,
        url: URL,
        cacheType: CacheType,
        completion: Completion?
    ) {
        finishIfCurrent(token, for: imageView)
        completion?(.success(url: url, cacheType: cacheType))
    }

    private func completeFailure(
        token: UUID,
        imageView: UIImageView,
        url: URL,
        reason: String,
        completion: Completion?
    ) {
        finishIfCurrent(token, for: imageView)
        completion?(.failure(url: url, reason: reason))
    }

    private func downloadAvatarData(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.cachePolicy = .returnCacheDataElseLoad
        Self.applyRequestHeaders(to: &request)

        let (data, _) = try await directSession.data(for: request)
        return data
    }

    private var optionsInfo: KingfisherOptionsInfo {
        [
            .requestModifier(AnyModifier { request in
                var request = request
                Self.applyRequestHeaders(to: &request)
                return request
            }),
            .downloader(downloader),
            .transition(.fade(0.2)),
            .cacheOriginalImage
        ]
    }

    nonisolated private static func makeSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 20
        return configuration
    }

    nonisolated private static func applyRequestHeaders(to request: inout URLRequest) {
        WebRequestFingerprint.applyImageHeaders(to: &request)
    }

    private func displayScale(for imageView: UIImageView) -> CGFloat {
        if let screenScale = imageView.window?.windowScene?.screen.scale {
            return screenScale
        }
        return max(imageView.traitCollection.displayScale, 1)
    }

    private func isCurrent(_ token: UUID, for imageView: UIImageView) -> Bool {
        requestTokens[ObjectIdentifier(imageView)] == token
    }

    private func finishIfCurrent(_ token: UUID, for imageView: UIImageView) {
        let viewID = ObjectIdentifier(imageView)
        guard requestTokens[viewID] == token else { return }
        requestTokens.removeValue(forKey: viewID)
    }

    private func shouldRetryAfterCookieSync(error: KingfisherError) -> Bool {
        guard case let .processorError(reason) = error else { return false }
        guard case let .processingFailed(processor: _, item: item) = reason else { return false }
        guard case let .data(data) = item else { return false }
        return dataLooksLikeHTML(data)
    }

    private func failureDetails(for error: KingfisherError) -> String {
        var message = error.localizedDescription
        guard case let .processorError(reason) = error else { return message }
        guard case let .processingFailed(processor: _, item: item) = reason else { return message }
        guard case let .data(data) = item else { return message }

        let snippet = String(data: data.prefix(120), encoding: .utf8)?
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            ?? ""
        let lowerSnippet = snippet.lowercased()
        let isHTML = lowerSnippet.contains("<html")
            || lowerSnippet.contains("<!doctype html")
            || lowerSnippet.contains("just a moment")
            || lowerSnippet.contains("cf_chl")
        let isSVG = lowerSnippet.contains("<svg")
            || lowerSnippet.contains("<?xml")
            || lowerSnippet.contains("</svg>")

        message += ", dataBytes=\(data.count), looksHTML=\(isHTML), looksSVG=\(isSVG)"
        if !snippet.isEmpty {
            message += ", snippet=\(snippet)"
        }
        return message
    }

    private func dataLooksLikeHTML(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        let prefix = String(data: data.prefix(256), encoding: .utf8)?
            .lowercased()
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        guard let prefix else { return false }
        return prefix.contains("<html")
            || prefix.contains("<!doctype html")
            || prefix.contains("just a moment")
            || prefix.contains("cf_chl")
            || prefix.contains("challenge-platform")
    }

    private func svgDataIfAvailable(from error: KingfisherError) -> Data? {
        guard case let .processorError(reason) = error else { return nil }
        guard case let .processingFailed(processor: _, item: item) = reason else { return nil }
        guard case let .data(data) = item else { return nil }
        return dataLooksLikeSVG(data) ? data : nil
    }

    private func dataLooksLikeSVG(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
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

    private static func renderSVGImage(data: Data, targetSize: CGSize, scale: CGFloat) async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let svg = SVG(data: data) else {
                    continuation.resume(throwing: SVGRenderError.unsupportedData)
                    return
                }
                let image = svg.rasterize(size: targetSize, scale: scale)
                continuation.resume(returning: image)
            }
        }
    }
}

private enum SVGRenderError: LocalizedError {
    case unsupportedData

    var errorDescription: String? {
        switch self {
        case .unsupportedData:
            return "SVG/位图数据均无法解析"
        }
    }
}
