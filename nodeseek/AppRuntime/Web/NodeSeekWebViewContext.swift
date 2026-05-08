//
//  NodeSeekWebViewContext.swift
//  nodeseek
//

import UIKit
import WebKit

@MainActor
protocol NodeSeekWebCookieSynchronizing: AnyObject {
    func syncURLSessionCookiesToWebView() async
    func syncWebViewCookiesToURLSession() async
}

extension CookieBridge: NodeSeekWebCookieSynchronizing {}

@MainActor
final class NodeSeekWebViewContext {
    let webView: WKWebView

    private let webCookieStore: WebCookieStore
    private let cookieSynchronizer: NodeSeekWebCookieSynchronizing

    init(
        additionalUserScripts: [WKUserScript] = [],
        cookieSynchronizer: NodeSeekWebCookieSynchronizing? = nil
    ) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController = NodeSeekWebThemeSupport.makeUserContentController(
            additionalScripts: additionalUserScripts
        )

        let webCookieStore = WKWebCookieStoreAdapter(
            store: configuration.websiteDataStore.httpCookieStore
        )
        self.webView = NoBounceWebView(frame: .zero, configuration: configuration)
        self.webCookieStore = webCookieStore
        self.cookieSynchronizer = cookieSynchronizer ?? CookieBridge(webCookieStore: webCookieStore)
    }

    func prepareForInitialLoad(userInterfaceStyle: UIUserInterfaceStyle) async {
        await cookieSynchronizer.syncURLSessionCookiesToWebView()
        await NodeSeekWebThemeSupport.syncPreferredColorSchemeCookie(
            to: webCookieStore,
            userInterfaceStyle: userInterfaceStyle
        )
    }

    func syncCookiesToURLSession() async {
        await cookieSynchronizer.syncWebViewCookiesToURLSession()
    }
}
