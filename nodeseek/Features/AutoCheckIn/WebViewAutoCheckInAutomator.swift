//
//  WebViewAutoCheckInAutomator.swift
//  nodeseek
//

import Foundation
import WebKit

struct IsolatedAutoCheckInResult {
    let outcome: AutoCheckInRunOutcome
    let isLoggedOut: Bool
    let hitChallenge: Bool
    let updatedAccountCookies: [HTTPCookie]
}

@MainActor
protocol AutoCheckInWebAutomating: AnyObject {
    func fetchBoardState(runID: String) async throws -> AutoCheckInBoardState
    func submit(mode: AutoCheckInMode, runID: String) async throws -> AutoCheckInSubmitResult
    func runIsolatedCheckIn(
        accountCookies: [HTTPCookie],
        cloudflareCookies: [HTTPCookie],
        mode: AutoCheckInMode,
        runID: String
    ) async -> IsolatedAutoCheckInResult
}

extension AutoCheckInWebAutomating {
    func runIsolatedCheckIn(
        accountCookies: [HTTPCookie],
        cloudflareCookies: [HTTPCookie],
        mode: AutoCheckInMode,
        runID: String
    ) async -> IsolatedAutoCheckInResult {
        IsolatedAutoCheckInResult(
            outcome: .skipped("unsupported"),
            isLoggedOut: false,
            hitChallenge: false,
            updatedAccountCookies: []
        )
    }
}

@MainActor
final class WebViewAutoCheckInAutomator: AutoCheckInWebAutomating {
    private let timeoutInterval: TimeInterval

    init(timeoutInterval: TimeInterval = 20) {
        self.timeoutInterval = timeoutInterval
    }

    func fetchBoardState(runID: String) async throws -> AutoCheckInBoardState {
        let pageURL = NodeSeekSite.baseURL
        AppLog.notice(.autoCheckIn, "runID=\(runID) automator_board_start page=\(pageURL.absoluteString) timeout=\(Int(timeoutInterval))s")
        let object = try await withHiddenWebViewPageActionLoader(
            logMessage: "自动签到隐藏 WebView 准备获取榜单状态: runID=\(runID), url=\(pageURL.absoluteString)"
        ) { loader in
            try await loader.runPageAutomationScript(
                pageURL: pageURL,
                source: AutoCheckInAutomationScript.boardStateSource,
                arguments: [:],
                timeoutInterval: timeoutInterval,
                actionName: "自动签到榜单状态"
            )
        }
        let state = Self.parseBoardState(object)
        AppLog.notice(
            .autoCheckIn,
            "runID=\(runID) automator_board_finish ok=\(state.ok) checkedIn=\(state.isCheckedIn) reason=\(state.reason) status=\(state.statusCode.map(String.init) ?? "nil") keys=\(state.responseKeys.joined(separator: ",")) \(Self.describeDiagnostics(object))"
        )
        return state
    }

    func submit(mode: AutoCheckInMode, runID: String) async throws -> AutoCheckInSubmitResult {
        let pageURL = NodeSeekSite.baseURL
        AppLog.notice(.autoCheckIn, "runID=\(runID) automator_submit_start page=\(pageURL.absoluteString) mode=\(mode.rawValue) random=\(mode.randomQueryValue) timeout=\(Int(timeoutInterval))s")
        let object = try await withHiddenWebViewPageActionLoader(
            logMessage: "自动签到隐藏 WebView 准备提交: runID=\(runID), mode=\(mode.rawValue), random=\(mode.randomQueryValue)"
        ) { loader in
            try await loader.runPageAutomationScript(
                pageURL: pageURL,
                source: AutoCheckInAutomationScript.submitSource,
                arguments: ["randomValue": mode.randomQueryValue],
                timeoutInterval: timeoutInterval,
                actionName: "自动签到提交"
            )
        }
        let result = Self.parseSubmitResult(object)
        AppLog.notice(
            .autoCheckIn,
            "runID=\(runID) automator_submit_finish ok=\(result.ok) success=\(result.success.map(String.init) ?? "nil") current=\(result.current.map(String.init) ?? "nil") reason=\(result.reason) message=\(result.message ?? "nil") \(Self.describeDiagnostics(object))"
        )
        return result
    }

    func runIsolatedCheckIn(
        accountCookies: [HTTPCookie],
        cloudflareCookies: [HTTPCookie],
        mode: AutoCheckInMode,
        runID: String
    ) async -> IsolatedAutoCheckInResult {
        let runner = IsolatedAutoCheckInRunner(timeoutInterval: timeoutInterval)
        return await runner.run(
            accountCookies: accountCookies,
            cloudflareCookies: cloudflareCookies,
            mode: mode,
            runID: runID
        )
    }

