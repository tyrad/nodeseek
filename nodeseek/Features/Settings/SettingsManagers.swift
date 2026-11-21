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
        let avatarSize = (try? await AvatarImageLoadingOptions.cache.diskStorageSize) ?? 0
        return detailSize + rawImageSize + UInt64(kingfisherSize) + UInt64(avatarSize)
    }

    func clearPreservingCookies() async throws {
        try DetailImageLoader.shared.clearDetailImageCache()
        try ImageDataLoader.shared.clearCache()
        ImageCache.default.clearMemoryCache()
        await ImageCache.default.clearDiskCache()
        AvatarImageLoadingOptions.cache.clearMemoryCache()
        await AvatarImageLoadingOptions.cache.clearDiskCache()
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
    private let defaults: UserDefaults

    init(
        cookieBridge: CookieBridge? = nil,
        cookieSession: NodeSeekCookieSessionManaging? = nil,
        currentAccountStore: CurrentAccountStore = .shared,
        nodeImageAPIKeyStore: NodeImageAPIKeyStoring = KeychainNodeImageAPIKeyStore(),
        defaults: UserDefaults = .standard
    ) {
        self.cookieSession = cookieSession ?? NodeSeekCookieSession(bridge: cookieBridge ?? CookieBridge())
        self.currentAccountStore = currentAccountStore
        self.nodeImageAPIKeyStore = nodeImageAPIKeyStore
        self.defaults = defaults
    }

    // 退出时 Cookie 删除可能尚未落盘，进程就被终止。下次启动先补清，再预热 WebView。
    func startPendingCleanup() -> Task<Void, Never>? {
        guard defaults.bool(forKey: CurrentAccountStore.pendingLogoutCleanupKey) else { return nil }
        return Task { @MainActor in
            AppLog.debug(.account, "开始冷启动退出清理")
            await clearLocalSession(atLaunch: true)
            AppLog.debug(.account, "完成冷启动退出清理")
        }
    }

    func logout() async {
        await clearLocalSession(atLaunch: false)
        NotificationCenter.default.post(name: .nodeSeekAccountSessionDidChange, object: nil)
        NotificationCenter.default.post(name: .nodeSeekLoginSessionDidClose, object: nil)
    }

    private func clearLocalSession(atLaunch: Bool) async {
        await currentAccountStore.beginLogoutCleanup()
        await cookieSession.clearLoginSession()
        nodeImageAPIKeyStore.clear()
        await currentAccountStore.finishLogoutCleanup(atLaunch: atLaunch)
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
