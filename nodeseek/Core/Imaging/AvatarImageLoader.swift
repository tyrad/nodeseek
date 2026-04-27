//
//  AvatarImageLoader.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation
import Kingfisher
import OSLog
import UIKit

private let avatarRequestModifier = AnyModifier { request in
    var request = request
    request.setValue(
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36",
        forHTTPHeaderField: "User-Agent"
    )
    request.setValue("https://www.nodeseek.com/", forHTTPHeaderField: "Referer")
    request.setValue("image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
    return request
}

@MainActor
final class AvatarImageLoader {

    enum LoadResult {
        case success(url: URL, cacheType: CacheType)
        case failure(url: URL, reason: String)
    }

    typealias Completion = (LoadResult) -> Void

    static let shared = AvatarImageLoader()

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
    private let cookieBridge: CookieBridge
    private var requestTokens: [ObjectIdentifier: UUID] = [:]

    convenience init() {
        self.init(cookieBridge: CookieBridge())
    }

    init(cookieBridge: CookieBridge) {
        self.cookieBridge = cookieBridge
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 20
        self.downloader = ImageDownloader(name: "NodeSeekAvatarDownloader")
        self.downloader.sessionConfiguration = configuration
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
        let viewID = ObjectIdentifier(imageView)
        let token = UUID()
        requestTokens[viewID] = token
        imageView.kf.cancelDownloadTask()
        imageView.image = Self.placeholderImage

        guard let avatarURL else {
            logger.notice("头像URL缺失 id=\(postID, privacy: .public)")
            requestTokens.removeValue(forKey: viewID)
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
                    self.finishIfCurrent(token, for: imageView)
                    self.logger.debug(
                        "头像加载成功 id=\(postID, privacy: .public), cache=\(String(describing: retrieveResult.cacheType), privacy: .public)"
                    )
                    completion?(.success(url: avatarURL, cacheType: retrieveResult.cacheType))

                case .failure(let error):
                    if allowCookieRetry, self.shouldRetryAfterCookieSync(error: error) {
                        self.logger.warning(
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

                    self.finishIfCurrent(token, for: imageView)
                    let details = self.failureDetails(for: error)
                    self.logger.error(
                        "头像加载失败 id=\(postID, privacy: .public), url=\(avatarURL.absoluteString, privacy: .public), error=\(details, privacy: .public)"
                    )
                    completion?(.failure(url: avatarURL, reason: details))
                }
            }
        )
    }

    private var optionsInfo: KingfisherOptionsInfo {
        [
            .requestModifier(avatarRequestModifier),
            .downloader(downloader),
            .transition(.fade(0.2)),
            .cacheOriginalImage
        ]
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

        message += ", dataBytes=\(data.count), looksHTML=\(isHTML)"
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
}
