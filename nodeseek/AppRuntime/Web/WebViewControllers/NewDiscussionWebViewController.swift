//
//  NewDiscussionWebViewController.swift
//  nodeseek
//

import SafariServices
import UIKit
import WebKit

final class NewDiscussionWebViewController: BaseWebViewController {
    static let newDiscussionURL = NodeSeekSite.newDiscussionURL

    private var lastResponseStatusCode: Int?
    private var hasPresentedLoginRequiredHint = false

    override var moreMenuAccessibilityLabel: String {
        "发帖页更多操作"
    }

    init(
        targetURL: URL = NewDiscussionWebViewController.newDiscussionURL,
        automaticallyLoadsPage: Bool = true
    ) {
        super.init(
            initialURL: targetURL,
            pageTitle: "发帖",
            automaticallyLoadsPage: automaticallyLoadsPage
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadInitialPage() {
        lastResponseStatusCode = nil
        hasPresentedLoginRequiredHint = false
        loadPage(initialURL)
    }

    private func openInSafariViewController(_ url: URL) {
        present(SFSafariViewController(url: url), animated: true)
    }

    private func presentLoginRequiredHint(message: String) {
        guard !hasPresentedLoginRequiredHint else { return }
        guard view.window != nil else { return }
        hasPresentedLoginRequiredHint = true

        let alert = UIAlertController(title: "需要登录", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "去登录", style: .default) { [weak self] _ in
            let loginViewController = LoginWebViewController()
            if let navigationController = self?.navigationController {
                navigationController.pushViewController(loginViewController, animated: true)
                return
            }
            self?.present(UINavigationController(rootViewController: loginViewController), animated: true)
        })
        present(alert, animated: true)
    }

    private func checkLoginRequiredFallback() {
        let statusCode = lastResponseStatusCode
        webView.evaluateJavaScript("document.body.innerText") { [weak self] result, _ in
            guard let self else { return }
            let responseText = result as? String ?? ""
            guard let message = Self.loginRequiredMessage(
                statusCode: statusCode,
                responseText: responseText
            ) else {
                return
            }
            self.presentLoginRequiredHint(message: message)
        }
    }

    private func handleExternalNavigationIfNeeded(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        guard NodeSeekSite.isNodeSeekHost(url) == false else { return false }
        openInSafariViewController(url)
        return true
    }

    override func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        super.webView(webView, didFinish: navigation)
        checkLoginRequiredFallback()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        lastResponseStatusCode = (navigationResponse.response as? HTTPURLResponse)?.statusCode
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url,
           handleExternalNavigationIfNeeded(url) {
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

        if handleExternalNavigationIfNeeded(targetURL) {
            return nil
        }

        webView.load(navigationAction.request)
        return nil
    }

    static func loginRequiredMessage(statusCode: Int?, responseText: String) -> String? {
        guard statusCode == 404 else { return nil }
        guard responseText.uppercased().contains("USER NOT FOUND") else { return nil }
        return "用户可能还未登录，请先登录。"
    }
}
