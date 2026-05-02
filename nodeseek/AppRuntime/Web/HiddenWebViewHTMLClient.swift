//
//  HiddenWebViewHTMLClient.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation
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
        AppLog.info(.webView, "已调优 URLCache 容量 memory=\(memoryCapacity / 1024 / 1024)MB, disk=\(diskCapacity / 1024 / 1024)MB")
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

enum HiddenWebViewChannel: Hashable, Sendable {
    case shared
    case isolated(UUID)
}

struct HiddenWebViewHTMLClient: HTMLClient {
    private let timeoutInterval: TimeInterval
    private let requestLock: HiddenWebViewRequestLock
    private let channel: HiddenWebViewChannel

    init(
        timeoutInterval: TimeInterval = 20,
        requestLock: HiddenWebViewRequestLock = .shared,
        channel: HiddenWebViewChannel = .shared
    ) {
        self.timeoutInterval = timeoutInterval
        self.requestLock = requestLock
        self.channel = channel
    }

    static func isolated(timeoutInterval: TimeInterval = 20) -> HiddenWebViewHTMLClient {
        HiddenWebViewHTMLClient(
            timeoutInterval: timeoutInterval,
            requestLock: HiddenWebViewRequestLock(),
            channel: .isolated(UUID())
        )
    }

    func get(_ url: URL) async throws -> HTMLResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeoutInterval
        request.cachePolicy = WebViewCachePolicy.getRequestPolicy
        WebRequestFingerprint.applyHTMLHeaders(to: &request)
        if channel == .shared {
            await NodeSeekWebViewPrewarmer.waitForPreloadIfNeeded(for: url)
        }
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
        await requestLock.acquire()
        AppLog.info(.webView, "准备通过隐藏 WebView 抓取 HTML: \(request.url?.absoluteString ?? "nil")")
        do {
            let loader = await MainActor.run {
                HiddenWebViewLoader.loader(for: channel)
            }
            let response = try await loader.load(request: request, timeoutInterval: timeoutInterval)
            await releaseRequestResources()
            return response
        } catch {
            await releaseRequestResources()
            throw error
        }
    }

    private func releaseRequestResources() async {
        await requestLock.release()
        await MainActor.run {
            HiddenWebViewLoader.releaseLoader(for: channel)
        }
    }
}

@MainActor
enum NodeSeekWebViewPrewarmer {
    private static let defaultPostListURL = NodeSeekSite.defaultPostListURL
    private static let defaultPostListPreloadWaitInterval: TimeInterval = 0.45

    static func prewarm() {
        _ = HiddenWebViewLoader.shared
        HiddenWebViewPreloadLoader.shared.preload(url: defaultPostListURL)
    }

    static func waitForPreloadIfNeeded(for url: URL) async {
        guard isDefaultPostListURL(url) else { return }
        await HiddenWebViewPreloadLoader.shared.waitForActivePreload(
            url: url,
            maxWait: defaultPostListPreloadWaitInterval
        )
    }

    private static func isDefaultPostListURL(_ url: URL) -> Bool {
        url.absoluteString == defaultPostListURL.absoluteString
    }
}

@MainActor
private final class HiddenWebViewPreloadLoader: NSObject, WKNavigationDelegate {
    static let shared = HiddenWebViewPreloadLoader()

    private var webView: WKWebView?
    private var navigation: WKNavigation?
    private var timeoutTask: Task<Void, Never>?
    private var activeURL: URL?
    private var preloadWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var preloadWaiterTimeoutTasks: [UUID: Task<Void, Never>] = [:]
    private var didPreload = false

    private override init() {
        super.init()
    }

    deinit {
        timeoutTask?.cancel()
        preloadWaiterTimeoutTasks.values.forEach { $0.cancel() }
    }

    func preload(url: URL, timeoutInterval: TimeInterval = 15) {
        guard !didPreload, navigation == nil else { return }
        didPreload = true
        activeURL = url
        WebViewCacheTuner.tuneIfNeeded()

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = WebRequestFingerprint.userAgent
        webView.navigationDelegate = self
        self.webView = webView

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeoutInterval
        request.cachePolicy = WebViewCachePolicy.getRequestPolicy
        WebRequestFingerprint.applyHTMLHeaders(to: &request)

        AppLog.info(.webView, "预加载 NodeSeek 首屏缓存: \(url.absoluteString)")
        navigation = webView.load(request)
        guard navigation != nil else {
            AppLog.warning(.webView, "预加载未开始: \(url.absoluteString)")
            finishPreload()
            return
        }

        scheduleTimeout(timeoutInterval)
    }

