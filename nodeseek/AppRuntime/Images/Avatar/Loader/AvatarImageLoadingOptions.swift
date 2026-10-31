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
