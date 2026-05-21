//
//  AutoCheckInSettingsViewController.swift
//  nodeseek
//

import UIKit

final class AutoCheckInSettingsViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case enable
        case mode
    }

    private let settingsStore: AutoCheckInSettingsStore

    init(settingsStore: AutoCheckInSettingsStore = .shared) {
        self.settingsStore = settingsStore
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "自动签到"
        tableView.accessibilityIdentifier = "auto-check-in-settings-table-view"
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .enable:
            return 1
        case .mode:
            return AutoCheckInMode.allCases.count
        case .none:
            return 0
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .enable:
            return "开关"
        case .mode:
            return "签到方式"
        case .none:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {
        case .enable:
            return enableCell()
        case .mode:
            return modeCell(for: indexPath)
        case .none:
            return UITableViewCell()
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard Section(rawValue: indexPath.section) == .mode else { return }
        settingsStore.setMode(AutoCheckInMode.allCases[indexPath.row])
        tableView.reloadSections(IndexSet(integer: Section.mode.rawValue), with: .none)
    }

    private func enableCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = "自动签到"
        let toggle = UISwitch()
        toggle.isOn = settingsStore.settings.isEnabled
        toggle.accessibilityIdentifier = "auto-check-in-enabled-switch"
        toggle.addTarget(self, action: #selector(enabledSwitchChanged(_:)), for: .valueChanged)
        cell.accessoryView = toggle
        cell.selectionStyle = .none
        cell.accessibilityIdentifier = "auto-check-in-enabled-cell"
        return cell
    }

    private func modeCell(for indexPath: IndexPath) -> UITableViewCell {
        let mode = AutoCheckInMode.allCases[indexPath.row]
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = mode.displayName
        cell.accessoryType = settingsStore.settings.mode == mode ? .checkmark : .none
        cell.accessibilityIdentifier = "auto-check-in-mode-\(mode.rawValue)-cell"
        return cell
    }

    @objc private func enabledSwitchChanged(_ sender: UISwitch) {
        settingsStore.setEnabled(sender.isOn)
    }
}
