//
//  DetailVideoAssetRequest.swift
//  nodeseek
//
//  Created by Codex on 2026/4/30.
//

import AVFoundation
import Foundation

enum DetailVideoAssetRequest {
    nonisolated static func makeAsset(
        for url: URL,
        cookieStorage: HTTPCookieStorage = .shared
    ) -> AVURLAsset {
        AVURLAsset(
            url: url,
            options: assetOptions(for: url, cookieStorage: cookieStorage)
        )
    }

    nonisolated static func assetOptions(
        for url: URL,
        cookieStorage: HTTPCookieStorage = .shared
    ) -> [String: Any] {
        var options: [String: Any] = [
            AVURLAssetHTTPUserAgentKey: WebRequestFingerprint.userAgent
        ]

        if let cookies = cookieStorage.cookies(for: url), cookies.isEmpty == false {
            options[AVURLAssetHTTPCookiesKey] = cookies
        }

        return options
    }
}

@MainActor
final class DetailVideoAssetProvider {
    static let shared = DetailVideoAssetProvider()

    private let cookieSession: NodeSeekCookieSessionManaging
    private let cookieStorage: HTTPCookieStorage

    init(cookieStorage: HTTPCookieStorage = .shared) {
        self.cookieSession = NodeSeekCookieSession()
        self.cookieStorage = cookieStorage
    }

    init(cookieBridge: CookieBridge, cookieStorage: HTTPCookieStorage = .shared) {
        self.cookieSession = NodeSeekCookieSession(bridge: cookieBridge)
        self.cookieStorage = cookieStorage
    }

    init(cookieSession: NodeSeekCookieSessionManaging, cookieStorage: HTTPCookieStorage = .shared) {
        self.cookieSession = cookieSession
        self.cookieStorage = cookieStorage
    }

    func makeAsset(for url: URL) async -> AVURLAsset {
        await cookieSession.prepareMediaRequest()
        return DetailVideoAssetRequest.makeAsset(for: url, cookieStorage: cookieStorage)
    }
}
