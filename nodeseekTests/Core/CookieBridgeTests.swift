//
//  CookieBridgeTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/4/27.
//

import Foundation
import Testing
@testable import nodeseek

@MainActor
struct CookieBridgeTests {
    @Test func syncsNodeSeekCookiesFromWebViewToURLSession() async throws {
        let webStore = InMemoryWebCookieStore(cookies: [
            try makeCookie(name: "cf_clearance", value: "token", domain: ".nodeseek.com"),
            try makeCookie(name: "other", value: "ignored", domain: ".example.com")
        ])
        let urlStorage = HTTPCookieStorage.shared
        deleteTestCookies(from: urlStorage)
        let bridge = CookieBridge(webCookieStore: webStore, urlCookieStorage: urlStorage)

        await bridge.syncWebViewCookiesToURLSession()

        let cookies = urlStorage.cookies(for: URL(string: "https://www.nodeseek.com/")!) ?? []
        #expect(cookies.contains { $0.name == "cf_clearance" && $0.value == "token" })
        #expect(!cookies.contains { $0.name == "other" })
        deleteTestCookies(from: urlStorage)
    }

    @Test func syncsNodeSeekCookiesFromURLSessionToWebView() async throws {
        let webStore = InMemoryWebCookieStore()
        let urlStorage = HTTPCookieStorage.shared
        deleteTestCookies(from: urlStorage)
        let cookie = try makeCookie(name: "session", value: "abc", domain: ".nodeseek.com")
        urlStorage.setCookie(cookie)
        let bridge = CookieBridge(webCookieStore: webStore, urlCookieStorage: urlStorage)

        await bridge.syncURLSessionCookiesToWebView()

        #expect(webStore.cookies.contains { $0.name == "session" && $0.value == "abc" })
        deleteTestCookies(from: urlStorage)
    }

    @Test func clearsNodeSeekCookiesFromBothStores() async throws {
        let cookie = try makeCookie(name: "cf_clearance", value: "token", domain: ".nodeseek.com")
        let webStore = InMemoryWebCookieStore(cookies: [cookie])
        let urlStorage = HTTPCookieStorage.shared
        deleteTestCookies(from: urlStorage)
        urlStorage.setCookie(cookie)
        let bridge = CookieBridge(webCookieStore: webStore, urlCookieStorage: urlStorage)

        await bridge.clearSession()

        let cookies = urlStorage.cookies(for: URL(string: "https://www.nodeseek.com/")!) ?? []
        #expect(!cookies.contains { $0.name == "cf_clearance" })
        #expect(webStore.cookies.isEmpty)
    }

    @Test func defersDefaultWebCookieStoreCreationUntilSync() async throws {
        let webStore = InMemoryWebCookieStore(cookies: [
            try makeCookie(name: "cf_clearance", value: "token", domain: ".nodeseek.com")
        ])
        let urlStorage = HTTPCookieStorage.shared
        deleteTestCookies(from: urlStorage)
        var factoryCallCount = 0

        let bridge = CookieBridge(
            urlCookieStorage: urlStorage,
            makeDefaultWebCookieStore: {
                factoryCallCount += 1
                return webStore
            }
        )

        #expect(factoryCallCount == 0)

        await bridge.syncWebViewCookiesToURLSession()

        #expect(factoryCallCount == 1)
        let cookies = urlStorage.cookies(for: URL(string: "https://www.nodeseek.com/")!) ?? []
        #expect(cookies.contains { $0.name == "cf_clearance" && $0.value == "token" })
        deleteTestCookies(from: urlStorage)
    }

    private func makeCookie(name: String, value: String, domain: String) throws -> HTTPCookie {
        let cookie = HTTPCookie(properties: [
            .domain: domain,
            .path: "/",
            .name: name,
            .value: value,
            .secure: "TRUE",
            .expires: Date(timeIntervalSinceNow: 3600)
        ])

        return try #require(cookie)
    }

    private func deleteTestCookies(from storage: HTTPCookieStorage) {
        let cookies = storage.cookies ?? []
        for cookie in cookies where cookie.domain.contains("nodeseek.com") || cookie.domain.contains("example.com") {
            storage.deleteCookie(cookie)
        }
    }
}

@MainActor
private final class InMemoryWebCookieStore: WebCookieStore {
    private(set) var cookies: [HTTPCookie]

    init(cookies: [HTTPCookie] = []) {
        self.cookies = cookies
    }

    func allCookies() async -> [HTTPCookie] {
        cookies
    }

    func setCookie(_ cookie: HTTPCookie) async {
        cookies.removeAll { $0.name == cookie.name && $0.domain == cookie.domain && $0.path == cookie.path }
        cookies.append(cookie)
    }

    func deleteCookie(_ cookie: HTTPCookie) async {
        cookies.removeAll { $0.name == cookie.name && $0.domain == cookie.domain && $0.path == cookie.path }
    }
}
