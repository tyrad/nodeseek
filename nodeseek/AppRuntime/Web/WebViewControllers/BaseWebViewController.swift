//
//  BaseWebViewController.swift
//  nodeseek
//

import UIKit
import WebKit

class BaseWebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    let initialURL: URL
    let automaticallyLoadsPage: Bool
    let webViewContext: NodeSeekWebViewContext
    let webView: WKWebView
    let loadingIndicator = UIActivityIndicatorView(style: .medium)

    private let pageTitle: String
    var loadTask: Task<Void, Never>?

    var moreMenuAccessibilityLabel: String {
        "网页更多操作"
    }

    var usesCustomUserAgent: Bool {
        true
    }

    init(
        initialURL: URL,
        pageTitle: String,
        automaticallyLoadsPage: Bool = true,
        additionalUserScripts: [WKUserScript] = [],
        cookieSession: NodeSeekCookieSessionManaging? = nil
    ) {
        self.initialURL = initialURL
        self.pageTitle = pageTitle
        self.automaticallyLoadsPage = automaticallyLoadsPage

        let webViewContext = NodeSeekWebViewContext(
            additionalUserScripts: additionalUserScripts,
            cookieSession: cookieSession
        )
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
        title = pageTitle
        view.backgroundColor = .systemBackground
        configureNavigationItems()
        configureWebView()
        if automaticallyLoadsPage {
            loadInitialPage()
        }
    }

    func configureNavigationItems() {
        navigationItem.rightBarButtonItem = WebPageMoreMenuFactory.makeMoreButton(
            accessibilityLabel: moreMenuAccessibilityLabel,
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

    func configureWebView() {
        configureWebViewProperties()
        installWebViewLayout(topAnchor: view.topAnchor)
    }

    func configureWebViewProperties() {
        webView.navigationDelegate = self
        webView.uiDelegate = self
        if usesCustomUserAgent {
            webView.customUserAgent = WebRequestFingerprint.userAgent
        }
        webView.scrollView.backgroundColor = .systemBackground
        webView.translatesAutoresizingMaskIntoConstraints = false

        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
    }

    func installWebViewLayout(topAnchor: NSLayoutYAxisAnchor) {
        view.addSubview(webView)
        view.addSubview(loadingIndicator)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    func loadInitialPage() {
        loadPage(initialURL)
    }

    func loadPage(_ url: URL) {
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

    func cancelLoad() {
        loadTask?.cancel()
        loadTask = nil
    }

    func reloadCurrentPage() {
        guard webView.url != nil else {
            loadInitialPage()
            return
        }
        loadingIndicator.startAnimating()
        webView.reload()
    }

    func currentPageURL() -> URL {
        webView.url ?? initialURL
    }

    func copyCurrentPageURL() {
        UIPasteboard.general.url = currentPageURL()
    }

    func openInSystemBrowser() {
        UIApplication.shared.open(currentPageURL(), options: [:], completionHandler: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadingIndicator.stopAnimating()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
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
        webView.load(navigationAction.request)
        return nil
    }

    // MARK: - JavaScript Dialogs

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

        let alert = Self.makeJavaScriptAlert(
            title: Self.javaScriptDialogTitle(for: frame.request.url),
            message: message,
            completionHandler: completionHandler
        )
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

        let alert = Self.makeJavaScriptConfirmAlert(
            title: Self.javaScriptDialogTitle(for: frame.request.url),
            message: message,
            completionHandler: completionHandler
        )
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

        let alert = Self.makeJavaScriptTextInputAlert(
            title: Self.javaScriptDialogTitle(for: frame.request.url),
            prompt: prompt,
            defaultText: defaultText,
            completionHandler: completionHandler
        )
        present(alert, animated: true)
    }

    static func javaScriptDialogTitle(for url: URL?) -> String {
        url?.host ?? "网页"
    }

    static func makeJavaScriptAlert(
        title: String,
        message: String,
        completionHandler: @escaping () -> Void
    ) -> UIAlertController {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            completionHandler()
        })
        return alert
    }

    static func makeJavaScriptConfirmAlert(
        title: String,
        message: String,
        completionHandler: @escaping (Bool) -> Void
    ) -> UIAlertController {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in
            completionHandler(false)
        })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            completionHandler(true)
        })
        return alert
    }

    static func makeJavaScriptTextInputAlert(
        title: String,
        prompt: String,
        defaultText: String?,
        completionHandler: @escaping (String?) -> Void
    ) -> UIAlertController {
        let alert = UIAlertController(title: title, message: prompt, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = defaultText
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in
            completionHandler(nil)
        })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak alert] _ in
            completionHandler(alert?.textFields?.first?.text)
        })
        return alert
    }
}


enum WebPageMoreMenuFactory {
    static func makeMoreButton(
        accessibilityLabel: String,
        onRefresh: @escaping @MainActor () -> Void,
        onCopyLink: @escaping @MainActor () -> Void,
        onOpenInSystemBrowser: @escaping @MainActor () -> Void
    ) -> UIBarButtonItem {
        let refreshAction = UIAction(
            title: "刷新",
            image: UIImage(systemName: "arrow.clockwise")
        ) { _ in
            onRefresh()
        }
        let copyAction = UIAction(
            title: "复制链接",
            image: UIImage(systemName: "doc.on.doc")
        ) { _ in
            onCopyLink()
        }
        let openAction = UIAction(
            title: "系统浏览器打开",
            image: UIImage(systemName: "safari")
        ) { _ in
            onOpenInSystemBrowser()
        }

        let button = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            primaryAction: nil,
            menu: UIMenu(children: [refreshAction, copyAction, openAction])
        )
        button.accessibilityLabel = accessibilityLabel
        return button
    }
}
