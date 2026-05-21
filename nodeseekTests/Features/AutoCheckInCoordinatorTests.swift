//
//  AutoCheckInCoordinatorTests.swift
//  nodeseekTests
//

import Foundation
import Testing
import UIKit
@testable import nodeseek

@MainActor
@Suite(.serialized)
struct AutoCheckInCoordinatorTests {
    @Test func skipsWhenDisabledWithoutCallingWeb() async throws {
        let harness = try Harness(settings: AutoCheckInSettings(isEnabled: false, mode: .fixedChickenLeg))

        let outcome = await harness.coordinator.runIfNeeded(presentationContext: nil)

        #expect(outcome == .skipped("disabled"))
        #expect(harness.web.boardCalls == 0)
        #expect(harness.web.submitModes.isEmpty)
    }

    @Test func skipsWhenLocalDayAlreadyCompleted() async throws {
        let harness = try Harness(settings: AutoCheckInSettings(isEnabled: true, mode: .fixedChickenLeg))
        harness.stateStore.markCompleted(dayIdentifier: harness.dayIdentifier, at: harness.now)

        let outcome = await harness.coordinator.runIfNeeded(presentationContext: nil)

        #expect(outcome == .skipped("completed_today"))
        #expect(harness.web.boardCalls == 0)
    }

    @Test func marksCompletedWithoutAlertWhenBoardSaysAlreadyCheckedIn() async throws {
        let harness = try Harness(settings: AutoCheckInSettings(isEnabled: true, mode: .fixedChickenLeg))
        harness.web.boardState = AutoCheckInBoardState(
            ok: true,
            isLoggedIn: true,
            isCheckedIn: true,
            message: "今日已签到",
            detectionSource: "board_api",
            reason: "loaded",
            statusCode: 200,
            responseKeys: ["record"]
        )

        let outcome = await harness.coordinator.runIfNeeded(presentationContext: UIViewController())

        #expect(outcome == .alreadyCheckedIn)
        #expect(harness.stateStore.isCompleted(on: harness.dayIdentifier) == true)
        #expect(harness.alerter.alerts.isEmpty)
        #expect(harness.web.submitModes.isEmpty)
    }

    @Test func submitsChickenLegModeAndShowsSuccessAlert() async throws {
        let harness = try Harness(settings: AutoCheckInSettings(isEnabled: true, mode: .fixedChickenLeg))
        harness.web.submitResult = AutoCheckInSubmitResult(
            ok: true,
            statusCode: 200,
            success: true,
            message: "签到成功",
            current: 5,
            reason: "submitted"
        )

        let outcome = await harness.coordinator.runIfNeeded(presentationContext: UIViewController())

        #expect(outcome == .submitted(message: "签到成功"))
        #expect(harness.web.submitModes == [.fixedChickenLeg])
        #expect(harness.stateStore.isCompleted(on: harness.dayIdentifier) == true)
        #expect(harness.alerter.alerts == [AutoCheckInAlert(title: "自动签到成功", message: "签到成功")])
    }

    @Test func submitsRandomModeWithNoAlertWhenPresentationContextIsMissing() async throws {
        let harness = try Harness(settings: AutoCheckInSettings(isEnabled: true, mode: .random))
        harness.web.submitResult = AutoCheckInSubmitResult(
            ok: true,
            statusCode: 200,
            success: true,
            message: nil,
            current: 8,
            reason: "submitted"
        )

        let outcome = await harness.coordinator.runIfNeeded(presentationContext: nil)

        #expect(outcome == .submitted(message: nil))
        #expect(harness.web.submitModes == [.random])
        #expect(harness.alerter.alerts.isEmpty)
    }

    @Test func returnsSilentlyWhenGuest() async throws {
        let harness = try Harness(settings: AutoCheckInSettings(isEnabled: true, mode: .fixedChickenLeg))
        harness.web.boardState = AutoCheckInBoardState(
            ok: true,
            isLoggedIn: false,
            isCheckedIn: false,
            message: "登录后签到",
            detectionSource: "guest_hint",
            reason: "loaded",
            statusCode: 200,
            responseKeys: []
        )

        let outcome = await harness.coordinator.runIfNeeded(presentationContext: UIViewController())

        #expect(outcome == .skipped("not_logged_in"))
        #expect(harness.web.submitModes.isEmpty)
        #expect(harness.alerter.alerts.isEmpty)
    }

