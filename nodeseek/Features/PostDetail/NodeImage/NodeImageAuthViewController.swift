//
//  NodeImageAuthViewController.swift
//  nodeseek
//
//  Created by Codex on 2026/5/9.
//

import UIKit
import WebKit

enum NodeImageAuthorizationMessage {
    static func apiKey(from body: Any) -> String? {
        guard let rawAPIKey = firstAPIKey(in: body) else { return nil }
        let normalized = NodeImageAPIKeyNormalizer.normalized(rawAPIKey)
        return normalized.isEmpty ? nil : normalized
    }

    private static func firstAPIKey(in value: Any) -> String? {
        if let dictionary = value as? [String: Any] {
            let preferredKeys = ["api_key", "apiKey", "apikey", "x-api-key", "X-API-Key"]
            for key in preferredKeys {
                if let rawAPIKey = dictionary[key] as? String {
                    return rawAPIKey
                }
            }

            for (key, nestedValue) in dictionary {
                let normalizedKey = key
                    .lowercased()
                    .replacingOccurrences(of: "-", with: "_")
                if normalizedKey.contains("api_key"),
                   let rawAPIKey = nestedValue as? String {
                    return rawAPIKey
                }
            }

            for nestedValue in dictionary.values {
                if let rawAPIKey = firstAPIKey(in: nestedValue) {
                    return rawAPIKey
                }
            }
            return nil
        }

        if let array = value as? [Any] {
            for nestedValue in array {
                if let rawAPIKey = firstAPIKey(in: nestedValue) {
                    return rawAPIKey
                }
            }
            return nil
        }

        if let string = value as? String {
            if let data = string.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data),
               let rawAPIKey = firstAPIKey(in: object) {
                return rawAPIKey
            }

            let lowercased = string.lowercased()
            if lowercased.hasPrefix("bearer ") || lowercased.contains("x-api-key") {
                return string
            }
        }

        return nil
    }
}

private enum NodeImageAuthorizationScripts {
    static let messageHandlerName = "nodeImageAuthorization"

    static let bridge = """
    (() => {
      if (window.__nodeSeekNodeImageBridgeInstalled) return;
      window.__nodeSeekNodeImageBridgeInstalled = true;
      const post = (payload) => {
        try {
          window.webkit?.messageHandlers?.nodeImageAuthorization?.postMessage(payload);
        } catch (_) {}
      };
      const requestAPIKey = (reason) => post({ type: 'request-api-key', reason });
      window.addEventListener('message', (event) => {
        post({ type: 'auth-message', origin: event.origin, data: event.data });
        setTimeout(() => requestAPIKey('message'), 250);
        setTimeout(() => requestAPIKey('message-delayed'), 1200);
      });
      window.addEventListener('focus', () => requestAPIKey('focus'));
      document.addEventListener('visibilitychange', () => {
        if (!document.hidden) requestAPIKey('visible');
      });
    })();
    """

    static let startAuthorization = """
    (() => {
      const startButton = document.getElementById('startAuthBtn');
      if (startButton) {
        startButton.click();
        return 'clicked-startAuthBtn';
      }
      window.location.href = 'https://www.nodeseek.com/connect?target=NodeImage';
      return 'fallback-location';
    })();
    """

    static let extractAPIKey = """
    (() => {
      const post = (payload) => {
        try {
          window.webkit?.messageHandlers?.nodeImageAuthorization?.postMessage(payload);
        } catch (_) {}
      };
      const emitAPIKey = (apiKey) => {
        if (apiKey) post({ type: 'api-key', api_key: apiKey });
        return apiKey || '';
      };
      const showAPI = () => {
        const apiButton = document.getElementById('apiBtn');
        if (apiButton) apiButton.click();
      };
      const readInput = () => {
        const input = document.getElementById('apiKeyInput');
        return input && input.value ? input.value : '';
      };
      const readCurrentPage = () => {
        showAPI();
        return emitAPIKey(readInput());
      };

      const immediate = readCurrentPage();
      if (immediate) return immediate;

      let attempts = 0;
      const interval = setInterval(() => {
        attempts += 1;
        const apiKey = readCurrentPage();
        if (apiKey || attempts >= 20) clearInterval(interval);
      }, 250);

      fetch('/api/user/status', { credentials: 'include' })
        .then((response) => response.ok ? response.json() : null)
        .then((data) => post({ type: 'user-status', data }))
        .catch(() => {});

      return '';
    })();
    """
}

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

