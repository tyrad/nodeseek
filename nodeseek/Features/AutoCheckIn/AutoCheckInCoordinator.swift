//
//  AutoCheckInCoordinator.swift
//  nodeseek
//

import Foundation
import UIKit

struct AutoCheckInAlert: Equatable, Sendable {
    let title: String
    let message: String
}

@MainActor
protocol AutoCheckInAlertPresenting: AnyObject {
    func show(_ alert: AutoCheckInAlert, from presentationContext: UIViewController) -> Bool
}

@MainActor
final class DefaultAutoCheckInAlertPresenter: AutoCheckInAlertPresenting {
    func show(_ alert: AutoCheckInAlert, from presentationContext: UIViewController) -> Bool {
        guard let presenter = availablePresenter(from: presentationContext) else {
            return false
        }
        let alertController = UIAlertController(title: alert.title, message: alert.message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "确定", style: .default))
        presenter.present(alertController, animated: true)
        return true
    }

    private func availablePresenter(from presentationContext: UIViewController) -> UIViewController? {
        guard presentationContext.isViewLoaded, presentationContext.view.window != nil else {
            return nil
        }

        var presenter = presentationContext
        while let presented = presenter.presentedViewController {
            presenter = presented
        }

        guard presenter.isViewLoaded, presenter.view.window != nil else {
            return nil
        }
        guard (presenter is UIAlertController) == false else {
            return nil
        }
        guard presenter.isBeingDismissed == false,
              presenter.isBeingPresented == false,
              presenter.transitionCoordinator == nil else {
            return nil
        }
        return presenter
    }
}

@MainActor
final class AutoCheckInCoordinator {
    private let settingsStore: AutoCheckInSettingsStore
    private let stateStore: AutoCheckInStateStore
    private let webAutomator: AutoCheckInWebAutomating
    private let alerter: AutoCheckInAlertPresenting
    private let now: () -> Date
    private let dayIdentifierProvider: () -> String
    private let runIDProvider: () -> String
    private let cooldownInterval: TimeInterval
    private var inFlightTask: Task<AutoCheckInRunOutcome, Never>?
    private var activeRunID: String?
    private var cooldownUntil: Date?

    init(
        settingsStore: AutoCheckInSettingsStore? = nil,
        stateStore: AutoCheckInStateStore? = nil,
        webAutomator: AutoCheckInWebAutomating? = nil,
        alerter: AutoCheckInAlertPresenting? = nil,
        now: @escaping () -> Date = Date.init,
        dayIdentifierProvider: (() -> String)? = nil,
        runIDProvider: @escaping () -> String = { String(UUID().uuidString.prefix(8)) },
        cooldownInterval: TimeInterval = 600
    ) {
        self.settingsStore = settingsStore ?? .shared
        self.stateStore = stateStore ?? .shared
        self.webAutomator = webAutomator ?? WebViewAutoCheckInAutomator()
        self.alerter = alerter ?? DefaultAutoCheckInAlertPresenter()
        self.now = now
        self.dayIdentifierProvider = dayIdentifierProvider ?? { AutoCheckInDayIdentifier.current() }
        self.runIDProvider = runIDProvider
        self.cooldownInterval = cooldownInterval
    }

    func runIfNeeded(
        presentationContext: UIViewController?,
        trigger: AutoCheckInTrigger = .postListAllFirstPage
    ) async -> AutoCheckInRunOutcome {
        if let inFlightTask {
            AppLog.info(.autoCheckIn, "runID=\(activeRunID ?? "unknown") skip=in_flight")
            return await inFlightTask.value
        }

        let runID = runIDProvider()
        let task: Task<AutoCheckInRunOutcome, Never> = Task { @MainActor [weak self] in
            guard let self else { return .failed("coordinator_released") }
            return await self.performRun(
                runID: runID,
                trigger: trigger,
                presentationContext: presentationContext
            )
        }
        activeRunID = runID
        inFlightTask = task
        let outcome = await task.value
        inFlightTask = nil
        activeRunID = nil
        return outcome
    }

