//
//  SettingsManagers.swift
//  nodeseek
//

import Foundation
import Kingfisher
import WebKit

@MainActor
protocol SettingsCacheManaging: AnyObject {
    func cacheByteSize() async -> UInt64
    func clearPreservingCookies() async throws
}

@MainActor
protocol SettingsSessionManaging: AnyObject {
    func logout() async
}

final class DefaultSettingsCacheManager: SettingsCacheManaging {
    func cacheByteSize() async -> UInt64 {
        let detailSize = UInt64(max(DetailImageLoader.shared.detailImageCacheByteSize(), 0))
        let rawImageSize = UInt64(max(ImageDataLoader.shared.cacheByteSize(), 0))
        let kingfisherSize = (try? await ImageCache.default.diskStorageSize) ?? 0
        return detailSize + rawImageSize + UInt64(kingfisherSize)
    }

    func clearPreservingCookies() async throws {
        try DetailImageLoader.shared.clearDetailImageCache()
        try ImageDataLoader.shared.clearCache()
        ImageCache.default.clearMemoryCache()
        await ImageCache.default.clearDiskCache()
        URLCache.shared.removeAllCachedResponses()
        await clearWebViewCachesPreservingCookies()
    }

    private func clearWebViewCachesPreservingCookies() async {
        let dataTypes: Set<String> = [
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache
        ]
        await WKWebsiteDataStore.default().removeData(
            ofTypes: dataTypes,
            modifiedSince: Date(timeIntervalSince1970: 0)
        )
    }
}

final class DefaultSettingsSessionManager: SettingsSessionManaging {
    private let cookieSession: NodeSeekCookieSessionManaging
    private let currentAccountStore: CurrentAccountStore
    private let nodeImageAPIKeyStore: NodeImageAPIKeyStoring

    init(
        cookieBridge: CookieBridge? = nil,
        cookieSession: NodeSeekCookieSessionManaging? = nil,
        currentAccountStore: CurrentAccountStore = .shared,
        nodeImageAPIKeyStore: NodeImageAPIKeyStoring = KeychainNodeImageAPIKeyStore()
    ) {
        self.cookieSession = cookieSession ?? NodeSeekCookieSession(bridge: cookieBridge ?? CookieBridge())
        self.currentAccountStore = currentAccountStore
        self.nodeImageAPIKeyStore = nodeImageAPIKeyStore
    }

    func logout() async {
        await cookieSession.clearLoginSession()
        await currentAccountStore.clear()
        nodeImageAPIKeyStore.clear()
        NotificationCenter.default.post(name: .nodeSeekLoginSessionDidClose, object: nil)
    }
}

private extension WKWebsiteDataStore {
    func removeData(ofTypes dataTypes: Set<String>, modifiedSince date: Date) async {
        await withCheckedContinuation { continuation in
            removeData(ofTypes: dataTypes, modifiedSince: date) {
                continuation.resume()
            }
        }
    }
}