    @Test func failedBoardStateDoesNotSubmitAndStartsCooldown() async throws {
        let harness = try Harness(settings: AutoCheckInSettings(isEnabled: true, mode: .fixedChickenLeg))
        harness.web.boardState = AutoCheckInBoardState(
            ok: false,
            isLoggedIn: true,
            isCheckedIn: false,
            message: "board\nstate failed",
            detectionSource: "javascript_exception",
            reason: "javascript_exception",
            statusCode: nil,
            responseKeys: []
        )

        let first = await harness.coordinator.runIfNeeded(presentationContext: UIViewController())
        let second = await harness.coordinator.runIfNeeded(presentationContext: UIViewController())

        #expect(first == .failed("javascript_exception"))
        #expect(second == .skipped("cooldown"))
        #expect(harness.stateStore.isCompleted(on: harness.dayIdentifier) == false)
        #expect(harness.web.boardCalls == 1)
        #expect(harness.web.submitModes.isEmpty)
        #expect(harness.alerter.alerts.isEmpty)
    }

    @Test func failedSubmitDoesNotMarkCompletedAndStartsCooldown() async throws {
        let harness = try Harness(settings: AutoCheckInSettings(isEnabled: true, mode: .fixedChickenLeg))
        harness.web.submitResult = AutoCheckInSubmitResult(
            ok: false,
            statusCode: 500,
            success: false,
            message: "server down",
            current: nil,
            reason: "server_error"
        )

        let first = await harness.coordinator.runIfNeeded(presentationContext: UIViewController())
        let second = await harness.coordinator.runIfNeeded(presentationContext: UIViewController())

        #expect(first == .failed("server_error"))
        #expect(second == .skipped("cooldown"))
        #expect(harness.stateStore.isCompleted(on: harness.dayIdentifier) == false)
        #expect(harness.web.submitModes.count == 1)
    }

    @Test func alreadyCheckedInSubmitMarksCompletedWithoutAlertOrCooldown() async throws {
        let harness = try Harness(settings: AutoCheckInSettings(isEnabled: true, mode: .fixedChickenLeg))
        harness.web.submitResult = AutoCheckInSubmitResult(
            ok: false,
            statusCode: 200,
            success: false,
            message: "今天已完成签到，请勿重复操作",
            current: nil,
            reason: "server_error"
        )

        let first = await harness.coordinator.runIfNeeded(presentationContext: UIViewController())
        let second = await harness.coordinator.runIfNeeded(presentationContext: UIViewController())

        #expect(first == .alreadyCheckedIn)
        #expect(second == .skipped("completed_today"))
        #expect(harness.stateStore.isCompleted(on: harness.dayIdentifier) == true)
        #expect(harness.web.submitModes.count == 1)
        #expect(harness.alerter.alerts.isEmpty)
    }

    @Test func unavailablePresentationStillCompletesSubmittedRun() async throws {
        let harness = try Harness(settings: AutoCheckInSettings(isEnabled: true, mode: .fixedChickenLeg))
        harness.alerter.shouldShow = false
        harness.web.submitResult = AutoCheckInSubmitResult(
            ok: true,
            statusCode: 200,
            success: true,
            message: "签到成功",
            current: 5,
            reason: "submitted"
        )

        let outcome = await harness.coordinator.runIfNeeded(presentationContext: UIViewController())

        #expect(outcome == .submitted(message: "签到成功"))
        #expect(harness.stateStore.isCompleted(on: harness.dayIdentifier) == true)
        #expect(harness.alerter.alerts.isEmpty)
        #expect(harness.alerter.showCalls == 1)
    }

    @Test func concurrentRunsJoinInFlightWork() async throws {
        let harness = try Harness(settings: AutoCheckInSettings(isEnabled: true, mode: .fixedChickenLeg))
        harness.web.suspendBoardState = true

        let firstTask = Task { @MainActor in
            await harness.coordinator.runIfNeeded(presentationContext: nil)
        }
        while harness.web.boardContinuation == nil {
            await Task.yield()
        }
        let secondTask = Task { @MainActor in
            await harness.coordinator.runIfNeeded(presentationContext: nil)
        }
        harness.web.resumeBoardState()

        let first = await firstTask.value
        let second = await secondTask.value

        #expect(first == .submitted(message: "ok"))
        #expect(second == first)
        #expect(harness.web.boardCalls == 1)
        #expect(harness.web.submitModes == [.fixedChickenLeg])
    }

    @Test func thrownWebErrorDoesNotMarkCompletedAndStartsCooldown() async throws {
        let harness = try Harness(settings: AutoCheckInSettings(isEnabled: true, mode: .fixedChickenLeg))
        harness.web.submitError = TestError.webFailed

        let first = await harness.coordinator.runIfNeeded(presentationContext: UIViewController())
        let second = await harness.coordinator.runIfNeeded(presentationContext: UIViewController())

        #expect(first == .failed("exception"))
        #expect(second == .skipped("cooldown"))
        #expect(harness.stateStore.isCompleted(on: harness.dayIdentifier) == false)
        #expect(harness.web.submitModes.count == 1)
    }

