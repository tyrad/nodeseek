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
        #expect(source.contains("json.success === true"))
        #expect(source.contains("current"))
        #expect(source.contains("diagnostics"))
        #expect(!source.contains("x-dynamic-sign"))
    }

    @Test func boardStateScriptFetchesOfficialBoardEndpointWithoutDOMHeuristics() {
        let source = AutoCheckInAutomationScript.boardStateSource

        #expect(source.contains("/api/attendance/board?page=1"))
        #expect(source.contains("credentials: \"include\""))
        #expect(source.contains("response: json"))
        #expect(source.contains("diagnostics"))
        #expect(source.contains("recordType"))
        #expect(source.contains("bodyLength"))
        #expect(source.contains("hasConfigUser"))
        #expect(!source.contains("登录后签到"))
        #expect(!source.contains("memberList"))
        #expect(!source.contains("hasCurrentMarker"))
        #expect(!source.contains("isSelf"))
        #expect(!source.contains("mine"))
    }

    @Test func boardStateTimeoutUsesBoardStateReason() {
        let source = AutoCheckInAutomationScript.boardStateSource

        #expect(source.contains("board_state_timeout"))
        #expect(!source.contains("reason: \"submit_timeout\""))
    }

    @Test func boardStateNetworkErrorUsesNormalizedPayload() {
        let source = AutoCheckInAutomationScript.boardStateSource

        #expect(source.contains("statusCode: null,\n          reason: \"network_error\""))
    }

    @Test func boardStateInvalidJSONDoesNotReportSuccessfulLoad() {
        let source = AutoCheckInAutomationScript.boardStateSource

        #expect(source.contains("reason: \"invalid_json\""))
        #expect(source.contains("ok: false"))
        #expect(source.contains("body.trim().length === 0"))
        #expect(!source.contains("body || \"{}\""))
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
    @Test func automatorParsesOfficialRecordObjectAsCheckedIn() {
        let boardState = WebViewAutoCheckInAutomator.parseBoardState([
            "ok": NSNumber(value: true),
            "statusCode": NSNumber(value: 200),
            "reason": "loaded",
            "response": [
                "list": [],
                "record": ["gain": NSNumber(value: 5)],
                "order": NSNumber(value: 3),
                "total": NSNumber(value: 10)
            ]
        ])
        let submitResult = WebViewAutoCheckInAutomator.parseSubmitResult([
            "ok": NSNumber(value: true),
            "response": [
                "success": NSNumber(value: true)
            ],
            "reason": "submitted"
        ])

        #expect(boardState.ok)
        #expect(boardState.isCheckedIn)
        #expect(submitResult.ok)
        #expect(submitResult.success == true)
    }

    @MainActor
    @Test func automatorParsesNullRecordAsNotCheckedIn() {
        let boardState = WebViewAutoCheckInAutomator.parseBoardState([
            "ok": NSNumber(value: true),
            "statusCode": NSNumber(value: 200),
            "reason": "loaded",
            "response": [
                "list": [],
                "record": NSNull(),
                "order": NSNull(),
                "total": NSNumber(value: 10)
            ]
        ])

        #expect(boardState.ok)
        #expect(boardState.isCheckedIn == false)
        #expect(boardState.responseKeys.contains("record"))
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
        #expect(submitResult.success == false)
        #expect(submitResult.reason == "javascript_exception")
    }

    @MainActor
    @Test func automatorKeepsFailedBoardStateReason() {
        let boardState = WebViewAutoCheckInAutomator.parseBoardState([
            "ok": NSNumber(value: false),
            "statusCode": NSNull(),
            "reason": "javascript_exception",
            "message": "script\nfailed",
            "response": [:]
        ])

        #expect(boardState.ok == false)
        #expect(boardState.statusCode == nil)
        #expect(boardState.reason == "javascript_exception")
        #expect(boardState.message == "script\nfailed")
        #expect(boardState.isCheckedIn == false)
    }

    @MainActor
    @Test func automatorLogsBoardDiagnosticsWithoutMemberNames() {
        let boardState = WebViewAutoCheckInAutomator.parseBoardState([
            "ok": NSNumber(value: true),
            "statusCode": NSNumber(value: 200),
            "reason": "loaded",
            "response": [
                "list": [],
                "record": NSNull(),
                "order": NSNull(),
                "total": NSNumber(value: 10)
            ],
            "diagnostics": [
                "pageHref": "https://www.nodeseek.com/",
                "hasConfigUser": NSNumber(value: true),
                "recordType": "null",
                "keys": ["list", "order", "record", "total"],
                "listLength": NSNumber(value: 50),
                "bodyLength": NSNumber(value: 1234)
            ]
        ])

        #expect(boardState.ok)
        #expect(boardState.isCheckedIn == false)
    }

    @MainActor
    @Test func automatorUsesHomepageForAutomationContext() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("nodeseek/Features/AutoCheckIn/WebViewAutoCheckInAutomator.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("NodeSeekSite.baseURL"))
        #expect(!source.contains("NodeSeekSite.boardURL"))
    }
}
