//
//  SettingsViewControllerTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/5/2.
//

import Testing
import UIKit
@testable import nodeseek

@MainActor
struct SettingsViewControllerTests {
    @Test func settingsPageShowsCacheActionAndLogoutAtBottom() async throws {
        let previousFileLogging = NodeSeekDebugConfig.enableFileLogging
        defer { NodeSeekDebugConfig.enableFileLogging = previousFileLogging }
        NodeSeekDebugConfig.enableFileLogging = false
        let viewController = SettingsViewController(
            cacheManager: FakeSettingsCacheManager(cacheByteSize: 4_096),
            sessionManager: FakeSettingsSessionManager()
        )
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)

        let tableView = try #require(viewController.tableView)
        #expect(viewController.title == "设置")
        #expect(tableView.numberOfSections == 3)
        #expect(tableView.numberOfRows(inSection: 0) == 1)
        #expect(tableView.numberOfRows(inSection: 1) == 3)
        #expect(tableView.numberOfRows(inSection: 2) == 1)
        #expect(tableView.dataSource?.tableView?(tableView, titleForHeaderInSection: 1) == "调试")

        let cacheCell = try #require(tableView.dataSource?.tableView(
            tableView,
            cellForRowAt: IndexPath(row: 0, section: 0)
        ))
        let logCell = try #require(tableView.dataSource?.tableView(
            tableView,
            cellForRowAt: IndexPath(row: 0, section: 1)
        ))
        let logFileCell = try #require(tableView.dataSource?.tableView(
            tableView,
            cellForRowAt: IndexPath(row: 1, section: 1)
        ))
        let detailTestCell = try #require(tableView.dataSource?.tableView(
            tableView,
            cellForRowAt: IndexPath(row: 2, section: 1)
        ))
        let logoutCell = try #require(tableView.dataSource?.tableView(
            tableView,
            cellForRowAt: IndexPath(row: 0, section: 2)
        ))

        #expect(cacheCell.textLabel?.text == "清除缓存")
        #expect(cacheCell.detailTextLabel?.text == "4 KB")
        #expect(logCell.textLabel?.text == "记录日志")
        let loggingSwitch = try #require(logCell.accessoryView as? UISwitch)
        #expect(loggingSwitch.isOn == false)
        #expect(logFileCell.textLabel?.text == "日志文件")
        #expect(detailTestCell.textLabel?.text == "详情测试")
        #expect(logoutCell.textLabel?.text == "退出登录")
        #expect(logoutCell.textLabel?.textColor == .systemRed)
    }

    @Test func selectingClearCacheClearsCacheWithoutLoggingOut() async throws {
        let cacheManager = FakeSettingsCacheManager(cacheByteSize: 4_096)
        let sessionManager = FakeSettingsSessionManager()
        let viewController = SettingsViewController(
            cacheManager: cacheManager,
            sessionManager: sessionManager,
            confirmsActionsImmediately: true
        )
        viewController.loadViewIfNeeded()

        viewController.tableView.delegate?.tableView?(
            viewController.tableView,
            didSelectRowAt: IndexPath(row: 0, section: 0)
        )
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(cacheManager.clearCount == 1)
        #expect(sessionManager.logoutCount == 0)
    }

    @Test func selectingLogoutLogsOutAndRunsCallback() async throws {
        let cacheManager = FakeSettingsCacheManager(cacheByteSize: 4_096)
        let sessionManager = FakeSettingsSessionManager()
        var logoutCallbackCount = 0
        let viewController = SettingsViewController(
            cacheManager: cacheManager,
            sessionManager: sessionManager,
            confirmsActionsImmediately: true,
            onLogout: {
                logoutCallbackCount += 1
            }
        )
        viewController.loadViewIfNeeded()

        viewController.tableView.delegate?.tableView?(
            viewController.tableView,
            didSelectRowAt: IndexPath(row: 0, section: 2)
        )
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(cacheManager.clearCount == 0)
        #expect(sessionManager.logoutCount == 1)
        #expect(logoutCallbackCount == 1)
    }

    @Test func selectingDebugRowsRunsDebugCallbacks() throws {
        var logFileTapCount = 0
        var detailTestTapCount = 0
        let viewController = SettingsViewController(
            cacheManager: FakeSettingsCacheManager(cacheByteSize: 0),
            sessionManager: FakeSettingsSessionManager(),
            onLogFile: {
                logFileTapCount += 1
            },
            onDetailTest: {
                detailTestTapCount += 1
            }
        )
        viewController.loadViewIfNeeded()

        viewController.tableView.delegate?.tableView?(
            viewController.tableView,
            didSelectRowAt: IndexPath(row: 1, section: 1)
        )
        viewController.tableView.delegate?.tableView?(
            viewController.tableView,
            didSelectRowAt: IndexPath(row: 2, section: 1)
        )

        #expect(logFileTapCount == 1)
        #expect(detailTestTapCount == 1)
    }

    @Test func togglingFileLoggingSwitchUpdatesRuntimeConfig() throws {
        let previousFileLogging = NodeSeekDebugConfig.enableFileLogging
        defer { NodeSeekDebugConfig.enableFileLogging = previousFileLogging }
        NodeSeekDebugConfig.enableFileLogging = false
        let viewController = SettingsViewController(
            cacheManager: FakeSettingsCacheManager(cacheByteSize: 0),
            sessionManager: FakeSettingsSessionManager()
        )
        viewController.loadViewIfNeeded()

        let cell = try #require(viewController.tableView.dataSource?.tableView(
            viewController.tableView,
            cellForRowAt: IndexPath(row: 0, section: 1)
        ))
        let loggingSwitch = try #require(cell.accessoryView as? UISwitch)
        loggingSwitch.isOn = true
        loggingSwitch.sendActions(for: .valueChanged)

        #expect(NodeSeekDebugConfig.enableFileLogging == true)
    }
}

@MainActor
private final class FakeSettingsCacheManager: SettingsCacheManaging {
    private(set) var clearCount = 0
    private var byteSize: UInt64

    init(cacheByteSize: UInt64) {
        self.byteSize = cacheByteSize
    }

    func cacheByteSize() async -> UInt64 {
        byteSize
    }

    func clearPreservingCookies() async throws {
        clearCount += 1
        byteSize = 0
    }
}

@MainActor
private final class FakeSettingsSessionManager: SettingsSessionManaging {
    private(set) var logoutCount = 0

    func logout() async {
        logoutCount += 1
    }
}