    @Test func allowsRetryAfterCooldownExpires() async throws {
        let harness = try Harness(settings: AutoCheckInSettings(isEnabled: true, mode: .fixedChickenLeg))
        harness.web.submitResult = AutoCheckInSubmitResult(
            ok: false,
            statusCode: 500,
            success: false,
            message: "server down",
            current: nil,
            reason: "server_error"
        )

        let first = await harness.coordinator.runIfNeeded(presentationContext: nil)
        harness.currentNow = harness.now.addingTimeInterval(601)
        harness.web.submitResult = AutoCheckInSubmitResult(
            ok: true,
            statusCode: 200,
            success: true,
            message: "ok",
            current: 5,
            reason: "submitted"
        )
        let second = await harness.coordinator.runIfNeeded(presentationContext: nil)

        #expect(first == .failed("server_error"))
        #expect(second == .submitted(message: "ok"))
        #expect(harness.web.submitModes == [.fixedChickenLeg, .fixedChickenLeg])
        #expect(harness.stateStore.isCompleted(on: harness.dayIdentifier) == true)
    }

    @Test func sanitizesSubmittedMessageForOutcomeAndAlert() async throws {
        let harness = try Harness(settings: AutoCheckInSettings(isEnabled: true, mode: .fixedChickenLeg))
        harness.web.submitResult = AutoCheckInSubmitResult(
            ok: true,
            statusCode: 200,
            success: true,
            message: "签到\n成功\r",
            current: 5,
            reason: "submitted"
        )

        let outcome = await harness.coordinator.runIfNeeded(presentationContext: UIViewController())

        #expect(outcome == .submitted(message: "签到 成功"))
        #expect(harness.alerter.alerts == [AutoCheckInAlert(title: "自动签到成功", message: "签到 成功")])
    }

    @Test func failedSubmitLogIncludesElapsedStatusAndSanitizedMessage() async throws {
        try await withTemporaryFileLogging {
            let harness = try Harness(settings: AutoCheckInSettings(isEnabled: true, mode: .fixedChickenLeg))
            harness.web.submitResult = AutoCheckInSubmitResult(
                ok: false,
                statusCode: 500,
                success: false,
                message: "server\ndown\r",
                current: nil,
                reason: "server_error"
            )

            _ = await harness.coordinator.runIfNeeded(presentationContext: nil)
            AppLog.flushFileLogsForTesting()

            let content = try AppLog.fileLogContent()
            let failureLine = try #require(logLine(in: content, containing: "failure reason=server_error"))
            #expect(failureLine.contains("runID=test1234"))
            #expect(failureLine.contains("status=500"))
            #expect(failureLine.contains("elapsedMs="))
            #expect(failureLine.contains("message=server down"))
        }
    }

    @Test func boardStateFailureLogIncludesElapsedStatusAndSanitizedMessage() async throws {
        try await withTemporaryFileLogging {
            let harness = try Harness(settings: AutoCheckInSettings(isEnabled: true, mode: .fixedChickenLeg))
            harness.web.boardState = AutoCheckInBoardState(
                ok: false,
                isLoggedIn: true,
                isCheckedIn: false,
                message: "board\nstate failed",
                detectionSource: "javascript_exception",
                reason: "javascript_exception",
                statusCode: nil,
                responseKeys: []
            )

            _ = await harness.coordinator.runIfNeeded(presentationContext: nil)
            AppLog.flushFileLogsForTesting()

            let content = try AppLog.fileLogContent()
            let failureLine = try #require(logLine(in: content, containing: "failure reason=javascript_exception"))
            #expect(failureLine.contains("runID=test1234"))
            #expect(failureLine.contains("status=nil"))
            #expect(failureLine.contains("elapsedMs="))
            #expect(failureLine.contains("message=board state failed"))
            let finishLine = try #require(logLine(in: content, containing: "finish outcome=failed"))
            #expect(finishLine.contains("elapsedMs="))
        }
    }

    @Test func exceptionFailureLogIncludesElapsedAndSanitizedMessage() async throws {
        try await withTemporaryFileLogging {
            let harness = try Harness(settings: AutoCheckInSettings(isEnabled: true, mode: .fixedChickenLeg))
            harness.web.submitError = TestError.webFailed

            _ = await harness.coordinator.runIfNeeded(presentationContext: nil)
            AppLog.flushFileLogsForTesting()

            let content = try AppLog.fileLogContent()
            let failureLine = try #require(logLine(in: content, containing: "failure reason=exception"))
            #expect(failureLine.contains("runID=test1234"))
            #expect(failureLine.contains("elapsedMs="))
            #expect(failureLine.contains("message=web failed"))
        }
    }