    private func performRun(
        runID: String,
        trigger: AutoCheckInTrigger,
        presentationContext: UIViewController?
    ) async -> AutoCheckInRunOutcome {
        let startedAt = now()
        let dayIdentifier = dayIdentifierProvider()
        let settings = settingsStore.settings
        AppLog.info(.autoCheckIn, "runID=\(runID) start trigger=\(trigger.rawValue) day=\(dayIdentifier) enabled=\(settings.isEnabled) mode=\(settings.mode.rawValue)")

        guard settings.isEnabled else {
            AppLog.info(.autoCheckIn, "runID=\(runID) skip=disabled")
            return finish(.skipped("disabled"), runID: runID, startedAt: startedAt, detail: "reason=disabled")
        }

        guard stateStore.isCompleted(on: dayIdentifier) == false else {
            AppLog.info(.autoCheckIn, "runID=\(runID) skip=completed_today day=\(dayIdentifier)")
            return finish(.skipped("completed_today"), runID: runID, startedAt: startedAt, detail: "reason=completed_today")
        }

        if let cooldownUntil, cooldownUntil > startedAt {
            AppLog.info(.autoCheckIn, "runID=\(runID) skip=cooldown until=\(cooldownUntil.timeIntervalSince1970)")
            return finish(.skipped("cooldown"), runID: runID, startedAt: startedAt, detail: "reason=cooldown")
        }

        do {
            AppLog.info(.autoCheckIn, "runID=\(runID) board_state_start endpoint=/api/attendance/board?page=1")
            let boardStartedAt = now()
            let boardState = try await webAutomator.fetchBoardState(runID: runID)
            let sanitizedBoardMessage = sanitize(boardState.message)
            AppLog.info(.autoCheckIn, "runID=\(runID) board_state_finish status=\(boardState.statusCode.map(String.init) ?? "nil") elapsedMs=\(elapsedMilliseconds(since: boardStartedAt)) ok=\(boardState.ok) reason=\(boardState.reason) loggedIn=\(boardState.isLoggedIn) checkedIn=\(boardState.isCheckedIn) source=\(boardState.detectionSource) keys=\(boardState.responseKeys.joined(separator: ",")) message=\(sanitizedBoardMessage ?? "nil")")

            guard boardState.ok else {
                cooldownUntil = now().addingTimeInterval(cooldownInterval)
                AppLog.warning(.autoCheckIn, "runID=\(runID) failure reason=\(boardState.reason) status=\(boardState.statusCode.map(String.init) ?? "nil") elapsedMs=\(elapsedMilliseconds(since: startedAt)) message=\(sanitizedBoardMessage ?? "nil")")
                return finish(.failed(boardState.reason), runID: runID, startedAt: startedAt, detail: "reason=\(boardState.reason)")
            }

            guard boardState.isLoggedIn else {
                AppLog.info(.autoCheckIn, "runID=\(runID) skip=not_logged_in source=\(boardState.detectionSource)")
                return finish(.skipped("not_logged_in"), runID: runID, startedAt: startedAt, detail: "reason=not_logged_in")
            }

            if boardState.isCheckedIn {
                stateStore.markCompleted(dayIdentifier: dayIdentifier, at: now())
                AppLog.info(.autoCheckIn, "runID=\(runID) state_write day=\(dayIdentifier) source=board_state")
                AppLog.info(.autoCheckIn, "runID=\(runID) alert=skipped reason=already_checked_in")
                return finish(.alreadyCheckedIn, runID: runID, startedAt: startedAt, detail: "source=board_state")
            }

            AppLog.info(.autoCheckIn, "runID=\(runID) submit_start mode=\(settings.mode.rawValue) random=\(settings.mode.randomQueryValue)")
            let submitStartedAt = now()
            let submit = try await webAutomator.submit(mode: settings.mode, runID: runID)
            let sanitizedMessage = sanitize(submit.message)
            AppLog.info(.autoCheckIn, "runID=\(runID) submit_finish status=\(submit.statusCode.map(String.init) ?? "nil") elapsedMs=\(elapsedMilliseconds(since: submitStartedAt)) ok=\(submit.ok) success=\(submit.success.map(String.init) ?? "nil") current=\(submit.current.map(String.init) ?? "nil") reason=\(submit.reason) message=\(sanitizedMessage ?? "nil")")

            if submit.ok == false, isAlreadyCheckedInSubmitMessage(sanitizedMessage) {
                stateStore.markCompleted(dayIdentifier: dayIdentifier, at: now())
                AppLog.info(.autoCheckIn, "runID=\(runID) state_write day=\(dayIdentifier) source=submit_already_checked_in")
                AppLog.info(.autoCheckIn, "runID=\(runID) alert=skipped reason=already_checked_in")
                return finish(.alreadyCheckedIn, runID: runID, startedAt: startedAt, detail: "source=submit_already_checked_in")
            }

            guard submit.ok else {
                cooldownUntil = now().addingTimeInterval(cooldownInterval)
                AppLog.warning(.autoCheckIn, "runID=\(runID) failure reason=\(submit.reason) status=\(submit.statusCode.map(String.init) ?? "nil") elapsedMs=\(elapsedMilliseconds(since: startedAt)) message=\(sanitizedMessage ?? "nil")")
                return finish(.failed(submit.reason), runID: runID, startedAt: startedAt, detail: "reason=\(submit.reason)")
            }

            stateStore.markCompleted(dayIdentifier: dayIdentifier, at: now())
            AppLog.info(.autoCheckIn, "runID=\(runID) state_write day=\(dayIdentifier) source=submit_success")
            let alertMessage = sanitizedMessage?.isEmpty == false ? sanitizedMessage! : "已完成今日签到。"
            if let presentationContext {
                let didShow = alerter.show(AutoCheckInAlert(title: "自动签到成功", message: alertMessage), from: presentationContext)
                if didShow {
                    AppLog.notice(.autoCheckIn, "runID=\(runID) alert=shown title=自动签到成功")
                } else {
                    AppLog.info(.autoCheckIn, "runID=\(runID) alert=skipped reason=presentation_unavailable")
                }
            } else {
                AppLog.info(.autoCheckIn, "runID=\(runID) alert=skipped reason=no_presentation_context")
            }
            return finish(.submitted(message: sanitizedMessage), runID: runID, startedAt: startedAt, detail: "source=submit_success")
        } catch {
            cooldownUntil = now().addingTimeInterval(cooldownInterval)
            AppLog.warning(.autoCheckIn, "runID=\(runID) failure reason=exception elapsedMs=\(elapsedMilliseconds(since: startedAt)) message=\(sanitize(error.localizedDescription) ?? "nil")")
            return finish(.failed("exception"), runID: runID, startedAt: startedAt, detail: "reason=exception")
        }
    }

    private func finish(
        _ outcome: AutoCheckInRunOutcome,
        runID: String,
        startedAt: Date,
        detail: String
    ) -> AutoCheckInRunOutcome {
        AppLog.info(.autoCheckIn, "runID=\(runID) finish outcome=\(outcome.logValue) elapsedMs=\(elapsedMilliseconds(since: startedAt)) \(detail)")
        return outcome
    }

    private func elapsedMilliseconds(since startDate: Date) -> Int {
        max(0, Int(now().timeIntervalSince(startDate) * 1_000))
    }

    private func sanitize(_ message: String?) -> String? {
        guard let message else { return nil }
        return message
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isAlreadyCheckedInSubmitMessage(_ message: String?) -> Bool {
        guard let message else { return false }
        return message.contains("已完成签到")
            || message.contains("请勿重复")
            || message.contains("已签到")
            || message.contains("已经签到")
    }
}

private extension AutoCheckInRunOutcome {
    var logValue: String {
        switch self {
        case let .skipped(reason):
            return "skipped:\(reason)"
        case .alreadyCheckedIn:
            return "already_checked_in"
        case .submitted:
            return "submitted"
        case let .failed(reason):
            return "failed:\(reason)"
        }
    }
}
