//
//  AddAccountWebViewController.swift
//  nodeseek
//

import UIKit
import WebKit

/// 独立隔离的添加/重登账号页面：使用 nonPersistent() 沙盒并绕过全局 NodeSeekCookieSession，
/// 避免把当前活跃账号的 Cookie 注入登录页或在中途取消时污染原会话。
final class AddAccountWebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private let cloudflareCookiesProvider: @MainActor () async -> [HTTPCookie]
    private let onComplete: @MainActor (AccountResponse, [HTTPCookie]) -> Void
    private let onCancel: @MainActor () -> Void

    private let webView: WKWebView
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private var isClosing = false
    private var loadTask: Task<Void, Never>?
    private var loginDetectionTask: Task<Void, Never>?

    private let hintContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = .secondarySystemBackground
        view.layer.cornerRadius = 12
        view.layer.cornerCurve = .continuous
        view.layer.borderWidth = 0.5
        view.layer.borderColor = UIColor.separator.cgColor
        view.accessibilityIdentifier = "add-account-hint-container"
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let hintIconView: UIImageView = {
        let configuration = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        let imageView = UIImageView(image: UIImage(systemName: "person.badge.plus", withConfiguration: configuration))
        imageView.tintColor = .label
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let hintLabel: UILabel = {
        let label = UILabel()
        label.text = AccountsL10n.text("在独立会话中登录新账号，取消不会影响当前登录状态")
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.numberOfLines = 0
        label.textAlignment = .natural
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    init(
        pageTitle: String = AccountsL10n.text("添加账号"),
        cloudflareCookiesProvider: @escaping @MainActor () async -> [HTTPCookie] = {
            await AccountSwitchCoordinator.shared.exportCloudflareCookies()
        },
        onComplete: @escaping @MainActor (AccountResponse, [HTTPCookie]) -> Void,
        onCancel: @escaping @MainActor () -> Void = {}
    ) {
        self.cloudflareCookiesProvider = cloudflareCookiesProvider
        self.onComplete = onComplete
        self.onCancel = onCancel

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController = NodeSeekWebThemeSupport.makeUserContentController()
        let webView = NoBounceWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = WebRequestFingerprint.userAgent
        self.webView = webView

        super.init(nibName: nil, bundle: nil)
        title = pageTitle
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
        loginDetectionTask?.cancel()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureNavigationItems()
        configureLayout()
        loadLoginPage()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !isClosing else { return }
        loginDetectionTask?.cancel()
        loginDetectionTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.checkLoginStatus()
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }
            }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        loginDetectionTask?.cancel()
        loginDetectionTask = nil
    }

    private func configureNavigationItems() {
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        let closeButton = UIBarButtonItem(
            image: UIImage(systemName: "xmark", withConfiguration: symbolConfiguration),
            style: .plain,
            target: self,
            action: #selector(closeTapped)
        )
        closeButton.accessibilityLabel = AccountsL10n.text("关闭")
        closeButton.accessibilityIdentifier = "add-account-close-button"
        closeButton.tintColor = .label
        navigationItem.rightBarButtonItem = closeButton
    }

    private func configureLayout() {
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.scrollView.backgroundColor = .systemBackground
        webView.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false

        hintContainerView.addSubview(hintIconView)
        hintContainerView.addSubview(hintLabel)
        view.addSubview(hintContainerView)
        view.addSubview(webView)
        view.addSubview(loadingIndicator)

        NSLayoutConstraint.activate([
            hintContainerView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 14),
            hintContainerView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
            hintContainerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),

            hintIconView.leadingAnchor.constraint(equalTo: hintContainerView.leadingAnchor, constant: 14),
            hintIconView.centerYAnchor.constraint(equalTo: hintContainerView.centerYAnchor),
            hintIconView.widthAnchor.constraint(equalToConstant: 22),
            hintIconView.heightAnchor.constraint(equalToConstant: 22),

            hintLabel.leadingAnchor.constraint(equalTo: hintIconView.trailingAnchor, constant: 10),
            hintLabel.trailingAnchor.constraint(equalTo: hintContainerView.trailingAnchor, constant: -14),
            hintLabel.topAnchor.constraint(equalTo: hintContainerView.topAnchor, constant: 12),
            hintLabel.bottomAnchor.constraint(equalTo: hintContainerView.bottomAnchor, constant: -12),

            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: hintContainerView.bottomAnchor, constant: 10),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func loadLoginPage() {
        loadingIndicator.startAnimating()
        loadTask?.cancel()
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let cookieStore = WKWebCookieStoreAdapter(
                store: self.webView.configuration.websiteDataStore.httpCookieStore
            )
            // 仅注入 Cloudflare 过盾 Cookie 与主题 Cookie，绝不注入当前活跃账号 Cookie。
            let cloudflareCookies = await self.cloudflareCookiesProvider()
            for cookie in cloudflareCookies {
                await cookieStore.setCookie(cookie)
            }
            await NodeSeekWebThemeSupport.syncPreferredColorSchemeCookie(
                to: cookieStore,
                userInterfaceStyle: self.traitCollection.userInterfaceStyle
            )
            guard !Task.isCancelled else { return }

            var request = URLRequest(url: NodeSeekSite.loginURL)
            WebRequestFingerprint.applyHTMLHeaders(to: &request)
            self.webView.load(request)
        }
    }

    private func checkLoginStatus() async {
        guard !isClosing, !webView.isLoading,
              let url = webView.url,
              url.scheme == "https",
              url.host == NodeSeekSite.baseURL.host,
              let html = await readCurrentPageHTML() else { return }
        await finishIfLoggedIn(html: html)
    }

    private func finishIfLoggedIn(html: String) async {
        guard !isClosing, !Task.isCancelled else { return }
        let account = await Task.detached(priority: .userInitiated) {
            try? KannaNodeSeekParser(baseURL: NodeSeekSite.baseURL).parseAccount(html: html)
        }.value
        guard !Task.isCancelled, let account, account.isLoggedIn, account.nodeSeekUID != nil else { return }
        finish(detectedAccount: account)
    }

    @objc private func closeTapped() {
        finish(detectedAccount: nil)
    }

    private func finish(detectedAccount: AccountResponse?) {
        guard !isClosing else { return }
        isClosing = true
        loginDetectionTask?.cancel()
        loginDetectionTask = nil
        loadTask?.cancel()
        loadTask = nil
        navigationItem.rightBarButtonItem?.isEnabled = false

        Task { @MainActor [weak self] in
            guard let self else { return }
            let resolvedAccount: AccountResponse?
            if let detectedAccount {
                resolvedAccount = detectedAccount
            } else if let html = await self.readCurrentPageHTML(), html.isEmpty == false {
                // 用户刚登完顺手点关闭时兜底检查一次页面，已登录则算成功，否则按取消零副作用退出。
                let parsed = await Task.detached(priority: .userInitiated) {
                    try? KannaNodeSeekParser(baseURL: NodeSeekSite.baseURL).parseAccount(html: html)
                }.value
                resolvedAccount = (parsed?.isLoggedIn == true && parsed?.nodeSeekUID != nil) ? parsed : nil
            } else {
                resolvedAccount = nil
            }

            let extractedCookies: [HTTPCookie]
            if resolvedAccount != nil {
                let cookieStore = WKWebCookieStoreAdapter(
                    store: self.webView.configuration.websiteDataStore.httpCookieStore
                )
                let allCookies = await cookieStore.allCookies()
                extractedCookies = NodeSeekCookieClassifier.accountSessionCookies(from: allCookies)
            } else {
                extractedCookies = []
            }

            self.webView.stopLoading()
            self.webView.navigationDelegate = nil
            self.webView.uiDelegate = nil

            let dismissCompletion: @MainActor () -> Void = {
                if let resolvedAccount, extractedCookies.isEmpty == false {
                    self.onComplete(resolvedAccount, extractedCookies)
                } else {
                    self.onCancel()
                }
            }

            let container = self.navigationController ?? self
            if container.presentingViewController != nil {
                container.dismiss(animated: true) {
                    Task { @MainActor in
                        dismissCompletion()
                    }
                }
            } else {
                dismissCompletion()
            }
        }
    }

    private func readCurrentPageHTML() async -> String? {
        await withCheckedContinuation { continuation in
            var isResumed = false
            let finish: @MainActor (String?) -> Void = { html in
                guard isResumed == false else { return }
                isResumed = true
                continuation.resume(returning: html)
            }
            webView.evaluateJavaScript(NodeSeekPageScripts.outerHTMLWithCapturedConfig) { result, _ in
                MainActor.assumeIsolated { finish(result as? String) }
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 800_000_000)
                finish(nil)
            }
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loadingIndicator.startAnimating()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadingIndicator.stopAnimating()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadingIndicator.stopAnimating()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadingIndicator.stopAnimating()
    }
}
