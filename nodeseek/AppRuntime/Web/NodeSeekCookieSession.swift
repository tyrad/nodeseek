//
//  NodeSeekCookieSession.swift
//  nodeseek
//

import UIKit

@MainActor
protocol NodeSeekCookieSessionManaging: AnyObject {
    func prepareWebViewLoad(userInterfaceStyle: UIUserInterfaceStyle?) async
    func captureWebViewSession() async
    func prepareHTTPLoad() async
    func prepareMediaRequest() async
    func clearLoginSession() async
}

extension NodeSeekCookieSessionManaging {
    func prepareWebViewLoad() async {
        await prepareWebViewLoad(userInterfaceStyle: nil)
    }
}

@MainActor
final class NodeSeekCookieSession: NodeSeekCookieSessionManaging {
    private let bridge: CookieBridge
    private let webCookieStore: WebCookieStore?

    convenience init(webCookieStore: WebCookieStore? = nil) {
        self.init(
            bridge: CookieBridge(webCookieStore: webCookieStore),
            webCookieStore: webCookieStore
        )
    }

    init(bridge: CookieBridge, webCookieStore: WebCookieStore? = nil) {
        self.bridge = bridge
        self.webCookieStore = webCookieStore
    }

    func prepareWebViewLoad(userInterfaceStyle: UIUserInterfaceStyle?) async {
        await bridge.syncURLSessionCookiesToWebView()
        guard let userInterfaceStyle, let webCookieStore else { return }
        await NodeSeekWebThemeSupport.syncPreferredColorSchemeCookie(
            to: webCookieStore,
            userInterfaceStyle: userInterfaceStyle
        )
    }

    func captureWebViewSession() async {
        await bridge.syncWebViewCookiesToURLSession()
    }

    func prepareHTTPLoad() async {
        await bridge.syncWebViewCookiesToURLSession()
    }

    func prepareMediaRequest() async {
        await bridge.syncWebViewCookiesToURLSession()
    }

    func clearLoginSession() async {
        await bridge.clearSession()
    }
}
