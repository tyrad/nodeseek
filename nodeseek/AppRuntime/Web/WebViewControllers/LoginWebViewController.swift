//
//  LoginWebViewController.swift
//  nodeseek
//

import UIKit
import WebKit

final class LoginWebViewController: BaseWebViewController {
    private let onClose: @MainActor () -> Void
    private var isClosing = false
    private var loginDetectionTask: Task<Void, Never>?
    private let readsAccountOnClose: Bool

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
        label.text = "登录成功后将自动关闭"
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .label
        label.numberOfLines = 0
        label.textAlignment = .natural
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    init(
        cookieSession: NodeSeekCookieSessionManaging? = nil,
        automaticallyLoadsPage: Bool = true,
        readsAccountOnClose: Bool = true,
        onClose: @escaping @MainActor () -> Void = {}
    ) {
        self.onClose = onClose
        self.readsAccountOnClose = readsAccountOnClose
        super.init(
            initialURL: NodeSeekSite.loginURL,
            pageTitle: "登录 NodeSeek",
            automaticallyLoadsPage: automaticallyLoadsPage,
            cookieSession: cookieSession
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func configureNavigationItems() {
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        let closeButton = UIBarButtonItem(
            image: UIImage(systemName: "xmark", withConfiguration: symbolConfiguration),
            style: .plain,
            target: self,
            action: #selector(closeTapped)
        )
        closeButton.accessibilityLabel = "关闭登录页"
        closeButton.tintColor = .label
        navigationItem.rightBarButtonItem = closeButton
    }

    override func configureWebView() {
        configureWebViewProperties()
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

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !isClosing else { return }
        loginDetectionTask?.cancel()
        // 登录后账号区域可能异步出现，因此页面可见期间持续检查。
        loginDetectionTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.checkLoginStatus()
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch { return }
            }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        loginDetectionTask?.cancel()
        loginDetectionTask = nil
    }

    private func checkLoginStatus() async {
        guard !isClosing, !webView.isLoading,
              let url = webView.url,
              url.scheme == "https", url.host == NodeSeekSite.baseURL.host,
              let html = await readCurrentPageHTML() else { return }
        await closeIfLoggedIn(html: html)
    }

    func closeIfLoggedIn(html: String) async {
        guard !isClosing, !Task.isCancelled else { return }
        let account = await Task.detached(priority: .userInitiated) {
            try? KannaNodeSeekParser(baseURL: NodeSeekSite.baseURL).parseAccount(html: html)
        }.value
        guard !Task.isCancelled, let account, account.isLoggedIn,
              account.profileURL != nil else { return }
        close(account: account)
    }

    @objc private func closeTapped() {
        close(account: nil)
    }

    private func close(account: AccountResponse?) {
        guard !isClosing else { return }
        isClosing = true
        loginDetectionTask?.cancel()
        loginDetectionTask = nil
        navigationItem.rightBarButtonItem?.isEnabled = false
        cancelLoad()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            await webViewContext.captureWebViewSession()
            if let account {
                await CurrentAccountStore.shared.save(account)
            } else {
                await saveAccountFromCurrentPage()
            }
            NotificationCenter.default.post(name: .nodeSeekLoginSessionDidClose, object: nil)
            onClose()
            closeSelf()
        }
    }

    /// 登录成功后当前页面里已有账号信息，直接解析存入缓存，
    /// 各页面关闭后可立刻显示登录状态，不必等隐藏 WebView 重新抓首页（要好几秒）。
    /// 解析不到（未登录或页面不含账号）就什么都不做，照旧由后台刷新确认。
    private func saveAccountFromCurrentPage() async {
        guard readsAccountOnClose, let html = await readCurrentPageHTML(), html.isEmpty == false else {
            return
        }
        let account = await Task.detached(priority: .userInitiated) {
            try? KannaNodeSeekParser(baseURL: NodeSeekSite.baseURL).parseAccount(html: html)
        }.value
        guard let account, account.isLoggedIn, account.profileURL != nil else { return }
        await CurrentAccountStore.shared.save(account)
        AppLog.debug(.account, "login: 关闭时从页面取到账号 -> \(account.displayName)")
    }

    /// 页面异常时 evaluateJavaScript 可能迟迟不回调，最多等 0.8 秒，避免关闭按钮卡住。
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

    private func closeSelf() {
        if let navigationController, navigationController.viewControllers.first !== self {
            navigationController.popViewController(animated: true)
            return
        }

        dismiss(animated: true)
    }
}
