//
//  HiddenWebViewHTMLClient.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation
import OSLog
import UIKit
import WebKit

enum HiddenWebViewHTMLClientError: Error {
    case timeout
    case noNavigationStarted
    case processTerminated
}

private enum WebViewCachePolicy {
    static let getRequestPolicy: URLRequest.CachePolicy = .reloadRevalidatingCacheData
    static let postRequestPolicy: URLRequest.CachePolicy = .reloadIgnoringLocalCacheData
}

private final class WebViewCacheTuner {
    private static let lock = NSLock()
    private static var tuned = false
    private static let logger = Logger(subsystem: "com.nodeseek.app", category: "HiddenWebViewCache")

    private static let minMemoryCapacity = 64 * 1024 * 1024
    private static let minDiskCapacity = 512 * 1024 * 1024

    static func tuneIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard !tuned else { return }

        let current = URLCache.shared
        let memoryCapacity = max(current.memoryCapacity, minMemoryCapacity)
        let diskCapacity = max(current.diskCapacity, minDiskCapacity)
        URLCache.shared = URLCache(
            memoryCapacity: memoryCapacity,
            diskCapacity: diskCapacity,
            diskPath: "com.nodeseek.web-cache"
        )
        tuned = true
        logger.info("已调优 URLCache 容量 memory=\(memoryCapacity / 1024 / 1024)MB, disk=\(diskCapacity / 1024 / 1024)MB")
    }
}

actor HiddenWebViewRequestLock {
    static let shared = HiddenWebViewRequestLock()

    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !isLocked {
            isLocked = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            isLocked = false
            return
        }

        let next = waiters.removeFirst()
        next.resume()
    }
}

struct HiddenWebViewHTMLClient: HTMLClient {
    private let timeoutInterval: TimeInterval
    private let logger = Logger(subsystem: "com.nodeseek.app", category: "HiddenWebViewHTMLClient")

    init(timeoutInterval: TimeInterval = 20) {
        self.timeoutInterval = timeoutInterval
    }

    func get(_ url: URL) async throws -> HTMLResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeoutInterval
        request.cachePolicy = WebViewCachePolicy.getRequestPolicy
        WebRequestFingerprint.applyHTMLHeaders(to: &request)
        return try await load(request: request)
    }

    func post(_ url: URL, formFields: [String: String]) async throws -> HTMLResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutInterval
        request.cachePolicy = WebViewCachePolicy.postRequestPolicy
        WebRequestFingerprint.applyHTMLHeaders(to: &request)
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = formFields
            .map { key, value in "\(Self.urlEncode(key))=\(Self.urlEncode(value))" }
            .joined(separator: "&")
            .data(using: .utf8)
        return try await load(request: request)
    }

    private static func urlEncode(_ value: String) -> String {
        FormURLEncoder.encode(value)
    }

    private func load(request: URLRequest) async throws -> HTMLResponse {
        let requestLock = HiddenWebViewRequestLock.shared
        await requestLock.acquire()
        logger.info("准备通过隐藏 WebView 抓取 HTML: \(request.url?.absoluteString ?? "nil")")
        do {
            let loader = await MainActor.run {
                HiddenWebViewLoader.shared
            }
            let response = try await loader.load(request: request, timeoutInterval: timeoutInterval)
            await requestLock.release()
            return response
        } catch {
            await requestLock.release()
            throw error
        }
    }
}

@MainActor
final class HiddenWebViewLoader: NSObject, WKNavigationDelegate {
    static let shared = HiddenWebViewLoader()

    private var timeoutInterval: TimeInterval = 20
    private let webView: WKWebView
    private let cookieBridge: CookieBridge
    private var continuation: CheckedContinuation<HTMLResponse, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var htmlPollingTask: Task<Void, Never>?
    private var statusCode = 200
    private var headers: [String: String] = [:]
    private var initialURL: URL?
    private var completed = false
    private var challengePollCount = 0
    private let maxChallengePollCount = 10
    private let challengePollIntervalNanoseconds: UInt64 = 1_200_000_000
    private var debugOverlayConstraints: [NSLayoutConstraint] = []
    private let logger = Logger(subsystem: "com.nodeseek.app", category: "HiddenWebViewLoader")

    private override init() {
        WebViewCacheTuner.tuneIfNeeded()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView.customUserAgent = WebRequestFingerprint.userAgent
        self.cookieBridge = CookieBridge(
            webCookieStore: WKWebCookieStoreAdapter(
                store: configuration.websiteDataStore.httpCookieStore
            )
        )
        super.init()
        webView.navigationDelegate = self
    }

