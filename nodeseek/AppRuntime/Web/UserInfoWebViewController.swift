//
//  UserInfoWebViewController.swift
//  nodeseek
//
//  Created by Codex on 2026/4/30.
//

import SafariServices
import UIKit
import WebKit

final class UserInfoWebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private let profileURL: URL
    private let webView: WKWebView
    private let cookieBridge: CookieBridge
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private var loadTask: Task<Void, Never>?

    init(profileURL: URL) {
        self.profileURL = Self.normalizedProfileURL(profileURL)

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController = Self.makeUserContentController()
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        self.cookieBridge = CookieBridge(
            webCookieStore: WKWebCookieStoreAdapter(
                store: configuration.websiteDataStore.httpCookieStore
            )
        )
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        cancelLoad()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "用户主页"
        view.backgroundColor = .systemBackground
        configureNavigationItems()
        configureWebView()
        loadProfilePage()
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

    private static func makeUserContentController() -> WKUserContentController {
        let controller = WKUserContentController()
        for script in makeUserScripts() {
            controller.addUserScript(script)
        }
        return controller
    }

    private func configureNavigationItems() {
        let copyAction = UIAction(
            title: "复制链接",
            image: UIImage(systemName: "doc.on.doc")
        ) { [weak self] _ in
            self?.copyCurrentPageURL()
        }
        let openAction = UIAction(
            title: "系统浏览器打开",
            image: UIImage(systemName: "safari")
        ) { [weak self] _ in
            self?.openInSystemBrowser()
        }

        let menu = UIMenu(children: [copyAction, openAction])
        let moreButton = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            primaryAction: nil,
            menu: menu
        )
        moreButton.accessibilityLabel = "用户页更多操作"
        navigationItem.rightBarButtonItem = moreButton
    }

    private func configureWebView() {
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.customUserAgent = WebRequestFingerprint.userAgent
        webView.scrollView.backgroundColor = .systemBackground
        webView.translatesAutoresizingMaskIntoConstraints = false

        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(webView)
        view.addSubview(loadingIndicator)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func loadProfilePage() {
        loadingIndicator.startAnimating()
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await cookieBridge.syncURLSessionCookiesToWebView()
            guard !Task.isCancelled else { return }

            var request = URLRequest(url: profileURL)
            request.timeoutInterval = 20
            request.cachePolicy = .reloadRevalidatingCacheData
            WebRequestFingerprint.applyHTMLHeaders(to: &request)
            webView.load(request)
        }
    }

    private func cancelLoad() {
        loadTask?.cancel()
        loadTask = nil
    }

    private func currentPageURL() -> URL {
        webView.url ?? profileURL
    }

    private func copyCurrentPageURL() {
        UIPasteboard.general.url = currentPageURL()
    }

    private func openInSystemBrowser() {
        UIApplication.shared.open(currentPageURL(), options: [:], completionHandler: nil)
    }

    private func openInSafariViewController(_ url: URL) {
        present(SFSafariViewController(url: url), animated: true)
    }

    private func isNodeSeekHost(_ url: URL) -> Bool {
        NodeSeekSite.isNodeSeekHost(url)
    }

    private func handleExternalNavigationIfNeeded(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        guard isNodeSeekHost(url) == false else { return false }
        openInSafariViewController(url)
        return true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadingIndicator.stopAnimating()
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

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        loadingIndicator.stopAnimating()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        loadingIndicator.stopAnimating()
    }

    func webView(
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

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        guard view.window != nil else {
            completionHandler()
            return
        }

        let alert = UIAlertController(title: webDialogTitle(from: frame), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            completionHandler()
        })
        present(alert, animated: true)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        guard view.window != nil else {
            completionHandler(false)
            return
        }

        let alert = UIAlertController(title: webDialogTitle(from: frame), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in
            completionHandler(false)
        })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            completionHandler(true)
        })
        present(alert, animated: true)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        guard view.window != nil else {
            completionHandler(nil)
            return
        }

        let alert = UIAlertController(title: webDialogTitle(from: frame), message: prompt, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = defaultText
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in
            completionHandler(nil)
        })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak alert] _ in
            completionHandler(alert?.textFields?.first?.text)
        })
        present(alert, animated: true)
    }

    private func webDialogTitle(from frame: WKFrameInfo) -> String {
        frame.request.url?.host ?? "网页"
    }
}
