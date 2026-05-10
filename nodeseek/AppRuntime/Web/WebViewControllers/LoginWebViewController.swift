//
//  LoginWebViewController.swift
//  nodeseek
//

import UIKit
import WebKit

final class LoginWebViewController: BaseWebViewController {
    private let onClose: @MainActor () -> Void

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
        cookieSession: NodeSeekCookieSessionManaging? = nil,
        automaticallyLoadsPage: Bool = true,
        onClose: @escaping @MainActor () -> Void = {}
    ) {
        self.onClose = onClose
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

    @objc private func closeTapped() {
        navigationItem.rightBarButtonItem?.isEnabled = false
        cancelLoad()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            await webViewContext.captureWebViewSession()
            NotificationCenter.default.post(name: .nodeSeekLoginSessionDidClose, object: nil)
            onClose()
            closeSelf()
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
