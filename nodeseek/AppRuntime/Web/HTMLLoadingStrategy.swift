//
//  HTMLLoadingStrategy.swift
//  nodeseek
//

import Foundation

enum HTMLLoadingStrategy: Sendable {
    case legacyWebView
    case httpWithWebViewFallback
}

@MainActor
enum HTMLLoadingStrategyConfig {
    static var listAndDetailStrategy: HTMLLoadingStrategy = .httpWithWebViewFallback
}

@MainActor
enum HTMLLoadingStrategyFactory {
    static func makeDefaultClient() -> any HTMLClient {
        makeClient(strategy: HTMLLoadingStrategyConfig.listAndDetailStrategy)
    }

    static func makeClient(strategy: HTMLLoadingStrategy) -> any HTMLClient {
        switch strategy {
        case .legacyWebView:
            AppLog.info(.service, "HTML加载策略=legacyWebView")
            return HiddenWebViewHTMLClient()
        case .httpWithWebViewFallback:
            AppLog.info(.service, "HTML加载策略=httpWithWebViewFallback")
            return WebViewFallbackHTMLClient(
                primaryClient: HTTPHTMLClient(),
                fallbackClient: HiddenWebViewHTMLClient(),
                cookieSynchronizer: CookieBridge()
            )
        }
    }
}

struct WebViewFallbackHTMLClient: HTMLClient {
    private let primaryClient: any HTMLClient
    private let fallbackClient: any HTMLClient
    private let cookieSynchronizer: CookieSynchronizing?
    private let challengeDetector: ChallengeDetector

    init(
        primaryClient: any HTMLClient,
        fallbackClient: any HTMLClient,
        cookieSynchronizer: CookieSynchronizing?,
        challengeDetector: ChallengeDetector = ChallengeDetector()
    ) {
        self.primaryClient = primaryClient
        self.fallbackClient = fallbackClient
        self.cookieSynchronizer = cookieSynchronizer
        self.challengeDetector = challengeDetector
    }

    func get(_ url: URL) async throws -> HTMLResponse {
        await syncCookies(reason: "primary-before-get", url: url)
        AppLog.info(.service, "HTTP优先加载开始 method=GET url=\(url.absoluteString)")
        let primaryResponse = try await primaryClient.get(url)
        log(response: primaryResponse, phase: "primary")

        guard shouldFallback(response: primaryResponse) else {
            return primaryResponse
        }

        return try await fallbackAndRetryGet(url: url, primaryResponse: primaryResponse)
    }

    func post(_ url: URL, formFields: [String: String]) async throws -> HTMLResponse {
        await syncCookies(reason: "primary-before-post", url: url)
        AppLog.info(.service, "HTTP优先加载开始 method=POST url=\(url.absoluteString)")
        let response = try await primaryClient.post(url, formFields: formFields)
        log(response: response, phase: "primary-post")
        return response
    }

    private func fallbackAndRetryGet(url: URL, primaryResponse: HTMLResponse) async throws -> HTMLResponse {
        if let challenge = challengeDetector.detect(response: primaryResponse) {
            AppLog.warning(.service, "HTTP命中验证，准备 WebView fallback: \(challenge.logDescription)")
        }

        let fallbackResponse: HTMLResponse
        do {
            fallbackResponse = try await fallbackClient.get(url)
        } catch {
            AppLog.error(.service, "WebView fallback 失败，返回 HTTP 原始结果: \(error.localizedDescription)")
            return primaryResponse
        }
        log(response: fallbackResponse, phase: "webview-fallback")
        await syncCookies(reason: "after-webview-fallback", url: url)

        AppLog.info(.service, "WebView fallback 后重试 HTTP GET: \(url.absoluteString)")
        let retryResponse: HTMLResponse
        do {
            retryResponse = try await primaryClient.get(url)
        } catch {
            if challengeDetector.detect(response: fallbackResponse) == nil {
                AppLog.error(.service, "WebView fallback 后 HTTP 重试失败，返回 WebView 结果: \(error.localizedDescription)")
                return fallbackResponse
            }
            AppLog.error(.service, "WebView fallback 后 HTTP 重试失败，返回 HTTP 原始结果: \(error.localizedDescription)")
            return primaryResponse
        }
        log(response: retryResponse, phase: "retry")
        return retryResponse
    }

    private func shouldFallback(response: HTMLResponse) -> Bool {
        guard let challenge = challengeDetector.detect(response: response) else {
            return false
        }

        switch challenge {
        case .cloudflare, .blocked:
            return true
        case .loginRequired, .unsupported:
            AppLog.info(.service, "HTTP命中非 fallback 验证，保持原结果: \(challenge.logDescription)")
            return false
        }
    }

    private func syncCookies(reason: String, url: URL) async {
        guard let cookieSynchronizer else { return }
        AppLog.info(.service, "同步 WebView Cookie 到 URLSession reason=\(reason) url=\(url.absoluteString)")
        await cookieSynchronizer.syncWebViewCookiesToURLSession()
    }

    private func log(response: HTMLResponse, phase: String) {
        let challengeDescription = challengeDetector.detect(response: response)?.logDescription ?? "none"
        AppLog.info(
            .service,
            "HTML加载结果 phase=\(phase) status=\(response.statusCode) htmlLength=\(response.html.count) finalURL=\(response.finalURL.absoluteString) challenge=\(challengeDescription)"
        )
    }
}
