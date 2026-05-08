//
//  CookieSharedWebViewController.swift
//  nodeseek
//
//  Created by Codex on 2026/4/30.
//

import SafariServices
import UIKit
import WebKit

final class CookieSharedWebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private let url: URL
    private let automaticallyLoadsPage: Bool
    private let webViewContext: NodeSeekWebViewContext
    private let webView: WKWebView
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private var loadTask: Task<Void, Never>?

    init(url: URL, automaticallyLoadsPage: Bool = true) {
        self.url = url
        self.automaticallyLoadsPage = automaticallyLoadsPage
        let webViewContext = NodeSeekWebViewContext()
        self.webViewContext = webViewContext
        self.webView = webViewContext.webView
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
        view.backgroundColor = .systemBackground
        title = "网页"
        configureNavigationItems()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)

        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        if automaticallyLoadsPage {
            loadPage()
        }
    }

    private func configureNavigationItems() {
        navigationItem.rightBarButtonItem = WebPageMoreMenuFactory.makeMoreButton(
            accessibilityLabel: "网页更多操作",
            onRefresh: { [weak self] in
                self?.reloadCurrentPage()
            },
            onCopyLink: { [weak self] in
                self?.copyCurrentPageURL()
            },
            onOpenInSystemBrowser: { [weak self] in
                self?.openInSystemBrowser()
            }
        )
    }

    private func loadPage() {
        cancelLoad()
        loadingIndicator.startAnimating()
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await webViewContext.prepareForInitialLoad(userInterfaceStyle: traitCollection.userInterfaceStyle)
            guard !Task.isCancelled else { return }

            var request = URLRequest(url: url)
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

    private func reloadCurrentPage() {
        guard webView.url != nil else {
            loadPage()
            return
        }
        loadingIndicator.startAnimating()
        webView.reload()
    }

    private func currentPageURL() -> URL {
        webView.url ?? url
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

    static func nativePostRoute(for url: URL, baseURL: URL) -> NodeSeekPostRoute? {
        NodeSeekPostRouteResolver.route(for: url, baseURL: baseURL)
    }

    private func handleNativePostNavigationIfNeeded(_ url: URL) -> Bool {
        guard let route = Self.nativePostRoute(for: url, baseURL: currentPageURL()) else {
            return false
        }

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
        return true
    }

    private func handleExternalNavigationIfNeeded(_ url: URL) -> Bool {
        guard let destination = PostDetailLinkResolver.destination(for: url, baseURL: self.url) else {
            return false
        }

        guard case .safari(let safariURL) = destination else {
            return false
        }

        openInSafariViewController(safariURL)
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
           handleNativePostNavigationIfNeeded(url) {
            decisionHandler(.cancel)
            return
        }

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

        if handleNativePostNavigationIfNeeded(targetURL) {
            return nil
        }

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

#if DEBUG
extension CookieSharedWebViewController {
    var testInitialURL: URL {
        url
    }
}
#endif