    deinit {
        timeoutTask?.cancel()
        htmlPollingTask?.cancel()
    }

    func load(request: URLRequest, timeoutInterval: TimeInterval) async throws -> HTMLResponse {
        self.timeoutInterval = timeoutInterval
        resetForNextRequest()
        initialURL = request.url
        updateDebugOverlayIfNeeded()
        logger.info("开始加载页面: \(request.url?.absoluteString ?? "nil"), timeout: \(Int(self.timeoutInterval))s")
        await cookieBridge.syncURLSessionCookiesToWebView()
        logger.info("已同步 URLSession Cookie 到 WebView")

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            scheduleTimeout()
            let navigation = webView.load(request)
            if navigation == nil {
                logger.error("webView.load 返回 nil，导航未开始")
                resolve(.failure(HiddenWebViewHTMLClientError.noNavigationStarted))
            }
        }
    }

    func submitComment(pageURL: URL, content: String, timeoutInterval: TimeInterval) async throws -> CommentAutomationResponse {
        var request = URLRequest(url: pageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = timeoutInterval
        request.cachePolicy = WebViewCachePolicy.getRequestPolicy
        WebRequestFingerprint.applyHTMLHeaders(to: &request)

        let response = try await load(request: request, timeoutInterval: timeoutInterval)
        if let challenge = ChallengeDetector().detect(response: response) {
            return CommentAutomationResponse(
                ok: false,
                statusCode: response.statusCode,
                message: Self.message(for: challenge),
                reason: "challenge"
            )
        }

        let result = try await evaluateCommentSubmissionScript(content: content, timeoutInterval: timeoutInterval)
        await cookieBridge.syncWebViewCookiesToURLSession()
        return result
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        logger.info("WebView didFinish: \(webView.url?.absoluteString ?? "nil")")
        htmlPollingTask?.cancel()
        htmlPollingTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                do {
                    let html = try await self.readOuterHTML()
                    let hasUsableContent = ChallengeDetector.containsUsableNodeSeekHTML(html)
                    let isChallengePage = Self.isChallengePage(html: html)
                    let shouldResolve = !isChallengePage || self.challengePollCount >= self.maxChallengePollCount

                    if hasUsableContent || shouldResolve {
                        logger.info("结束轮询，challenge 状态: \(isChallengePage), usableContent: \(hasUsableContent), pollCount: \(self.challengePollCount)")
                        await self.cookieBridge.syncWebViewCookiesToURLSession()
                        logger.info("已同步 WebView Cookie 到 URLSession")
                        self.resolve(.success(HTMLResponse(
                            statusCode: self.statusCode,
                            headers: self.headers,
                            finalURL: self.webView.url ?? self.initialURL ?? URL(string: "about:blank")!,
                            html: html
                        )))
                        return
                    }

                    self.challengePollCount += 1
                    self.logger.warning("仍在 challenge 页面，usableContent=\(hasUsableContent)，继续轮询: \(self.challengePollCount)/\(self.maxChallengePollCount)")
                    try? await Task.sleep(nanoseconds: self.challengePollIntervalNanoseconds)
                } catch {
                    self.logger.error("轮询 outerHTML 失败: \(error.localizedDescription)")
                    self.resolve(.failure(error))
                    return
                }
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        if let response = navigationResponse.response as? HTTPURLResponse {
            statusCode = response.statusCode
            headers = response.allHeaderFields.reduce(into: [String: String]()) { result, item in
                guard let key = item.key as? String else { return }
                result[key] = String(describing: item.value)
            }
            logger.info("收到响应: status=\(response.statusCode), url=\(response.url?.absoluteString ?? "nil")")
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        logger.error("导航失败 didFail: \(error.localizedDescription)")
        resolve(.failure(error))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        logger.error("导航失败 didFailProvisionalNavigation: \(error.localizedDescription)")
        resolve(.failure(error))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        logger.error("Web 内容进程终止")
        resolve(.failure(HiddenWebViewHTMLClientError.processTerminated))
    }

    private func scheduleTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            guard let self else { return }
            let nanoseconds = UInt64(timeoutInterval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            self.timeout()
        }
    }

    private func timeout() {
        logger.error("隐藏 WebView 抓取超时")
        resolve(.failure(HiddenWebViewHTMLClientError.timeout))
    }

    private func resolve(_ result: Result<HTMLResponse, Error>) {
        guard !completed, let continuation else { return }
        completed = true
        timeoutTask?.cancel()
        htmlPollingTask?.cancel()
        timeoutTask = nil
        htmlPollingTask = nil
        self.continuation = nil

        switch result {
        case .success(let response):
            logger.info("抓取完成: status=\(response.statusCode), htmlLength=\(response.html.count), finalURL=\(response.finalURL.absoluteString)")
            continuation.resume(returning: response)
        case .failure(let error):
            logger.error("抓取失败收敛: \(error.localizedDescription)")
            continuation.resume(throwing: error)
        }
    }

    private func readOuterHTML() async throws -> String {
        let htmlAny = try await webView.evaluateJavaScript("document.documentElement.outerHTML")
        return htmlAny as? String ?? ""
    }

    private func evaluateCommentSubmissionScript(content: String, timeoutInterval: TimeInterval) async throws -> CommentAutomationResponse {
        let timeoutMilliseconds = max(5_000, Int(timeoutInterval * 1_000))
        let result: Any?
        do {
            result = try await webView.callAsyncJavaScript(
                CommentSubmissionAutomationScript.source,
                arguments: [
                    "commentText": content,
                    "timeoutMs": timeoutMilliseconds
                ],
                in: nil,
                contentWorld: .page
            )
        } catch {
            let nsError = error as NSError
            logger.error("评论脚本执行异常: domain=\(nsError.domain, privacy: .public), code=\(nsError.code), info=\(String(describing: nsError.userInfo), privacy: .public)")
            return CommentAutomationResponse(
                ok: false,
                message: error.localizedDescription,
                reason: "javascript_exception"
            )
        }

        guard let object = result as? [String: Any] else {
            return CommentAutomationResponse(ok: false, message: nil, reason: "invalid_script_result")
        }

        let ok = object["ok"] as? Bool ?? false
        let statusCode = (object["statusCode"] as? NSNumber)?.intValue ?? object["statusCode"] as? Int
        let message = object["message"] as? String
        let reason = object["reason"] as? String ?? "unknown"
        let body = object["body"] as? String
        return CommentAutomationResponse(
            ok: ok,
            statusCode: statusCode,
            message: message,
            reason: reason,
            body: body
        )
    }

    private static func message(for challenge: ChallengeKind) -> String {
        switch challenge {
        case .loginRequired:
            return "请先登录后再发表评论。"
        case .cloudflare:
            return "站点当前需要 Cloudflare 验证，请稍后重试。"
        case .blocked:
            return "站点当前返回了拦截页面，请稍后重试。"
        case .unsupported:
            return "站点当前返回了无法处理的验证页面，请稍后重试。"
        }
    }

    private static func isChallengePage(html: String) -> Bool {
        ChallengeDetector.containsCloudflareChallengeHTML(html)
    }

    private func resetForNextRequest() {
        webView.stopLoading()
        timeoutTask?.cancel()
        htmlPollingTask?.cancel()
        timeoutTask = nil
        htmlPollingTask = nil
        continuation = nil
        initialURL = nil
        statusCode = 200
        headers = [:]
        completed = false
        challengePollCount = 0
    }

    private func updateDebugOverlayIfNeeded() {
        guard NodeSeekDebugConfig.enableWebViewDebugOverlay else {
            detachDebugOverlayIfNeeded()
            return
        }

        guard let keyWindow = Self.currentKeyWindow() else { return }
        if webView.superview !== keyWindow {
            detachDebugOverlayIfNeeded()

            webView.translatesAutoresizingMaskIntoConstraints = false
            webView.layer.cornerRadius = 8
            webView.layer.masksToBounds = true
            webView.layer.borderWidth = 1
            webView.layer.borderColor = UIColor.systemRed.cgColor

            keyWindow.addSubview(webView)
            debugOverlayConstraints = [
                webView.bottomAnchor.constraint(
                    equalTo: keyWindow.safeAreaLayoutGuide.bottomAnchor,
                    constant: -NodeSeekDebugConfig.webViewDebugOverlayBottomInset
                ),
                webView.leadingAnchor.constraint(
                    equalTo: keyWindow.safeAreaLayoutGuide.leadingAnchor,
                    constant: NodeSeekDebugConfig.webViewDebugOverlayLeadingInset
                ),
                webView.widthAnchor.constraint(equalToConstant: NodeSeekDebugConfig.webViewDebugOverlaySize.width),
                webView.heightAnchor.constraint(equalToConstant: NodeSeekDebugConfig.webViewDebugOverlaySize.height)
            ]
            NSLayoutConstraint.activate(debugOverlayConstraints)
        }

        keyWindow.bringSubviewToFront(webView)
    }

    private func detachDebugOverlayIfNeeded() {
        NSLayoutConstraint.deactivate(debugOverlayConstraints)
        debugOverlayConstraints = []
        webView.removeFromSuperview()
    }

    private static func currentKeyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }
}
