//
//  WebViewAutoCheckInAutomator.swift
//  nodeseek
//

import Foundation

@MainActor
protocol AutoCheckInWebAutomating: AnyObject {
    func fetchBoardState(runID: String) async throws -> AutoCheckInBoardState
    func submit(mode: AutoCheckInMode, runID: String) async throws -> AutoCheckInSubmitResult
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
