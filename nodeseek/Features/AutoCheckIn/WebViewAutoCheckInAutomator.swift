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
        let object = try await withHiddenWebViewPageActionLoader(
            logMessage: "自动签到隐藏 WebView 准备获取榜单状态: runID=\(runID), url=\(NodeSeekSite.boardURL.absoluteString)"
        ) { loader in
            try await loader.runPageAutomationScript(
                pageURL: NodeSeekSite.boardURL,
                source: AutoCheckInAutomationScript.boardStateSource,
                arguments: [:],
                timeoutInterval: timeoutInterval,
                actionName: "自动签到榜单状态"
            )
        }
        return Self.parseBoardState(object)
    }

    func submit(mode: AutoCheckInMode, runID: String) async throws -> AutoCheckInSubmitResult {
        let object = try await withHiddenWebViewPageActionLoader(
            logMessage: "自动签到隐藏 WebView 准备提交: runID=\(runID), mode=\(mode.rawValue), random=\(mode.randomQueryValue)"
        ) { loader in
            try await loader.runPageAutomationScript(
                pageURL: NodeSeekSite.boardURL,
                source: AutoCheckInAutomationScript.submitSource,
                arguments: ["randomValue": mode.randomQueryValue],
                timeoutInterval: timeoutInterval,
                actionName: "自动签到提交"
            )
        }
        return Self.parseSubmitResult(object)
    }

    static func parseBoardState(_ object: [String: Any]) -> AutoCheckInBoardState {
        let response = object["response"] as? [String: Any] ?? [:]
        return AutoCheckInBoardState(
            ok: boolValue(object["ok"]) ?? false,
            isLoggedIn: boolValue(response["isLoggedIn"]) ?? false,
            isCheckedIn: boolValue(response["isCheckedIn"]) ?? false,
            message: response["message"] as? String ?? object["message"] as? String,
            detectionSource: response["detectionSource"] as? String ?? object["reason"] as? String ?? "unknown",
            reason: object["reason"] as? String ?? "unknown",
            statusCode: intValue(object["statusCode"]),
            responseKeys: response["responseKeys"] as? [String] ?? []
        )
    }

    static func parseSubmitResult(_ object: [String: Any]) -> AutoCheckInSubmitResult {
        let response = object["response"] as? [String: Any] ?? [:]
        return AutoCheckInSubmitResult(
            ok: boolValue(object["ok"]) ?? false,
            statusCode: intValue(object["statusCode"]),
            success: boolValue(response["success"]),
            message: response["message"] as? String ?? object["message"] as? String,
            current: intValue(response["current"]),
            reason: object["reason"] as? String ?? "unknown"
        )
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
