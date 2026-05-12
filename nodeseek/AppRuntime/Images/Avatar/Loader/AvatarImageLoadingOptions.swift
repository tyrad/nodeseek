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