    static func parseBoardState(_ object: [String: Any]) -> AutoCheckInBoardState {
        let reason = object["reason"] as? String ?? "unknown"
        let message = object["message"] as? String
        let statusCode = intValue(object["statusCode"])
        guard boolValue(object["ok"]) == true else {
            return AutoCheckInBoardState(
                ok: false,
                isCheckedIn: false,
                message: message,
                reason: reason,
                statusCode: statusCode,
                responseKeys: []
            )
        }

        guard let response = object["response"] as? [String: Any] else {
            return AutoCheckInBoardState(
                ok: false,
                isCheckedIn: false,
                message: message ?? "board payload is not an object",
                reason: "invalid_board_payload",
                statusCode: statusCode,
                responseKeys: []
            )
        }

        switch NodeSeekAttendanceParser.parseBoard(from: response) {
        case let .success(payload):
            return AutoCheckInBoardState(
                ok: true,
                isCheckedIn: payload.isCheckedIn,
                message: message,
                reason: reason,
                statusCode: statusCode,
                responseKeys: payload.topLevelKeys
            )
        case let .failure(error):
            return AutoCheckInBoardState(
                ok: false,
                isCheckedIn: false,
                message: message ?? String(describing: error),
                reason: boardReason(for: error),
                statusCode: statusCode,
                responseKeys: response.keys.sorted()
            )
        }
    }

    static func parseSubmitResult(_ object: [String: Any]) -> AutoCheckInSubmitResult {
        let response = object["response"] as? [String: Any] ?? [:]
        let parsed = NodeSeekAttendanceParser.parseSubmit(from: response)
        let payload = try? parsed.get()
        return AutoCheckInSubmitResult(
            ok: boolValue(object["ok"]) ?? false,
            statusCode: intValue(object["statusCode"]),
            success: payload?.success,
            message: payload?.message ?? object["message"] as? String,
            current: payload?.current,
            reason: object["reason"] as? String ?? "unknown"
        )
    }

    private static func describeDiagnostics(_ object: [String: Any]) -> String {
        guard let diagnostics = object["diagnostics"] as? [String: Any], diagnostics.isEmpty == false else {
            return "diagnostics=none"
        }
        let parts = diagnostics.keys.sorted().compactMap { key -> String? in
            guard let value = diagnostics[key] else { return nil }
            return "\(key)=\(stringifyDiagnosticValue(value))"
        }
        return "diagnostics{\(parts.joined(separator: " "))}"
    }

    private static func stringifyDiagnosticValue(_ value: Any) -> String {
        if value is NSNull { return "null" }
        if let bool = value as? Bool { return bool ? "true" : "false" }
        if let number = value as? NSNumber { return number.stringValue }
        if let string = value as? String {
            return string.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        }
        if let keys = value as? [String] { return "[\(keys.joined(separator: ","))]" }
        if let numbers = value as? [NSNumber] { return "[\(numbers.map(\.stringValue).joined(separator: ","))]" }
        return String(describing: type(of: value))
    }

    private static func boardReason(for error: NodeSeekAttendanceParser.ParseError) -> String {
        switch error {
        case .empty, .invalidJSON:
            return "invalid_json"
        case .missingRecordKey, .invalidBoardPayload:
            return "invalid_board_payload"
        case .challenge:
            return "challenge"
        case .htmlPayload:
            return "invalid_board_payload"
        }
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }
}

/// 在独立 nonPersistent() WebView 中为非当前活跃账号执行一次签到，完成后回传续期后的账号 Cookie。
@MainActor
private final class IsolatedAutoCheckInRunner: NSObject, WKNavigationDelegate {
    private let timeoutInterval: TimeInterval
    private var webView: WKWebView?
    private var navigationContinuation: CheckedContinuation<Bool, Never>?
    private var navigationTimeoutTask: Task<Void, Never>?

    init(timeoutInterval: TimeInterval) {
        self.timeoutInterval = timeoutInterval
    }

    deinit {
        navigationTimeoutTask?.cancel()
    }

