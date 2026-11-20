//
//  AvatarImageLoadingOptions.swift
//  nodeseek
//
//  Created by Codex on 2026/5/10.
//

import Kingfisher
import UIKit

enum AvatarImageLoadingOptions {
    static let targetSize = CGSize(width: 56, height: 56)

    /// 头像独立缓存：内存里不按时间过期，也不会被其他大图挤掉，只按数量和体积封顶。
    /// 内存命中时 Kingfisher 不会在主线程查磁盘，快速滑动更稳。
    static let cache: ImageCache = {
        let cache = ImageCache(name: "NodeSeekAvatar")
        cache.memoryStorage.config.expiration = .never
        cache.memoryStorage.config.countLimit = 400
        cache.memoryStorage.config.totalCostLimit = 48 * 1024 * 1024
        cache.memoryStorage.config.keepWhenEnteringBackground = true
        return cache
    }()

    /// 头像地址不变、内容变了（比如刚上传新头像）时，清掉缓存才能重新下载。
    static func removeCachedAvatar(for url: URL?) {
        guard let url = ImageURLResolver.resolve(url) else { return }
        cache.removeImage(
            forKey: url.absoluteString,
            processorIdentifier: AvatarImageProcessor(size: targetSize).identifier
        )
    }

    /// 站点头像经 CDN 缓存（max-age 4 小时），地址不变时换头像后仍会拿到旧图。
    /// 和网页上传后一样带 no-cache 请求一次让 CDN 回源，再清掉本地缓存。
    /// 用于 App 内上传后，以及「我的」页下拉刷新（网页端换过头像的情况）。
    static func refreshFromOrigin(url: URL?) async {
        guard let resolved = ImageURLResolver.resolve(url) else { return }
        var request = URLRequest(url: resolved, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        WebRequestFingerprint.applyImageHeaders(to: &request)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        let session = URLSession(configuration: makeSessionConfiguration())
        // 临时会话用完要释放，否则会一直留着。
        defer { session.finishTasksAndInvalidate() }
        _ = try? await session.data(for: request)
        removeCachedAvatar(for: resolved)
    }

    static func makeDownloader() -> ImageDownloader {
        let downloader = ImageDownloader(name: "NodeSeekAvatarDownloader")
        downloader.sessionConfiguration = makeSessionConfiguration()
        return downloader
    }

    static func makeOptions(downloader: ImageDownloader) -> KingfisherOptionsInfo {
        [
            .processor(AvatarImageProcessor(size: targetSize)),
            .scaleFactor(UIScreen.main.scale),
            .requestModifier(AnyModifier { request in
                var request = request
                WebRequestFingerprint.applyImageHeaders(to: &request)
                return request
            }),
            .downloader(downloader),
            .targetCache(cache),
            .cacheSerializer(AvatarCacheSerializer.default),
            .transition(.fade(0.2))
        ]
    }

    private static func makeSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 20
        return configuration
    }
}
