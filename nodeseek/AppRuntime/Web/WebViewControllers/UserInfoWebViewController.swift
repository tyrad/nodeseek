//
//  UserInfoWebViewController.swift
//  nodeseek
//
//  Created by Codex on 2026/4/30.
//

import UIKit
import WebKit

final class UserInfoWebViewController: BaseWebViewController {
    override var moreMenuAccessibilityLabel: String {
        "用户页更多操作"
    }

    init(profileURL: URL, title: String = "用户主页", automaticallyLoadsPage: Bool = true) {
        super.init(
            initialURL: Self.normalizedProfileURL(profileURL),
            pageTitle: title,
            automaticallyLoadsPage: automaticallyLoadsPage,
            additionalUserScripts: Self.makeUserScripts()
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func makeUserScripts() -> [WKUserScript] {
        WebViewStyleInjectionScriptFactory.makeStyleInjectionScripts(
            css: """
            body > header {
                display: none !important;
            }
            """,
            markerAttribute: "data-nodeseek-user-info-style"
        )
    }

    static func normalizedProfileURL(_ url: URL) -> URL {
        let absoluteURL = url.scheme == nil
            ? URL(string: url.absoluteString, relativeTo: NodeSeekSite.baseURL)?.absoluteURL ?? url
            : url.absoluteURL
        guard absoluteURL.path.hasPrefix("/space/") else { return absoluteURL }
        guard var components = URLComponents(url: absoluteURL, resolvingAgainstBaseURL: true) else { return absoluteURL }
        components.fragment = "/general"
        return components.url ?? absoluteURL
    }

    static func nativePostRoute(for url: URL, baseURL: URL) -> NodeSeekPostRoute? {
        NodeSeekPostRouteResolver.route(for: url, baseURL: baseURL)
    }

    private func openNativePost(_ route: NodeSeekPostRoute) {
        let post = PostSummary(
            id: route.postID,
            title: "帖子 #\(route.postID)",
            url: route.url,
            authorName: "",
            nodeName: nil,
            replyCount: 0,
            lastActivityText: nil
        )
        let viewController = PostDetailRouter.createModule(
            post: post,
            page: route.page,
            initialAnchorID: route.anchorID
        )
        if let navigationController {
            navigationController.pushViewController(viewController, animated: true)
        } else {
            present(UINavigationController(rootViewController: viewController), animated: true)
        }
    }

    private func handleNativePostNavigationIfNeeded(_ url: URL) -> Bool {
        guard let route = Self.nativePostRoute(for: url, baseURL: currentPageURL()) else {
            return false
        }

        openNativePost(route)
        return true
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url,
           handleNativePostNavigationIfNeeded(url) {
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    override func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }
        guard let targetURL = navigationAction.request.url else { return nil }

        if handleNativePostNavigationIfNeeded(targetURL) {
            return nil
        }

        webView.load(navigationAction.request)
        return nil
    }
}
