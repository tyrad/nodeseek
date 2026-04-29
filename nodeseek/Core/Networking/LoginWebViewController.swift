//
//  LoginWebViewController.swift
//  nodeseek
//

import UIKit
import WebKit

@MainActor
protocol LoginCookieSynchronizing: AnyObject {
    func syncURLSessionCookiesToWebView() async
    func syncWebViewCookiesToURLSession() async
}

extension CookieBridge: LoginCookieSynchronizing {}

final class LoginWebViewController: UIViewController, WKNavigationDelegate {
    private static let loginURL = URL(string: "https://www.nodeseek.com/signIn.html")!

    private let cookieSynchronizer: LoginCookieSynchronizing
    private let onClose: @MainActor () -> Void
    private let webView: WKWebView
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private var loadTask: Task<Void, Never>?

    private let hintContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = .secondarySystemBackground
        view.layer.cornerRadius = 12
        view.layer.cornerCurve = .continuous
        view.layer.borderWidth = 0.5
        view.layer.borderColor = UIColor.separator.cgColor
        view.accessibilityIdentifier = "login-hint-container"
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let hintIconView: UIImageView = {
        let configuration = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        let imageView = UIImageView(image: UIImage(systemName: "checkmark.seal.fill", withConfiguration: configuration))
        imageView.tintColor = .label
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let hintLabel: UILabel = {
        let label = UILabel()
        label.text = "登录成功后关闭当前页面即可"
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .label
        label.numberOfLines = 0
        label.textAlignment = .natural
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    init(
        cookieSynchronizer: LoginCookieSynchronizing? = nil,
        onClose: @escaping @MainActor () -> Void = {}
    ) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        self.cookieSynchronizer = cookieSynchronizer ?? CookieBridge(
            webCookieStore: WKWebCookieStoreAdapter(
                store: configuration.websiteDataStore.httpCookieStore
            )
        )
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        cancelLoginLoad()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "登录 NodeSeek"
        view.backgroundColor = .systemBackground
        configureNavigationItems()
        configureWebView()
        loadLoginPage()
    }

    private func configureNavigationItems() {
        let closeButton = UIBarButtonItem(
            title: "关闭",
            style: .done,
            target: self,
            action: #selector(closeTapped)
        )
        closeButton.accessibilityLabel = "关闭登录页"
        navigationItem.rightBarButtonItem = closeButton
    }

    private func configureWebView() {
        webView.navigationDelegate = self
        webView.customUserAgent = WebRequestFingerprint.userAgent
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
            hintIconView.topAnchor.constraint(greaterThanOrEqualTo: hintContainerView.topAnchor, constant: 12),
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
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await cookieSynchronizer.syncURLSessionCookiesToWebView()
            guard !Task.isCancelled else { return }

            var request = URLRequest(url: Self.loginURL)
            request.timeoutInterval = 20
            request.cachePolicy = .reloadRevalidatingCacheData
            WebRequestFingerprint.applyHTMLHeaders(to: &request)
            webView.load(request)
        }
    }

    @objc private func closeTapped() {
        navigationItem.rightBarButtonItem?.isEnabled = false
        cancelLoginLoad()
        webView.stopLoading()
        webView.navigationDelegate = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            await cookieSynchronizer.syncWebViewCookiesToURLSession()
            onClose()
            closeSelf()
        }
    }

    private func cancelLoginLoad() {
        loadTask?.cancel()
        loadTask = nil
    }

    private func closeSelf() {
        if let navigationController, navigationController.viewControllers.first !== self {
            navigationController.popViewController(animated: true)
            return
        }

        dismiss(animated: true)
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
}
