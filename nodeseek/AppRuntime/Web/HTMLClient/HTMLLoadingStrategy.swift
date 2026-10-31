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
                cookieSession: NodeSeekCookieSession()
            )
        }
    }
}

@MainActor
struct WebViewFallbackHTMLClient: HTMLClient {
    private let primaryClient: any HTMLClient
    private let fallbackClient: any HTMLClient
    private let cookieSession: NodeSeekCookieSessionManaging?
    private let challengeDetector: ChallengeDetector

    init(
        primaryClient: any HTMLClient,
        fallbackClient: any HTMLClient,
        cookieSession: NodeSeekCookieSessionManaging?,
        challengeDetector: ChallengeDetector? = nil
    ) {
        self.primaryClient = primaryClient
        self.fallbackClient = fallbackClient
        self.cookieSession = cookieSession
        self.challengeDetector = challengeDetector ?? ChallengeDetector()
    }

    @MainActor
    func get(_ url: URL) async throws -> HTMLResponse {
        await prepareCookiesForHTTPLoad(reason: "primary-before-get", url: url)
        AppLog.info(.service, "HTTP优先加载开始 method=GET url=\(url.absoluteString)")
        let primaryResponse = try await primaryClient.get(url)
        let primaryChallenge = await detectChallenge(in: primaryResponse)
        log(response: primaryResponse, phase: "primary", challenge: primaryChallenge)

        guard shouldFallback(challenge: primaryChallenge) else {
            return primaryResponse
        }

        return try await fallbackAndRetryGet(url: url, primaryResponse: primaryResponse, primaryChallenge: primaryChallenge)
    }

    @MainActor
    func post(_ url: URL, formFields: [String: String]) async throws -> HTMLResponse {
        await prepareCookiesForHTTPLoad(reason: "primary-before-post", url: url)
        AppLog.info(.service, "HTTP优先加载开始 method=POST url=\(url.absoluteString)")
        let response = try await primaryClient.post(url, formFields: formFields)
        log(response: response, phase: "primary-post", challenge: await detectChallenge(in: response))
        return response
    }

    private func fallbackAndRetryGet(
        url: URL,
        primaryResponse: HTMLResponse,
        primaryChallenge: ChallengeKind?
    ) async throws -> HTMLResponse {
        if let challenge = primaryChallenge {
            AppLog.warning(.service, "HTTP命中验证，准备 WebView fallback: \(challenge.logDescription)")
        }

        let fallbackResponse: HTMLResponse
        do {
            fallbackResponse = try await fallbackClient.get(url)
        } catch {
            AppLog.error(.service, "WebView fallback 失败，返回 HTTP 原始结果: \(error.localizedDescription)")
            return primaryResponse
        }
        let fallbackChallenge = await detectChallenge(in: fallbackResponse)
        log(response: fallbackResponse, phase: "webview-fallback", challenge: fallbackChallenge)
        await prepareCookiesForHTTPLoad(reason: "after-webview-fallback", url: url)

        AppLog.info(.service, "WebView fallback 后重试 HTTP GET: \(url.absoluteString)")
        let retryResponse: HTMLResponse
        do {
            retryResponse = try await primaryClient.get(url)
        } catch {
            if fallbackChallenge == nil {
                AppLog.error(.service, "WebView fallback 后 HTTP 重试失败，返回 WebView 结果: \(error.localizedDescription)")
                return fallbackResponse
            }
            AppLog.error(.service, "WebView fallback 后 HTTP 重试失败，返回 HTTP 原始结果: \(error.localizedDescription)")
            return primaryResponse
        }
        log(response: retryResponse, phase: "retry", challenge: await detectChallenge(in: retryResponse))
        return retryResponse
    }

    private func shouldFallback(challenge: ChallengeKind?) -> Bool {
        guard let challenge else {
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

    private func prepareCookiesForHTTPLoad(reason: String, url: URL) async {
        guard let cookieSession else { return }
        AppLog.info(.service, "准备 HTTP Cookie reason=\(reason) url=\(url.absoluteString)")
        await cookieSession.prepareHTTPLoad()
    }

    /// 检测要在整页 HTML 上做字符串查找，耗时几十毫秒；放在主线程会让滑动中的分页掉帧。
    private func detectChallenge(in response: HTMLResponse) async -> ChallengeKind? {
        let challengeDetector = challengeDetector
        return await Task.detached(priority: .userInitiated) {
            challengeDetector.detect(response: response)
        }.value
    }

    private func log(response: HTMLResponse, phase: String, challenge: ChallengeKind?) {
        let challengeDescription = challenge?.logDescription ?? "none"
        AppLog.info(
            .service,
            "HTML加载结果 phase=\(phase) status=\(response.statusCode) htmlLength=\(response.html.utf8.count) finalURL=\(response.finalURL.absoluteString) challenge=\(challengeDescription)"
        )
    }
}
