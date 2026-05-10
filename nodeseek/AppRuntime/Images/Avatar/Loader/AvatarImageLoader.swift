//
//  AvatarImageLoader.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation
import Kingfisher
import UIKit

@MainActor
final class AvatarImageLoader {
    enum LoadResult {
        case success(url: URL, cacheType: CacheType)
        case failure(url: URL, reason: String)
    }

    typealias Completion = (LoadResult) -> Void

    static let shared = AvatarImageLoader()

    private let downloader: ImageDownloader
    private let cookieSession: NodeSeekCookieSessionManaging
    private var activeRequestTokens: [ObjectIdentifier: UUID] = [:]

    convenience init() {
        self.init(cookieSession: NodeSeekCookieSession())
    }

    convenience init(cookieBridge: CookieBridge) {
        self.init(cookieSession: NodeSeekCookieSession(bridge: cookieBridge))
    }

    init(cookieSession: NodeSeekCookieSessionManaging) {
        self.cookieSession = cookieSession
        self.downloader = AvatarImageLoadingOptions.makeDownloader()
    }

    func cancel(on imageView: UIImageView) {
        activeRequestTokens.removeValue(forKey: ObjectIdentifier(imageView))
        imageView.kf.cancelDownloadTask()
    }

    func loadImage(
        into imageView: UIImageView,
        requestID: String,
        imageURL: URL?,
        completion: Completion? = nil
    ) {
        loadAvatar(
            into: imageView,
            postID: requestID,
            avatarURL: imageURL,
            completion: completion
        )
    }

    func loadAvatar(
        into imageView: UIImageView,
        postID: String,
        avatarURL: URL?,
        completion: Completion? = nil
    ) {
        let requestToken = beginRequest(for: imageView)
        imageView.image = AvatarPlaceholderImage.image

        guard let avatarURL = ImageURLResolver.resolve(avatarURL) else {
            logAvatar(.notice, "头像URL缺失或非法 id=\(postID)")
            finishIfCurrent(requestToken, for: imageView)
            return
        }

        logAvatar(.debug, "开始加载头像 id=\(postID), url=\(avatarURL.absoluteString)")
        loadWithKingfisher(
            into: imageView,
            requestToken: requestToken,
            postID: postID,
            avatarURL: avatarURL,
            allowsCookieRetry: true,
            completion: completion
        )
    }

    private func logAvatar(_ level: AppLogLevel, _ message: @autoclosure () -> String) {
        guard NodeSeekDebugConfig.enableAvatarImageLogs else { return }
        AppLog.log(level, .image, message())
    }

    private func beginRequest(for imageView: UIImageView) -> UUID {
        let viewID = ObjectIdentifier(imageView)
        let requestToken = UUID()
        activeRequestTokens[viewID] = requestToken
        imageView.kf.cancelDownloadTask()
        return requestToken
    }

    private func loadWithKingfisher(
        into imageView: UIImageView,
        requestToken: UUID,
        postID: String,
        avatarURL: URL,
        allowsCookieRetry: Bool,
        completion: Completion?
    ) {
        guard isCurrent(requestToken, for: imageView) else { return }

        imageView.kf.setImage(
            with: avatarURL,
            placeholder: AvatarPlaceholderImage.image,
            options: kingfisherOptions,
            completionHandler: { [weak self, weak imageView] result in
                guard let self, let imageView else { return }
                guard self.isCurrent(requestToken, for: imageView) else {
                    self.logAvatar(.debug, "忽略过期头像回调 id=\(postID)")
                    return
                }

                switch result {
                case let .success(retrieveResult):
                    self.logAvatar(.debug, "头像加载成功 id=\(postID), cache=\(String(describing: retrieveResult.cacheType))")
                    self.completeSuccess(
                        requestToken: requestToken,
                        imageView: imageView,
                        url: avatarURL,
                        cacheType: retrieveResult.cacheType,
                        completion: completion
                    )

                case let .failure(error):
                    self.handleKingfisherFailure(
                        error,
                        imageView: imageView,
                        requestToken: requestToken,
                        postID: postID,
                        avatarURL: avatarURL,
                        allowsCookieRetry: allowsCookieRetry,
                        completion: completion
                    )
                }
            }
        )
    }

    private func handleKingfisherFailure(
        _ error: KingfisherError,
        imageView: UIImageView,
        requestToken: UUID,
        postID: String,
        avatarURL: URL,
        allowsCookieRetry: Bool,
        completion: Completion?
    ) {
        if allowsCookieRetry, AvatarImageLoadFailure.isHTMLPayload(error) {
            retryAfterCookieSync(
                imageView: imageView,
                requestToken: requestToken,
                postID: postID,
                avatarURL: avatarURL,
                completion: completion
            )
            return
        }

        let details = AvatarImageLoadFailure.details(for: error)
        logAvatar(.error, "头像加载失败 id=\(postID), url=\(avatarURL.absoluteString), error=\(details)")
        completeFailure(
            requestToken: requestToken,
            imageView: imageView,
            url: avatarURL,
            reason: details,
            completion: completion
        )
    }

    private func retryAfterCookieSync(
        imageView: UIImageView,
        requestToken: UUID,
        postID: String,
        avatarURL: URL,
        completion: Completion?
    ) {
        logAvatar(.warning, "头像疑似 challenge 页面，准备同步 Cookie 后重试 id=\(postID), url=\(avatarURL.absoluteString)")
        Task { @MainActor [weak self, weak imageView] in
            guard let self, let imageView else { return }
            guard self.isCurrent(requestToken, for: imageView) else { return }
            await self.cookieSession.prepareMediaRequest()
            guard self.isCurrent(requestToken, for: imageView) else { return }

            self.logAvatar(.info, "头像重试前已同步 WebView Cookie 到 URLSession id=\(postID)")
            self.loadWithKingfisher(
                into: imageView,
                requestToken: requestToken,
                postID: postID,
                avatarURL: avatarURL,
                allowsCookieRetry: false,
                completion: completion
            )
        }
    }

    private func completeSuccess(
        requestToken: UUID,
        imageView: UIImageView,
        url: URL,
        cacheType: CacheType,
        completion: Completion?
    ) {
        finishIfCurrent(requestToken, for: imageView)
        completion?(.success(url: url, cacheType: cacheType))
    }

    private func completeFailure(
        requestToken: UUID,
        imageView: UIImageView,
        url: URL,
        reason: String,
        completion: Completion?
    ) {
        finishIfCurrent(requestToken, for: imageView)
        completion?(.failure(url: url, reason: reason))
    }

    private var kingfisherOptions: KingfisherOptionsInfo {
        AvatarImageLoadingOptions.makeOptions(downloader: downloader)
    }

    private func isCurrent(_ requestToken: UUID, for imageView: UIImageView) -> Bool {
        activeRequestTokens[ObjectIdentifier(imageView)] == requestToken
    }

    private func finishIfCurrent(_ requestToken: UUID, for imageView: UIImageView) {
        let viewID = ObjectIdentifier(imageView)
        guard activeRequestTokens[viewID] == requestToken else { return }
        activeRequestTokens.removeValue(forKey: viewID)
    }
}
