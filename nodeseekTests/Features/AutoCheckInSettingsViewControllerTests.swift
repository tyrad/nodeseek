//
//  AutoCheckInSettingsViewControllerTests.swift
//  nodeseekTests
//

import Testing
import UIKit
@testable import nodeseek

@MainActor
struct AutoCheckInSettingsViewControllerTests {
    @Test func settingsScreenShowsSwitchAndModeRows() throws {
        let store = makeStore()
        let viewController = AutoCheckInSettingsViewController(settingsStore: store)
        viewController.loadViewIfNeeded()

        #expect(viewController.title == "自动签到")
        #expect(viewController.tableView.numberOfSections == 2)
        #expect(viewController.tableView.numberOfRows(inSection: 0) == 1)
        #expect(viewController.tableView.numberOfRows(inSection: 1) == 2)
        #expect(viewController.tableView.dataSource?.tableView?(
            viewController.tableView,
            titleForHeaderInSection: 0
        ) == "开关")
        #expect(viewController.tableView.dataSource?.tableView?(
            viewController.tableView,
            titleForHeaderInSection: 1
        ) == "签到方式")

        let enableCell = try #require(viewController.tableView.dataSource?.tableView(
            viewController.tableView,
            cellForRowAt: IndexPath(row: 0, section: 0)
        ))
        let enableSwitch = try #require(enableCell.accessoryView as? UISwitch)
        #expect(enableCell.textLabel?.text == "自动签到")
        #expect(enableSwitch.isOn == false)

        let fixedModeCell = try #require(viewController.tableView.dataSource?.tableView(
            viewController.tableView,
            cellForRowAt: IndexPath(row: 0, section: 1)
        ))
        let randomModeCell = try #require(viewController.tableView.dataSource?.tableView(
            viewController.tableView,
            cellForRowAt: IndexPath(row: 1, section: 1)
        ))
        #expect(fixedModeCell.textLabel?.text == "鸡腿 x 5")
        #expect(fixedModeCell.accessoryType == .checkmark)
        #expect(randomModeCell.textLabel?.text == "试试手气")
        #expect(randomModeCell.accessoryType == .none)
    }

    @Test func togglingSwitchPersistsEnabledSetting() throws {
        let store = makeStore()
        let viewController = AutoCheckInSettingsViewController(settingsStore: store)
        viewController.loadViewIfNeeded()

        let enableCell = try #require(viewController.tableView.dataSource?.tableView(
            viewController.tableView,
            cellForRowAt: IndexPath(row: 0, section: 0)
        ))
        let enableSwitch = try #require(enableCell.accessoryView as? UISwitch)
        enableSwitch.isOn = true
        enableSwitch.sendActions(for: .valueChanged)

        #expect(store.settings.isEnabled == true)
    }

    @Test func selectingRandomModePersistsSettingAndMovesCheckmark() throws {
        let store = makeStore()
        let viewController = AutoCheckInSettingsViewController(settingsStore: store)
        viewController.loadViewIfNeeded()

        viewController.tableView.delegate?.tableView?(
            viewController.tableView,
            didSelectRowAt: IndexPath(row: 1, section: 1)
        )

        #expect(store.settings == AutoCheckInSettings(isEnabled: false, mode: .random))
        let fixedModeCell = try #require(viewController.tableView.dataSource?.tableView(
            viewController.tableView,
            cellForRowAt: IndexPath(row: 0, section: 1)
        ))
        let randomModeCell = try #require(viewController.tableView.dataSource?.tableView(
            viewController.tableView,
            cellForRowAt: IndexPath(row: 1, section: 1)
        ))
        #expect(fixedModeCell.accessoryType == .none)
        #expect(randomModeCell.accessoryType == .checkmark)
    }

    private func makeStore() -> AutoCheckInSettingsStore {
        let suiteName = "auto-check-in-ui-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return AutoCheckInSettingsStore(userDefaults: defaults, storageKey: "settings")
    }
}