    func run(
        accountCookies: [HTTPCookie],
        cloudflareCookies: [HTTPCookie],
        mode: AutoCheckInMode,
        runID: String
    ) async -> IsolatedAutoCheckInResult {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = NoBounceWebView(frame: .zero, configuration: configuration)
        // 与主请求保持一致的 User-Agent，避免注入的 cf_clearance 因 UA 不匹配触发过盾。
        webView.customUserAgent = WebRequestFingerprint.userAgent
        webView.navigationDelegate = self
        self.webView = webView

        defer {
            navigationTimeoutTask?.cancel()
            navigationTimeoutTask = nil
            webView.stopLoading()
            webView.navigationDelegate = nil
            self.webView = nil
        }

        let cookieStore = WKWebCookieStoreAdapter(store: configuration.websiteDataStore.httpCookieStore)
        for cookie in cloudflareCookies + accountCookies {
            await cookieStore.setCookie(cookie)
        }

        var request = URLRequest(url: NodeSeekSite.baseURL)
        request.timeoutInterval = timeoutInterval
        WebRequestFingerprint.applyHTMLHeaders(to: &request)

        let loaded = await loadPage(request: request, in: webView)
        guard loaded else {
            return IsolatedAutoCheckInResult(
                outcome: .failed("isolated_load_failed"),
                isLoggedOut: false,
                hitChallenge: false,
                updatedAccountCookies: []
            )
        }

        guard let boardObject = await runScript(
            AutoCheckInAutomationScript.boardStateSource,
            arguments: ["timeoutMs": Int(timeoutInterval * 1_000)],
            in: webView
        ) else {
            return IsolatedAutoCheckInResult(
                outcome: .failed("isolated_board_script_failed"),
                isLoggedOut: false,
                hitChallenge: false,
                updatedAccountCookies: []
            )
        }

        let boardState = WebViewAutoCheckInAutomator.parseBoardState(boardObject)
        let hasConfigUser = (boardObject["diagnostics"] as? [String: Any])?["hasConfigUser"] as? Bool
        let updatedCookies = NodeSeekCookieClassifier.accountSessionCookies(from: await cookieStore.allCookies())

        if boardState.ok == false {
            let isChallenge = boardState.reason == "challenge" || boardState.statusCode == 403 || boardState.statusCode == 503
            let isLoggedOut = !isChallenge && (boardState.statusCode == 401 || hasConfigUser == false)
            return IsolatedAutoCheckInResult(
                outcome: .failed(boardState.reason),
                isLoggedOut: isLoggedOut,
                hitChallenge: isChallenge,
                updatedAccountCookies: isLoggedOut ? [] : updatedCookies
            )
        }

        if boardState.isCheckedIn {
            return IsolatedAutoCheckInResult(
                outcome: .alreadyCheckedIn,
                isLoggedOut: false,
                hitChallenge: false,
                updatedAccountCookies: updatedCookies
            )
        }

        guard let submitObject = await runScript(
            AutoCheckInAutomationScript.submitSource,
            arguments: [
                "randomValue": mode.randomQueryValue,
                "timeoutMs": Int(timeoutInterval * 1_000)
            ],
            in: webView
        ) else {
            return IsolatedAutoCheckInResult(
                outcome: .failed("isolated_submit_script_failed"),
                isLoggedOut: false,
                hitChallenge: false,
                updatedAccountCookies: updatedCookies
            )
        }

        let submit = WebViewAutoCheckInAutomator.parseSubmitResult(submitObject)
        let refreshedCookies = NodeSeekCookieClassifier.accountSessionCookies(from: await cookieStore.allCookies())
        let message = submit.message?.trimmingCharacters(in: .whitespacesAndNewlines)

        if submit.ok == false, let message,
           message.contains("已完成签到") || message.contains("请勿重复") || message.contains("已签到") || message.contains("已经签到") {
            return IsolatedAutoCheckInResult(
                outcome: .alreadyCheckedIn,
                isLoggedOut: false,
                hitChallenge: false,
                updatedAccountCookies: refreshedCookies
            )
        }

        guard submit.ok else {
            let isChallenge = submit.reason == "challenge" || submit.statusCode == 403 || submit.statusCode == 503
            let isLoggedOut = !isChallenge && (submit.statusCode == 401 || hasConfigUser == false)
            return IsolatedAutoCheckInResult(
                outcome: .failed(submit.reason),
                isLoggedOut: isLoggedOut,
                hitChallenge: isChallenge,
                updatedAccountCookies: isLoggedOut ? [] : refreshedCookies
            )
        }

        AppLog.notice(.autoCheckIn, "runID=\(runID) isolated_submit_success message=\(message ?? "nil")")
        return IsolatedAutoCheckInResult(
            outcome: .submitted(message: message),
            isLoggedOut: false,
            hitChallenge: false,
            updatedAccountCookies: refreshedCookies
        )
    }

    private func loadPage(request: URLRequest, in webView: WKWebView) async -> Bool {
        await withCheckedContinuation { continuation in
            navigationContinuation = continuation
            navigationTimeoutTask?.cancel()
            navigationTimeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(self?.timeoutInterval ?? 20) * 1_000_000_000)
                guard !Task.isCancelled else { return }
                self?.finishNavigation(false)
            }
            if webView.load(request) == nil {
                finishNavigation(false)
            }
        }
    }

    private func finishNavigation(_ success: Bool) {
        navigationTimeoutTask?.cancel()
        navigationTimeoutTask = nil
        guard let continuation = navigationContinuation else { return }
        navigationContinuation = nil
        continuation.resume(returning: success)
    }

    private func runScript(
        _ source: String,
        arguments: [String: Any],
        in webView: WKWebView
    ) async -> [String: Any]? {
        await withCheckedContinuation { continuation in
            webView.callAsyncJavaScript(
                source,
                arguments: arguments,
                in: nil,
                in: .page
            ) { result in
                MainActor.assumeIsolated {
                    switch result {
                    case .success(let value):
                        continuation.resume(returning: value as? [String: Any])
                    case .failure:
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishNavigation(true)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishNavigation(false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finishNavigation(false)
    }
}
