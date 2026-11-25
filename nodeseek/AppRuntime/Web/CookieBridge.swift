//
//  CookieBridge.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation
import WebKit

@MainActor
protocol WebCookieStore: AnyObject {
    func allCookies() async -> [HTTPCookie]
    func setCookie(_ cookie: HTTPCookie) async
    func deleteCookie(_ cookie: HTTPCookie) async
}

@MainActor
final class WKWebCookieStoreAdapter: WebCookieStore {
    private let store: WKHTTPCookieStore

    init(store: WKHTTPCookieStore) {
        self.store = store
    }

    func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            store.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    func setCookie(_ cookie: HTTPCookie) async {
        await withCheckedContinuation { continuation in
            store.setCookie(cookie) {
                continuation.resume()
            }
        }
    }

    func deleteCookie(_ cookie: HTTPCookie) async {
        await withCheckedContinuation { continuation in
            store.delete(cookie) {
                continuation.resume()
            }
        }
    }
}

// 本质上是在包 WebKit 的 Cookie API
@MainActor
final class CookieBridge {
    private var webCookieStore: WebCookieStore?
    private let makeDefaultWebCookieStore: @MainActor () -> WebCookieStore
    private let urlCookieStorage: HTTPCookieStorage
    private let allowedDomains: [String]

    init(
        webCookieStore: WebCookieStore? = nil,
        urlCookieStorage: HTTPCookieStorage = .shared,
        allowedDomains: [String] = NodeSeekSite.allowedCookieDomains,
        // 延迟创建
        makeDefaultWebCookieStore: @escaping @MainActor () -> WebCookieStore = {
            WKWebCookieStoreAdapter(
                store: WKWebsiteDataStore.default().httpCookieStore // Cookie源。 WKHTTPCookieStore 本身提供 setC / getC / getAllC 等
            )
        }
    ) {
        self.webCookieStore = webCookieStore
        self.makeDefaultWebCookieStore = makeDefaultWebCookieStore
        self.urlCookieStorage = urlCookieStorage
        self.allowedDomains = allowedDomains
    }

    func syncWebViewCookiesToURLSession() async {
        let webCookieStore = resolvedWebCookieStore()
        let cookies = await webCookieStore.allCookies()
        for cookie in cookies where isAllowed(cookie) {
            urlCookieStorage.setCookie(cookie)
        }
    }

    func syncURLSessionCookiesToWebView() async {
        let webCookieStore = resolvedWebCookieStore()
        let cookies = urlCookieStorage.cookies ?? []
        for cookie in cookies where isAllowed(cookie) {
            await webCookieStore.setCookie(cookie)
        }
    }

    func clearSession() async {
        let webCookieStore = resolvedWebCookieStore()
        let urlCookies = urlCookieStorage.cookies ?? []
        let webCookies = await webCookieStore.allCookies()
        logCleanupCookies("清理前", urlCookies: urlCookies, webCookies: webCookies)
        for cookie in urlCookies where isAllowed(cookie) {
            urlCookieStorage.deleteCookie(cookie)
        }

        for cookie in webCookies where isAllowed(cookie) {
            await webCookieStore.deleteCookie(cookie)
        }
        let remaining = await webCookieStore.allCookies()
        logCleanupCookies("清理后", urlCookies: urlCookieStorage.cookies ?? [], webCookies: remaining)
    }

    /// 导出当前活跃存储中的账号会话 Cookie（合并 WebKit 与 URLSession，WebKit 优先）。
    func exportAccountSessionCookies() async -> [HTTPCookie] {
        let merged = await mergedAllowedCookies()
        return NodeSeekCookieClassifier.accountSessionCookies(from: merged, allowedDomains: allowedDomains)
    }

    /// 导出当前活跃存储中的 Cloudflare 过盾 Cookie，供独立登录页与独立自动签到复用。
    func exportCloudflareCookies() async -> [HTTPCookie] {
        let merged = await mergedAllowedCookies()
        return NodeSeekCookieClassifier.cloudflareCookies(from: merged, allowedDomains: allowedDomains)
    }

    /// 双边先删后写替换账号会话 Cookie，保留 Cloudflare 与站点偏好 Cookie。
    func replaceAccountSessionCookies(with targetCookies: [HTTPCookie]) async {
        let webCookieStore = resolvedWebCookieStore()
        let urlCookies = urlCookieStorage.cookies ?? []
        let webCookies = await webCookieStore.allCookies()
        logCleanupCookies("切换账号清理前", urlCookies: urlCookies, webCookies: webCookies)

        for cookie in urlCookies where NodeSeekCookieClassifier.isAccountSession(cookie, allowedDomains: allowedDomains) {
            urlCookieStorage.deleteCookie(cookie)
        }
        for cookie in webCookies where NodeSeekCookieClassifier.isAccountSession(cookie, allowedDomains: allowedDomains) {
            await webCookieStore.deleteCookie(cookie)
        }

        let validTargetCookies = NodeSeekCookieClassifier.accountSessionCookies(
            from: targetCookies,
            allowedDomains: allowedDomains
        )
        for cookie in validTargetCookies {
            urlCookieStorage.setCookie(cookie)
            await webCookieStore.setCookie(cookie)
        }

        let remaining = await webCookieStore.allCookies()
        logCleanupCookies("切换账号写入后", urlCookies: urlCookieStorage.cookies ?? [], webCookies: remaining)
    }

    /// 仅清空双边账号会话 Cookie，保留 Cloudflare 过盾与站点偏好 Cookie。
    func clearAccountSessionCookies() async {
        await replaceAccountSessionCookies(with: [])
    }

    private func mergedAllowedCookies() async -> [HTTPCookie] {
        let webCookieStore = resolvedWebCookieStore()
        let webCookies = await webCookieStore.allCookies().filter(isAllowed)
        let urlCookies = (urlCookieStorage.cookies ?? []).filter(isAllowed)
        var byIdentity: [String: HTTPCookie] = [:]
        // URLSession 先入表，WebKit 覆盖，确保最新 WebView 续期 Cookie 优先。
        for cookie in urlCookies {
            byIdentity[Self.cookieIdentity(cookie)] = cookie
        }
        for cookie in webCookies {
            byIdentity[Self.cookieIdentity(cookie)] = cookie
        }
        return Array(byIdentity.values)
    }

    private static func cookieIdentity(_ cookie: HTTPCookie) -> String {
        "\(cookie.name.lowercased())|\(cookie.domain.lowercased())|\(cookie.path)"
    }

    private func logCleanupCookies(_ stage: String, urlCookies: [HTTPCookie], webCookies: [HTTPCookie]) {
        func names(_ cookies: [HTTPCookie]) -> String {
            Set(cookies.filter(isAllowed).map(\.name)).sorted().joined(separator: ",")
        }
        AppLog.debug(.account, "Cookie \(stage) URLSession=[\(names(urlCookies))] WebKit=[\(names(webCookies))]")
    }

    private func resolvedWebCookieStore() -> WebCookieStore {
        if let webCookieStore {
            return webCookieStore
        }

        let webCookieStore = makeDefaultWebCookieStore()
        self.webCookieStore = webCookieStore
        return webCookieStore
    }

    private func isAllowed(_ cookie: HTTPCookie) -> Bool {
        allowedDomains.contains { allowedDomain in
            let normalizedDomain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
            return normalizedDomain == allowedDomain || normalizedDomain.hasSuffix(".\(allowedDomain)")
        }
    }
}
