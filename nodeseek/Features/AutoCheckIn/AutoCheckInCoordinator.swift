//
//  AutoCheckInCoordinator.swift
//  nodeseek
//

import Foundation
import UIKit

struct AutoCheckInToast: Equatable, Sendable {
    let title: String
    let message: String
}

@MainActor
protocol AutoCheckInToastPresenting: AnyObject {
    func show(_ toast: AutoCheckInToast, from presentationContext: UIViewController) -> Bool
}

@MainActor
final class DefaultAutoCheckInToastPresenter: AutoCheckInToastPresenting {
    private let displayDuration: TimeInterval

    init(displayDuration: TimeInterval = 5) {
        self.displayDuration = displayDuration
    }

    func show(_ toast: AutoCheckInToast, from presentationContext: UIViewController) -> Bool {
        guard let window = availableWindow(from: presentationContext) else {
            return false
        }

        window.subviews
            .filter { $0.accessibilityIdentifier == "auto-check-in-toast" }
            .forEach { $0.removeFromSuperview() }

        let toastView = makeToastView(toast)
        window.addSubview(toastView)
        NSLayoutConstraint.activate([
            toastView.leadingAnchor.constraint(greaterThanOrEqualTo: window.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            toastView.trailingAnchor.constraint(lessThanOrEqualTo: window.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            toastView.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            toastView.bottomAnchor.constraint(equalTo: window.safeAreaLayoutGuide.bottomAnchor, constant: -24)
        ])

        window.layoutIfNeeded()
        toastView.alpha = 0
        toastView.transform = CGAffineTransform(translationX: 0, y: 10)
        UIView.animate(withDuration: 0.24, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            toastView.alpha = 1
            toastView.transform = .identity
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + displayDuration) { [weak toastView] in
            guard let toastView, toastView.superview != nil else { return }
            UIView.animate(withDuration: 0.24, delay: 0, options: [.curveEaseIn, .allowUserInteraction]) {
                toastView.alpha = 0
                toastView.transform = CGAffineTransform(translationX: 0, y: 10)
            } completion: { _ in
                toastView.removeFromSuperview()
            }
        }
        return true
    }

    private func availableWindow(from presentationContext: UIViewController) -> UIWindow? {
        let activeWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        return activeWindow ?? presentationContext.view.window
    }

    private func makeToastView(_ toast: AutoCheckInToast) -> UIView {
        let container = UIView()
        container.accessibilityIdentifier = "auto-check-in-toast"
        container.backgroundColor = UIColor.label.withAlphaComponent(0.94)
        container.layer.cornerRadius = 14
        container.layer.cornerCurve = .continuous
        container.layer.shadowColor = UIColor.black.cgColor
        container.layer.shadowOpacity = 0.18
        container.layer.shadowRadius = 14
        container.layer.shadowOffset = CGSize(width: 0, height: 8)
        container.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
        iconView.tintColor = .systemGreen
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = toast.title
        titleLabel.font = UIFontMetrics.default.scaledFont(for: .systemFont(ofSize: 15, weight: .semibold))
        titleLabel.textColor = .systemBackground
        titleLabel.numberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let messageLabel = UILabel()
        messageLabel.text = toast.message
        messageLabel.font = .preferredFont(forTextStyle: .footnote)
        messageLabel.textColor = UIColor.systemBackground.withAlphaComponent(0.84)
        messageLabel.numberOfLines = 2
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [titleLabel, messageLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(iconView)
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            stack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
        ])
        return container
    }
}

@MainActor
protocol AutoCheckInAccountStatusProviding: AnyObject {
    func isLoggedIn() async -> Bool?
}

@MainActor
final class CurrentAccountAutoCheckInStatusProvider: AutoCheckInAccountStatusProviding {
    private let store: CurrentAccountStore

    init(store: CurrentAccountStore = .shared) {
        self.store = store
    }

    func isLoggedIn() async -> Bool? {
        await store.snapshot()?.account.isLoggedIn
    }
}

@MainActor
final class AutoCheckInCoordinator {
    private let settingsStore: AutoCheckInSettingsStore
    private let stateStore: AutoCheckInStateStore
    private let webAutomator: AutoCheckInWebAutomating
    private let accountStatus: AutoCheckInAccountStatusProviding
    private let toastPresenter: AutoCheckInToastPresenting
    private let now: () -> Date
    private let dayIdentifierProvider: () -> String
    private let runIDProvider: () -> String
    private let challengeCooldownInterval: TimeInterval
    private let failureCooldownInterval: TimeInterval
    private let triggerDelayInterval: TimeInterval
    private let delay: @MainActor (TimeInterval) async -> Void
    private var inFlightTask: Task<AutoCheckInRunOutcome, Never>?
    private var activeRunID: String?
    private var cooldownUntil: Date?

