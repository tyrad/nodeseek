//
//  AutoCheckInAutomationScriptTests.swift
//  nodeseekTests
//

import Foundation
import Testing
@testable import nodeseek

struct AutoCheckInAutomationScriptTests {
    @Test func submitScriptUsesAttendanceEndpointPostAndIncludedCredentials() {
        let source = AutoCheckInAutomationScript.submitSource

        #expect(source.contains("/api/attendance?random="))
        #expect(source.contains("method: \"POST\""))
        #expect(source.contains("credentials: \"include\""))
        #expect(source.contains("success"))
        #expect(source.contains("current"))
    }

    @Test func boardStateScriptUsesAttendanceBoardEndpointAndStableLoginSignals() {
        let source = AutoCheckInAutomationScript.boardStateSource

        #expect(source.contains("/api/attendance/board?page=1"))
        #expect(source.contains("window.__config__"))
        #expect(source.contains("登录后签到"))
        #expect(source.contains("memberList"))
        #expect(source.contains("record"))
    }

    @Test func boardStateTimeoutUsesBoardStateReason() {
        let source = AutoCheckInAutomationScript.boardStateSource

        #expect(source.contains("board_state_timeout"))
        #expect(!source.contains("reason: \"submit_timeout\""))
    }

    @Test func boardStateNetworkErrorUsesNormalizedPayload() {
        let source = AutoCheckInAutomationScript.boardStateSource

        #expect(source.contains("statusCode: null,\n      reason: \"network_error\""))
    }

    @Test func boardStateInvalidJSONDoesNotReportSuccessfulLoad() {
        let source = AutoCheckInAutomationScript.boardStateSource

        #expect(source.contains("reason: \"invalid_json\""))
        #expect(source.contains("ok: false"))
        #expect(source.contains("body.trim().length === 0"))
        #expect(!source.contains("body || \"{}\""))
        #expect(!source.contains("return {};"))
    }

    @Test func submitFailureBranchesUseNormalizedPayload() {
        let source = AutoCheckInAutomationScript.submitSource

        #expect(source.contains("reason: \"submit_timeout\""))
        #expect(source.contains("reason: \"network_error\""))
        #expect(source.contains("statusCode: null"))
        #expect(source.contains("response: {"))
        #expect(source.contains("success: false"))
        #expect(source.contains("success: null"))
        #expect(source.contains("current: null"))
    }

    @Test func submitScriptRequiresExplicitSuccessTrue() {
        let source = AutoCheckInAutomationScript.submitSource

        #expect(source.contains("json.success === true"))
        #expect(source.contains("const isSuccessfulStatus = response.status >= 200 && response.status < 300"))
        #expect(source.contains("isSuccessfulStatus && isSuccess"))
        #expect(!source.contains("success !== false ? \"submitted\""))
    }

    @Test func boardStateScriptAvoidsAmbiguousListSignals() {
        let source = AutoCheckInAutomationScript.boardStateSource

        #expect(!source.contains("record.length > 0"))
        #expect(!source.contains("Boolean(json.record)"))
        #expect(!source.contains("Boolean(json.memberList)"))
        #expect(source.contains("hasCurrentMarker"))
        #expect(source.contains("isSelf"))
        #expect(source.contains("mine"))
    }

    @Test func boardStateCheckedInRequiresSuccessfulStatus() {
        let source = AutoCheckInAutomationScript.boardStateSource

        #expect(source.contains("const isSuccessfulStatus = response.status >= 200 && response.status < 300"))
        #expect(source.contains("isSuccessfulStatus && hasCurrentRecord"))
        #expect(!source.contains("const isCheckedIn = hasCurrentRecord;"))
    }

    @Test func boardStateScriptRejectsMalformedSuccessfulPayload() {
        let source = AutoCheckInAutomationScript.boardStateSource

        #expect(source.contains("hasBoardPayload"))
        #expect(source.contains("invalid_board_payload"))
        #expect(source.contains("!hasGuestSignInHint && !hasBoardPayload"))
    }

    @Test func hiddenWebViewScriptExceptionLogsDoNotIncludeUserInfo() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = projectRoot.appendingPathComponent("nodeseek/AppRuntime/Web/HTMLClient/HiddenWebViewHTMLClient.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(!source.contains("nsError.userInfo"))
        #expect(source.contains("domain=\\(nsError.domain), code=\\(nsError.code), message=\\(nsError.localizedDescription)"))
    }

    @MainActor
    @Test func automatorParsesNSNumberBooleans() {
        let boardState = WebViewAutoCheckInAutomator.parseBoardState([
            "statusCode": NSNumber(value: 200),
            "response": [
                "isLoggedIn": NSNumber(value: true),
                "isCheckedIn": NSNumber(value: true),
                "detectionSource": "test",
                "responseKeys": ["record"]
            ]
        ])
        let submitResult = WebViewAutoCheckInAutomator.parseSubmitResult([
            "ok": NSNumber(value: true),
            "response": [
                "success": NSNumber(value: true)
            ],
            "reason": "submitted"
        ])

        #expect(boardState.isLoggedIn)
        #expect(boardState.isCheckedIn)
        #expect(submitResult.ok)
        #expect(submitResult.success == true)
    }

    @MainActor
    @Test func automatorKeepsJavascriptExceptionSubmitResultFailed() {
        let submitResult = WebViewAutoCheckInAutomator.parseSubmitResult([
            "ok": NSNumber(value: false),
            "statusCode": NSNull(),
            "response": [:],
            "reason": "javascript_exception"
        ])

        #expect(submitResult.ok == false)
        #expect(submitResult.statusCode == nil)
        #expect(submitResult.success == nil)
        #expect(submitResult.reason == "javascript_exception")
    }

    @MainActor
    @Test func automatorKeepsFailedBoardStateReason() {
        let boardState = WebViewAutoCheckInAutomator.parseBoardState([
            "ok": NSNumber(value: false),
            "statusCode": NSNull(),
            "reason": "javascript_exception",
            "message": "script\nfailed",
            "response": [
                "isLoggedIn": NSNumber(value: true),
                "isCheckedIn": NSNumber(value: false),
                "detectionSource": "javascript_exception",
                "responseKeys": []
            ]
        ])

        #expect(boardState.ok == false)
        #expect(boardState.statusCode == nil)
        #expect(boardState.reason == "javascript_exception")
        #expect(boardState.message == "script\nfailed")
        #expect(boardState.isLoggedIn)
        #expect(boardState.isCheckedIn == false)
    }
}
