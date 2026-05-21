//
//  AutoCheckInModule.swift
//  nodeseek
//

import UIKit

@MainActor
enum AutoCheckInModule {
    private static let settingsStore = AutoCheckInSettingsStore.shared
    private static let coordinator = AutoCheckInCoordinator(settingsStore: settingsStore)

    static func runIfNeeded(presentationContext: UIViewController?) async {
        _ = await coordinator.runIfNeeded(presentationContext: presentationContext)
    }

    static func makeSettingsViewController() -> UIViewController {
        AutoCheckInSettingsViewController(settingsStore: settingsStore)
    }

    static var settingsSummary: String {
        settingsStore.summary
    }
}