final class NodeImageAuthViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    private let onAPIKey: @MainActor (String) -> Void
    private let webView = NoBounceWebView(frame: .zero, configuration: WKWebViewConfiguration())
    private var popupWebView: WKWebView?
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private var didComplete = false
    private var didRequestNodeSeekAuthorization = false
    private var pendingExtractionWorkItem: DispatchWorkItem?

    init(onAPIKey: @escaping @MainActor (String) -> Void) {
        self.onAPIKey = onAPIKey
        super.init(nibName: nil, bundle: nil)
        title = "授权 NodeImage"
    }

    deinit {
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: NodeImageAuthorizationScripts.messageHandlerName
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .cancel,
            primaryAction: UIAction { [weak self] _ in
                self?.dismiss(animated: true)
            }
        )
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "填 Key",
            primaryAction: UIAction { [weak self] _ in
                self?.presentManualAPIKeyInput()
            }
        )
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.configuration.userContentController.add(
            WeakScriptMessageHandler(delegate: self),
            name: NodeImageAuthorizationScripts.messageHandlerName
        )
        webView.configuration.userContentController.addUserScript(WKUserScript(
            source: NodeImageAuthorizationScripts.bridge,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        webView.customUserAgent = WebRequestFingerprint.userAgent
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
        loadAuthorizationPage()
    }

    private func loadAuthorizationPage() {
        loadingIndicator.startAnimating()
        var request = URLRequest(url: URL(string: "https://www.nodeimage.com/")!)
        WebRequestFingerprint.applyHTMLHeaders(to: &request)
        webView.load(request)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadingIndicator.stopAnimating()
        if webView === self.webView {
            startNodeImageAuthorizationIfNeeded()
            extractAPIKeyIfPossible()
        } else if webView === popupWebView,
                  webView.url?.host?.lowercased().contains("nodeimage.com") == true {
            popupWebView?.removeFromSuperview()
            popupWebView = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.extractAPIKeyIfPossible()
            }
        }
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

        let popup = NoBounceWebView(frame: .zero, configuration: configuration)
        popup.customUserAgent = WebRequestFingerprint.userAgent
        popup.navigationDelegate = self
        popup.uiDelegate = self
        popup.translatesAutoresizingMaskIntoConstraints = false
        popupWebView?.removeFromSuperview()
        popupWebView = popup
        view.addSubview(popup)
        NSLayoutConstraint.activate([
            popup.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            popup.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            popup.topAnchor.constraint(equalTo: view.topAnchor),
            popup.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard webView === popupWebView else { return }
        popupWebView?.removeFromSuperview()
        popupWebView = nil
        extractAPIKeyIfPossible()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == NodeImageAuthorizationScripts.messageHandlerName else { return }
        if let apiKey = NodeImageAuthorizationMessage.apiKey(from: message.body) {
            completeAuthorization(with: apiKey)
            return
        }
        scheduleAPIKeyExtraction(after: 0.25)
    }

    private func startNodeImageAuthorizationIfNeeded() {
        guard didRequestNodeSeekAuthorization == false else { return }
        guard webView.url?.host?.lowercased().contains("nodeimage.com") == true else { return }
        didRequestNodeSeekAuthorization = true
        webView.evaluateJavaScript(NodeImageAuthorizationScripts.startAuthorization)
        scheduleAPIKeyExtraction(after: 0.8)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.extractAPIKeyIfPossible()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            self?.extractAPIKeyIfPossible()
        }
    }

    private func scheduleAPIKeyExtraction(after delay: TimeInterval) {
        guard didComplete == false else { return }
        pendingExtractionWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.extractAPIKeyIfPossible()
        }
        pendingExtractionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func extractAPIKeyIfPossible() {
        guard didComplete == false else { return }
        guard webView.url?.host?.lowercased().contains("nodeimage.com") == true else { return }
        webView.evaluateJavaScript(NodeImageAuthorizationScripts.extractAPIKey) { [weak self] result, _ in
            Task { @MainActor in
                self?.completeAuthorization(with: (result as? String) ?? "")
            }
        }
    }

    private func completeAuthorization(
        with rawAPIKey: String,
        afterDismissing presentedViewController: UIViewController? = nil
    ) {
        guard didComplete == false else { return }
        let apiKey = NodeImageAPIKeyNormalizer.normalized(rawAPIKey)
        guard apiKey.isEmpty == false else { return }
        didComplete = true

        let notifyAPIKey: @MainActor () -> Void = { [weak self] in
            self?.onAPIKey(apiKey)
        }

        guard let presentedViewController else {
            notifyAPIKey()
            return
        }

        if presentedViewController.isBeingDismissed,
           let transitionCoordinator = presentedViewController.transitionCoordinator {
            transitionCoordinator.animate(alongsideTransition: nil) { _ in
                Task { @MainActor in
                    notifyAPIKey()
                }
            }
            return
        }

        guard presentedViewController.presentingViewController != nil else {
            DispatchQueue.main.async {
                Task { @MainActor in
                    notifyAPIKey()
                }
            }
            return
        }

        presentedViewController.dismiss(animated: true) {
            Task { @MainActor in
                notifyAPIKey()
            }
        }
    }

    private func presentManualAPIKeyInput() {
        let alert = UIAlertController(
            title: "填写 NodeImage API Key",
            message: "如果自动授权没有完成，可在 NodeImage 的 API 页面复制后粘贴。",
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.placeholder = "X-API-Key"
            textField.textContentType = .password
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self, weak alert] _ in
            let alertController = alert
            let rawAPIKey = alertController?.textFields?.first?.text ?? ""
            Task { @MainActor in
                self?.completeAuthorization(
                    with: rawAPIKey,
                    afterDismissing: alertController
                )
            }
        })
        present(alert, animated: true)
    }
}
