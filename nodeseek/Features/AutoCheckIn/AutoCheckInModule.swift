//
//  AutoCheckInModule.swift
//  nodeseek
//

import UIKit

@MainActor
enum AutoCheckInModule {
    private static let settingsStore = AutoCheckInSettingsStore.shared
    private static let coordinator = AutoCheckInCoordinator(settingsStore: settingsStore)

    static func runIfNeeded(
        presentationContext: UIViewController?,
        trigger: AutoCheckInTrigger = .postListAllFirstPage
    ) async {
        _ = await coordinator.runIfNeeded(
            presentationContext: presentationContext,
            trigger: trigger
        )
    }

    static func checkInFromSiri() async -> AutoCheckInRunOutcome {
        await (UIApplication.shared.delegate as? AppDelegate)?.accountLaunchPreparation?.value
        _ = await CurrentAccountRefresher.shared.refreshIfNeeded(maxAge: 60)
        return await coordinator.runIfNeeded(presentationContext: nil, trigger: .siri)
    }

    static func makeSettingsViewController() -> UIViewController {
        AutoCheckInSettingsViewController(settingsStore: settingsStore)
    }

    static var settingsSummary: String {
        settingsStore.summary
    }
}