    private func logLine(in content: String, containing marker: String) -> String? {
        content.split(separator: "\n").map(String.init).first { $0.contains(marker) }
    }

    private func withTemporaryFileLogging(_ body: () async throws -> Void) async throws {
        try await FileLoggingTestGate.shared.withExclusiveAccess {
            let previousFileLoggingEnabled = NodeSeekDebugConfig.enableFileLogging
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            defer {
                try? FileManager.default.removeItem(at: directory)
                NodeSeekDebugConfig.enableFileLogging = previousFileLoggingEnabled
                AppLog.setFileLogDirectoryForTesting(nil)
            }

            AppLog.setFileLogDirectoryForTesting(directory)
            NodeSeekDebugConfig.enableFileLogging = true

            try await body()
        }
    }

    @MainActor
    private final class Harness {
        let now = Date(timeIntervalSince1970: 1_777_777_777)
        let clock: MutableClock
        var currentNow: Date {
            get { clock.now }
            set { clock.now = newValue }
        }
        let dayIdentifier: String
        let settingsStore: AutoCheckInSettingsStore
        let stateStore: AutoCheckInStateStore
        let web = FakeAutoCheckInWebAutomator()
        let alerter = CapturingAutoCheckInAlerter()
        let coordinator: AutoCheckInCoordinator

        init(settings: AutoCheckInSettings) throws {
            clock = MutableClock(now)
            let settingsDefaults = try #require(UserDefaults(suiteName: "auto-check-in-coordinator-settings-\(UUID().uuidString)"))
            let stateDefaults = try #require(UserDefaults(suiteName: "auto-check-in-coordinator-state-\(UUID().uuidString)"))
            settingsStore = AutoCheckInSettingsStore(userDefaults: settingsDefaults, storageKey: "settings")
            stateStore = AutoCheckInStateStore(userDefaults: stateDefaults, storageKey: "state")
            settingsStore.setEnabled(settings.isEnabled)
            settingsStore.setMode(settings.mode)
            dayIdentifier = AutoCheckInDayIdentifier.string(
                for: now,
                calendar: Calendar(identifier: .gregorian),
                timeZone: TimeZone(secondsFromGMT: 8 * 3600)!
            )
            let runDayIdentifier = dayIdentifier
            let runClock = clock
            coordinator = AutoCheckInCoordinator(
                settingsStore: settingsStore,
                stateStore: stateStore,
                webAutomator: web,
                alerter: alerter,
                now: { runClock.now },
                dayIdentifierProvider: { runDayIdentifier },
                runIDProvider: { "test1234" },
                cooldownInterval: 600
            )
        }
    }
}

@MainActor
private final class FakeAutoCheckInWebAutomator: AutoCheckInWebAutomating {
    var boardCalls = 0
    var submitModes: [AutoCheckInMode] = []
    var suspendBoardState = false
    var boardContinuation: CheckedContinuation<AutoCheckInBoardState, Error>?
    var submitError: Error?
    var boardState = AutoCheckInBoardState(
        ok: true,
        isLoggedIn: true,
        isCheckedIn: false,
        message: nil,
        detectionSource: "board_api",
        reason: "loaded",
        statusCode: 200,
        responseKeys: ["record"]
    )
    var submitResult = AutoCheckInSubmitResult(
        ok: true,
        statusCode: 200,
        success: true,
        message: "ok",
        current: 5,
        reason: "submitted"
    )

    func fetchBoardState(runID: String) async throws -> AutoCheckInBoardState {
        boardCalls += 1
        if suspendBoardState {
            return try await withCheckedThrowingContinuation { continuation in
                boardContinuation = continuation
            }
        }
        return boardState
    }

    func submit(mode: AutoCheckInMode, runID: String) async throws -> AutoCheckInSubmitResult {
        submitModes.append(mode)
        if let submitError {
            throw submitError
        }
        return submitResult
    }

    func resumeBoardState() {
        boardContinuation?.resume(returning: boardState)
        boardContinuation = nil
        suspendBoardState = false
    }
}

@MainActor
private final class CapturingAutoCheckInAlerter: AutoCheckInAlertPresenting {
    var alerts: [AutoCheckInAlert] = []
    var shouldShow = true
    var showCalls = 0

    func show(_ alert: AutoCheckInAlert, from presentationContext: UIViewController) -> Bool {
        showCalls += 1
        guard shouldShow else { return false }
        alerts.append(alert)
        return true
    }
}

private enum TestError: LocalizedError {
    case webFailed

    var errorDescription: String? {
        switch self {
        case .webFailed:
            return "web\nfailed"
        }
    }
}

private final class MutableClock {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }
}