    func waitForActivePreload(url: URL, maxWait: TimeInterval) async {
        guard maxWait > 0, isLoading(url) else { return }

        AppLog.info(.webView, "等待 NodeSeek 首屏缓存预加载完成，最多 \(Int(maxWait * 1000))ms")
        let waiterID = UUID()
        await withCheckedContinuation { continuation in
            guard self.isLoading(url) else {
                continuation.resume()
                return
            }

            self.preloadWaiters[waiterID] = continuation
            self.preloadWaiterTimeoutTasks[waiterID] = Task { @MainActor [weak self] in
                let nanoseconds = UInt64(maxWait * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled else { return }
                AppLog.info(.webView, "NodeSeek 首屏缓存预加载等待超时，继续业务请求")
                self?.resumePreloadWaiter(id: waiterID)
            }
        }
        AppLog.info(.webView, "NodeSeek 首屏缓存预加载等待结束")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === self.navigation else { return }
        AppLog.info(.webView, "NodeSeek 首屏缓存预加载完成: \(webView.url?.absoluteString ?? "nil")")
        finishPreload()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard navigation === self.navigation else { return }
        AppLog.warning(.webView, "NodeSeek 首屏缓存预加载失败: \(error.localizedDescription)")
        finishPreload()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        guard navigation === self.navigation else { return }
        AppLog.warning(.webView, "NodeSeek 首屏缓存预加载 provisional 失败: \(error.localizedDescription)")
        finishPreload()
    }

    private func scheduleTimeout(_ timeoutInterval: TimeInterval) {
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let nanoseconds = UInt64(timeoutInterval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            AppLog.warning(.webView, "NodeSeek 首屏缓存预加载超时")
            webView?.stopLoading()
            finishPreload()
        }
    }

    private func finishPreload() {
        timeoutTask?.cancel()
        timeoutTask = nil
        navigation = nil
        activeURL = nil
        webView?.navigationDelegate = nil
        webView = nil
        resumeAllPreloadWaiters()
    }

    private func isLoading(_ url: URL) -> Bool {
        navigation != nil && activeURL?.absoluteString == url.absoluteString
    }

    private func resumePreloadWaiter(id: UUID) {
        preloadWaiterTimeoutTasks.removeValue(forKey: id)?.cancel()
        preloadWaiters.removeValue(forKey: id)?.resume()
    }

    private func resumeAllPreloadWaiters() {
        let waiterIDs = Array(preloadWaiters.keys)
        waiterIDs.forEach { resumePreloadWaiter(id: $0) }
    }
}

@MainActor
final class HiddenWebViewLoader: NSObject, WKNavigationDelegate {
    static let shared = HiddenWebViewLoader()
    private static var isolatedLoaders: [UUID: HiddenWebViewLoader] = [:]

    static func loader(for channel: HiddenWebViewChannel) -> HiddenWebViewLoader {
        switch channel {
        case .shared:
            return shared
        case .isolated(let id):
            if let existing = isolatedLoaders[id] {
                return existing
            }
            let loader = HiddenWebViewLoader()
            isolatedLoaders[id] = loader
            return loader
        }
    }

    static func releaseLoader(for channel: HiddenWebViewChannel) {
        guard case .isolated(let id) = channel else { return }
        isolatedLoaders.removeValue(forKey: id)
    }

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
        AppLog.info(.webView, "开始加载页面: \(request.url?.absoluteString ?? "nil"), timeout: \(Int(self.timeoutInterval))s")
        await cookieBridge.syncWebViewCookiesToURLSession()
        await cookieBridge.syncURLSessionCookiesToWebView()
        let cookieNames = HTTPCookieStorage.shared
            .cookies(for: request.url ?? NodeSeekSite.baseURL)?
            .map(\.name)
            .sorted() ?? []
        AppLog.info(.webView, "已同步 Cookie 到 WebView，cookieCount=\(cookieNames.count)")
        AppLog.debugPanel(.account, "webview: cookies count=\(cookieNames.count) names=\(cookieNames.joined(separator: ","))")

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            scheduleTimeout()
            let navigation = webView.load(request)
            if navigation == nil {
                AppLog.error(.webView, "webView.load 返回 nil，导航未开始")
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
        AppLog.info(.webView, "WebView didFinish: \(webView.url?.absoluteString ?? "nil")")
        guard continuation != nil else { return }
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
                        AppLog.info(.webView, "结束轮询，challenge 状态: \(isChallengePage), usableContent: \(hasUsableContent), pollCount: \(self.challengePollCount)")
                        await self.cookieBridge.syncWebViewCookiesToURLSession()
                        AppLog.info(.webView, "已同步 WebView Cookie 到 URLSession")
                        self.resolve(.success(HTMLResponse(
                            statusCode: self.statusCode,
                            headers: self.headers,
                            finalURL: self.webView.url ?? self.initialURL ?? URL(string: "about:blank")!,
                            html: html
                        )))
                        return
                    }

                    self.challengePollCount += 1
                    AppLog.warning(.webView, "仍在 challenge 页面，usableContent=\(hasUsableContent)，继续轮询: \(self.challengePollCount)/\(self.maxChallengePollCount)")
                    try? await Task.sleep(nanoseconds: self.challengePollIntervalNanoseconds)
                } catch {
                    AppLog.error(.webView, "轮询 outerHTML 失败: \(error.localizedDescription)")
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
            AppLog.info(.webView, "收到响应: status=\(response.statusCode), url=\(response.url?.absoluteString ?? "nil")")
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        AppLog.error(.webView, "导航失败 didFail: \(error.localizedDescription)")
        resolve(.failure(error))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        AppLog.error(.webView, "导航失败 didFailProvisionalNavigation: \(error.localizedDescription)")
        resolve(.failure(error))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        AppLog.error(.webView, "Web 内容进程终止")
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
        AppLog.error(.webView, "隐藏 WebView 抓取超时")
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
            AppLog.info(.webView, "抓取完成: status=\(response.statusCode), htmlLength=\(response.html.count), finalURL=\(response.finalURL.absoluteString)")
            continuation.resume(returning: response)
        case .failure(let error):
            AppLog.error(.webView, "抓取失败收敛: \(error.localizedDescription)")
            continuation.resume(throwing: error)
        }
    }

    private func readOuterHTML() async throws -> String {
        let htmlAny = try await webView.evaluateJavaScript(
            """
            (() => {
              const html = document.documentElement.outerHTML;
              try {
                if (!window.__config__) {
                  return html;
                }
                const json = JSON.stringify(window.__config__).replace(/</g, '\\\\u003c');
                return html + '\\n<script id="nodeseek-captured-config" type="application/json">' + json + '</script>';
              } catch (error) {
                return html;
              }
            })()
            """
        )
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
            AppLog.error(.webView, "评论脚本执行异常: domain=\(nsError.domain), code=\(nsError.code), info=\(String(describing: nsError.userInfo))")
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