    init(
        settingsStore: AutoCheckInSettingsStore? = nil,
        stateStore: AutoCheckInStateStore? = nil,
        webAutomator: AutoCheckInWebAutomating? = nil,
        accountStatus: AutoCheckInAccountStatusProviding? = nil,
        toastPresenter: AutoCheckInToastPresenting? = nil,
        now: @escaping () -> Date = Date.init,
        dayIdentifierProvider: (() -> String)? = nil,
        runIDProvider: @escaping () -> String = { String(UUID().uuidString.prefix(8)) },
        cooldownInterval: TimeInterval = 120,
        failureCooldownInterval: TimeInterval = 30,
        triggerDelayInterval: TimeInterval = 3,
        delay: @escaping @MainActor (TimeInterval) async -> Void = { seconds in
            guard seconds > 0 else { return }
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    ) {
        self.settingsStore = settingsStore ?? .shared
        self.stateStore = stateStore ?? .shared
        self.webAutomator = webAutomator ?? WebViewAutoCheckInAutomator()
        self.accountStatus = accountStatus ?? CurrentAccountAutoCheckInStatusProvider()
        self.toastPresenter = toastPresenter ?? DefaultAutoCheckInToastPresenter()
        self.now = now
        self.dayIdentifierProvider = dayIdentifierProvider ?? { AutoCheckInDayIdentifier.current() }
        self.runIDProvider = runIDProvider
        self.challengeCooldownInterval = cooldownInterval
        self.failureCooldownInterval = failureCooldownInterval
        self.triggerDelayInterval = triggerDelayInterval
        self.delay = delay
    }

    func runIfNeeded(
        presentationContext: UIViewController?,
        trigger: AutoCheckInTrigger = .postListAllFirstPage
    ) async -> AutoCheckInRunOutcome {
        if let inFlightTask {
            AppLog.notice(.autoCheckIn, "runID=\(activeRunID ?? "unknown") skip=in_flight")
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
        let loggedIn = await accountStatus.isLoggedIn()
        AppLog.notice(
            .autoCheckIn,
            "runID=\(runID) start trigger=\(trigger.rawValue) day=\(dayIdentifier) timezone=Asia/Shanghai enabled=\(settings.isEnabled) mode=\(settings.mode.rawValue) random=\(settings.mode.randomQueryValue) loggedIn=\(Self.describeLoggedIn(loggedIn)) hasPresentationContext=\(presentationContext != nil) presentation=\(presentationContext.map { String(describing: type(of: $0)) } ?? "nil") lastCompletedDay=\(stateStore.state.completedDayIdentifier ?? "nil")"
        )

        guard settings.isEnabled else {
            AppLog.notice(.autoCheckIn, "runID=\(runID) skip=disabled")
            return finish(.skipped("disabled"), runID: runID, startedAt: startedAt, detail: "reason=disabled")
        }

        guard stateStore.isCompleted(on: dayIdentifier) == false else {
            AppLog.notice(.autoCheckIn, "runID=\(runID) skip=completed_today day=\(dayIdentifier)")
            return finish(.skipped("completed_today"), runID: runID, startedAt: startedAt, detail: "reason=completed_today")
        }

        if let cooldownUntil, cooldownUntil > startedAt {
            let remaining = Int(ceil(cooldownUntil.timeIntervalSince(startedAt)))
            AppLog.notice(.autoCheckIn, "runID=\(runID) skip=cooldown remainingSeconds=\(remaining)")
            return finish(.skipped("cooldown"), runID: runID, startedAt: startedAt, detail: "reason=cooldown")
        }

        if loggedIn == false {
            AppLog.notice(.autoCheckIn, "runID=\(runID) skip=not_logged_in source=account_store")
            return finish(.skipped("not_logged_in"), runID: runID, startedAt: startedAt, detail: "reason=not_logged_in")
        }

        let delaySeconds = Self.triggerDelaySeconds(for: trigger, configured: triggerDelayInterval)
        if delaySeconds > 0 {
            AppLog.notice(.autoCheckIn, "runID=\(runID) trigger_delay seconds=\(Int(delaySeconds)) trigger=\(trigger.rawValue)")
            await delay(delaySeconds)
            AppLog.notice(.autoCheckIn, "runID=\(runID) trigger_delay_done elapsedMs=\(elapsedMilliseconds(since: startedAt))")
        } else {
            AppLog.notice(.autoCheckIn, "runID=\(runID) trigger_delay skipped trigger=\(trigger.rawValue)")
        }

        do {
            let boardState = try await webAutomator.fetchBoardState(runID: runID)
            let sanitizedBoardMessage = sanitize(boardState.message)

            guard boardState.ok else {
                startCooldown(reason: boardState.reason, runID: runID)
                AppLog.warning(.autoCheckIn, "runID=\(runID) failure reason=\(boardState.reason) status=\(boardState.statusCode.map(String.init) ?? "nil") elapsedMs=\(elapsedMilliseconds(since: startedAt)) message=\(sanitizedBoardMessage ?? "nil")")
                return finish(.failed(boardState.reason), runID: runID, startedAt: startedAt, detail: "reason=\(boardState.reason)")
            }

            if boardState.isCheckedIn {
                stateStore.markCompleted(dayIdentifier: dayIdentifier, at: now())
                AppLog.notice(.autoCheckIn, "runID=\(runID) state_write day=\(dayIdentifier) source=board_state")
                AppLog.notice(.autoCheckIn, "runID=\(runID) toast=skipped reason=already_checked_in")
                return finish(.alreadyCheckedIn, runID: runID, startedAt: startedAt, detail: "source=board_state")
            }

            let submit = try await webAutomator.submit(mode: settings.mode, runID: runID)
            let sanitizedMessage = sanitize(submit.message)

            if submit.ok == false, isAlreadyCheckedInSubmitMessage(sanitizedMessage) {
                stateStore.markCompleted(dayIdentifier: dayIdentifier, at: now())
                AppLog.notice(.autoCheckIn, "runID=\(runID) state_write day=\(dayIdentifier) source=submit_already_checked_in")
                AppLog.notice(.autoCheckIn, "runID=\(runID) toast=skipped reason=already_checked_in")
                return finish(.alreadyCheckedIn, runID: runID, startedAt: startedAt, detail: "source=submit_already_checked_in")
            }

            guard submit.ok else {
                startCooldown(reason: submit.reason, runID: runID)
                AppLog.warning(.autoCheckIn, "runID=\(runID) failure reason=\(submit.reason) status=\(submit.statusCode.map(String.init) ?? "nil") elapsedMs=\(elapsedMilliseconds(since: startedAt)) message=\(sanitizedMessage ?? "nil")")
                return finish(.failed(submit.reason), runID: runID, startedAt: startedAt, detail: "reason=\(submit.reason)")
            }

            stateStore.markCompleted(dayIdentifier: dayIdentifier, at: now())
            AppLog.notice(.autoCheckIn, "runID=\(runID) state_write day=\(dayIdentifier) source=submit_success")
            let toastMessage = sanitizedMessage?.isEmpty == false ? sanitizedMessage! : "已完成今日签到。"
            if let presentationContext {
                let didShow = toastPresenter.show(
                    AutoCheckInToast(title: "自动签到成功", message: toastMessage),
                    from: presentationContext
                )
                if didShow {
                    AppLog.notice(.autoCheckIn, "runID=\(runID) toast=shown title=自动签到成功")
                } else {
                    AppLog.notice(.autoCheckIn, "runID=\(runID) toast=skipped reason=presentation_unavailable")
                }
            } else {
                AppLog.notice(.autoCheckIn, "runID=\(runID) toast=skipped reason=no_presentation_context")
            }
            return finish(.submitted(message: sanitizedMessage), runID: runID, startedAt: startedAt, detail: "source=submit_success")
        } catch {
            startCooldown(reason: "exception", runID: runID)
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
        AppLog.notice(.autoCheckIn, "runID=\(runID) finish outcome=\(outcome.logValue) elapsedMs=\(elapsedMilliseconds(since: startedAt)) \(detail)")
        return outcome
    }

    private func startCooldown(reason: String, runID: String) {
        let interval = reason == "challenge" ? challengeCooldownInterval : failureCooldownInterval
        cooldownUntil = now().addingTimeInterval(interval)
        AppLog.notice(.autoCheckIn, "runID=\(runID) cooldown_start reason=\(reason) seconds=\(Int(interval))")
    }

    private static func triggerDelaySeconds(for trigger: AutoCheckInTrigger, configured: TimeInterval) -> TimeInterval {
        switch trigger {
        case .postListAllFirstPage:
            return configured
        case .postListAppear, .settingsEnabled, .sceneBecomeActive:
            return 0
        }
    }

    private static func describeLoggedIn(_ value: Bool?) -> String {
        switch value {
        case true:
            return "true"
        case false:
            return "false"
        case nil:
            return "unknown"
        }
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
