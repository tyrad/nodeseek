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
    @Test func settingsPageShowsCacheActionAndLogoutAtBottomWhenLoggedIn() async throws {
        try await withFileLoggingConfigIsolation {
            NodeSeekDebugConfig.enableFileLogging = false
            let defaults = try #require(UserDefaults(suiteName: "settings-account-\(UUID().uuidString)"))
            let accountStore = CurrentAccountStore(userDefaults: defaults, storageKey: "account")
            await accountStore.save(AccountResponse(displayName: "mistj", isLoggedIn: true))
            let viewController = SettingsViewController(
                cacheManager: FakeSettingsCacheManager(cacheByteSize: 4_096),
                sessionManager: FakeSettingsSessionManager(),
                currentAccountStore: accountStore,
                buildInfo: .testFlightFixture,
                nodeImageAPIKeyStore: FakeNodeImageAPIKeyStore(),
                autoCheckInSummaryProvider: { "未开启" }
            )
            viewController.loadViewIfNeeded()
            viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            viewController.view.layoutIfNeeded()
            try await waitUntil { viewController.tableView.numberOfRows(inSection: 5) == 1 }

            let tableView = try #require(viewController.tableView)
            #expect(viewController.title == "设置")
            #expect(tableView.numberOfSections == 6)
            #expect(tableView.numberOfRows(inSection: 0) == 3)
            #expect(tableView.numberOfRows(inSection: 1) == 3)
            #expect(tableView.numberOfRows(inSection: 2) == 1)
            #expect(tableView.numberOfRows(inSection: 3) == 4)
            #expect(tableView.numberOfRows(inSection: 4) == 6)
            #expect(tableView.numberOfRows(inSection: 5) == 1)
            #expect(tableView.dataSource?.tableView?(tableView, titleForHeaderInSection: 0) == "阅读")
            #expect(tableView.dataSource?.tableView?(tableView, titleForHeaderInSection: 1) == "功能")
            #expect(tableView.dataSource?.tableView?(tableView, titleForHeaderInSection: 2) == "存储")
            #expect(tableView.dataSource?.tableView?(tableView, titleForHeaderInSection: 3) == "调试")
            #expect(tableView.dataSource?.tableView?(tableView, titleForHeaderInSection: 4) == "关于")

            let cacheCell = try #require(tableView.dataSource?.tableView(
                tableView,
                cellForRowAt: IndexPath(row: 0, section: 2)
            ))
            let nodeImageCell = try #require(tableView.dataSource?.tableView(
                tableView,
                cellForRowAt: IndexPath(row: 0, section: 1)
            ))
            let specialFollowCell = try #require(tableView.dataSource?.tableView(
                tableView,
                cellForRowAt: IndexPath(row: 1, section: 1)
            ))
            let autoCheckInCell = try #require(tableView.dataSource?.tableView(
                tableView,
                cellForRowAt: IndexPath(row: 2, section: 1)
            ))
            let signatureCell = try #require(tableView.dataSource?.tableView(
                tableView,
                cellForRowAt: IndexPath(row: 2, section: 0)
            ))
            let logCell = try #require(tableView.dataSource?.tableView(
                tableView,
                cellForRowAt: IndexPath(row: 0, section: 3)
            ))
            let logFileCell = try #require(tableView.dataSource?.tableView(
                tableView,
                cellForRowAt: IndexPath(row: 1, section: 3)
            ))
            let detailTestCell = try #require(tableView.dataSource?.tableView(
                tableView,
                cellForRowAt: IndexPath(row: 2, section: 3)
            ))
            let debugLinksCell = try #require(tableView.dataSource?.tableView(
                tableView,
                cellForRowAt: IndexPath(row: 3, section: 3)
            ))
            let appVersionCell = try #require(tableView.dataSource?.tableView(
                tableView,
                cellForRowAt: IndexPath(row: 0, section: 4)
            ))
            let buildNumberCell = try #require(tableView.dataSource?.tableView(
                tableView,
                cellForRowAt: IndexPath(row: 1, section: 4)
            ))
            let gitCell = try #require(tableView.dataSource?.tableView(
                tableView,
                cellForRowAt: IndexPath(row: 2, section: 4)
            ))
            let repositoryCell = try #require(tableView.dataSource?.tableView(
                tableView,
                cellForRowAt: IndexPath(row: 3, section: 4)
            ))
            let workflowCell = try #require(tableView.dataSource?.tableView(
                tableView,
                cellForRowAt: IndexPath(row: 4, section: 4)
            ))
            let githubCell = try #require(tableView.dataSource?.tableView(
                tableView,
                cellForRowAt: IndexPath(row: 5, section: 4)
            ))
            let logoutCell = try #require(tableView.dataSource?.tableView(
                tableView,
                cellForRowAt: IndexPath(row: 0, section: 5)
            ))

            #expect(cacheCell.textLabel?.text == "清除缓存")
            #expect(cacheCell.detailTextLabel?.text == "4 KB")
            #expect(nodeImageCell.textLabel?.text == "NodeImage 授权")
            #expect(nodeImageCell.accessoryType == .disclosureIndicator)
            #expect(specialFollowCell.textLabel?.text == "特别关注")
            #expect(specialFollowCell.detailTextLabel?.text == "帖子列表关键字高亮展示")
            #expect(autoCheckInCell.textLabel?.text == "自动签到")
            #expect(autoCheckInCell.detailTextLabel?.text == "Beta · 未开启")
            #expect(autoCheckInCell.accessoryType == .disclosureIndicator)
            #expect(signatureCell.textLabel?.text == "显示帖子签名")
            let signatureSwitch = try #require(signatureCell.accessoryView as? UISwitch)
            #expect(signatureSwitch.isOn == true)
            #expect(logCell.textLabel?.text == "记录日志")
            let loggingSwitch = try #require(logCell.accessoryView as? UISwitch)
            #expect(loggingSwitch.isOn == false)
            #expect(logFileCell.textLabel?.text == "日志文件")
            #expect(detailTestCell.textLabel?.text == "详情测试")
            #expect(debugLinksCell.textLabel?.text == "调试链接")
            #expect(appVersionCell.textLabel?.text == "版本")
            #expect(appVersionCell.detailTextLabel?.text == "1.0.1")
            #expect(buildNumberCell.textLabel?.text == "Build")
            #expect(buildNumberCell.detailTextLabel?.text == "42")
            #expect(gitCell.textLabel?.text == "Git")
            #expect(gitCell.detailTextLabel?.text == "abcdef1")
            #expect(repositoryCell.textLabel?.text == "仓库")
            #expect(repositoryCell.detailTextLabel?.text == "https://github.com/tyrad/nodeseek")
            #expect(repositoryCell.accessoryType == .disclosureIndicator)
            #expect(workflowCell.textLabel?.text == "Workflow")
            #expect(workflowCell.detailTextLabel?.text == "TestFlight #25443881348")
            #expect(githubCell.textLabel?.text == "GitHub")
            #expect(githubCell.detailTextLabel?.text == "https://github.com/tyrad/nodeseek/actions/runs/25443881348")
            #expect(logoutCell.textLabel?.text == "退出登录")
            #expect(logoutCell.textLabel?.textColor == .systemRed)
        }
    }

    @Test func settingsPageHidesLogoutWhenNotLoggedIn() async throws {
        let defaults = try #require(UserDefaults(suiteName: "settings-account-\(UUID().uuidString)"))
        let accountStore = CurrentAccountStore(userDefaults: defaults, storageKey: "account")
        let viewController = SettingsViewController(
            cacheManager: FakeSettingsCacheManager(cacheByteSize: 4_096),
            sessionManager: FakeSettingsSessionManager(),
            currentAccountStore: accountStore,
            nodeImageAPIKeyStore: FakeNodeImageAPIKeyStore()
        )

        viewController.loadViewIfNeeded()
        try await waitUntil { viewController.tableView.numberOfRows(inSection: 5) == 0 }

        #expect(viewController.tableView.numberOfRows(inSection: 5) == 0)
    }

    @Test func togglingSignatureDisplaySwitchPersistsPreference() throws {
        let suiteName = "settings-signature-display-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let signatureSettings = PostSignatureDisplaySettings(userDefaults: defaults, storageKey: "show-signatures")
        let viewController = SettingsViewController(
            cacheManager: FakeSettingsCacheManager(cacheByteSize: 0),
            sessionManager: FakeSettingsSessionManager(),
            nodeImageAPIKeyStore: FakeNodeImageAPIKeyStore(),
            signatureDisplaySettings: signatureSettings
        )
        viewController.loadViewIfNeeded()

        let cell = try #require(viewController.tableView.dataSource?.tableView(
            viewController.tableView,
            cellForRowAt: IndexPath(row: 2, section: 0)
        ))
        let signatureSwitch = try #require(cell.accessoryView as? UISwitch)
        #expect(signatureSwitch.isOn == true)

        signatureSwitch.isOn = false
        signatureSwitch.sendActions(for: .valueChanged)

        #expect(signatureSettings.showsSignatures == false)
    }

    @Test func textSizeSliderPersistsOffsetAndUpdatesPreview() throws {
        let suiteName = "settings-text-size-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let textSizeSettings = AppTextSizeSettings(userDefaults: defaults, storageKey: "text-size")
        let viewController = SettingsViewController(
            cacheManager: FakeSettingsCacheManager(cacheByteSize: 0),
            sessionManager: FakeSettingsSessionManager(),
            nodeImageAPIKeyStore: FakeNodeImageAPIKeyStore(),
            textSizeSettings: textSizeSettings
        )
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.layoutIfNeeded()

        let adjustmentCell = try #require(viewController.tableView.dataSource?.tableView(
            viewController.tableView,
            cellForRowAt: IndexPath(row: 0, section: 0)
        ) as? SettingsTextSizeAdjustmentCell)
        let previewCell = try #require(viewController.tableView.dataSource?.tableView(
            viewController.tableView,
            cellForRowAt: IndexPath(row: 1, section: 0)
        ) as? SettingsTextSizePreviewCell)

        adjustmentCell.slider.value = 2
        adjustmentCell.slider.sendActions(for: .valueChanged)
        previewCell.configure(pointOffset: textSizeSettings.pointOffset)

        #expect(textSizeSettings.pointOffset == 2)
        #expect(previewCell.debugListTitleFont?.pointSize == 19)
        #expect(previewCell.debugCommentBodyFont?.pointSize == 19)
    }

    @Test func textSizePreviewCellRecalculatesFlexibleHeightForLargeFont() {
        let cell = SettingsTextSizePreviewCell(style: .default, reuseIdentifier: nil)
        cell.bounds = CGRect(x: 0, y: 0, width: 390, height: 1)
        cell.contentView.bounds = CGRect(x: 0, y: 0, width: 390, height: 1)

        cell.configure(pointOffset: 0)
        let standardHeight = cell.contentView.systemLayoutSizeFitting(
            CGSize(width: 390, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height

        cell.configure(pointOffset: AppTextSizeSettings.maximumPointOffset)
        let largeHeight = cell.contentView.systemLayoutSizeFitting(
            CGSize(width: 390, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height

        #expect(largeHeight > standardHeight)
        #expect(cell.debugCommentActionNumberOfLines == 0)
    }

    @Test func textSizeSettingsUsesExpandedAdjustmentRange() {
        #expect(AppTextSizeSettings.normalizedPointOffset(-100) == -4)
        #expect(AppTextSizeSettings.normalizedPointOffset(100) == 8)
        #expect(AppTextSizeSettings.displayText(for: 8) == "+8")
    }

    @Test func settingsPageShowsSpecialFollowCountAndPushesKeywordList() throws {
        let store = makeSpecialFollowStore()
        try store.save(keyword: "NodeImage")
        try store.save(keyword: "mist", colorHex: "#34C759")
        let viewController = SettingsViewController(
            cacheManager: FakeSettingsCacheManager(cacheByteSize: 0),
            sessionManager: FakeSettingsSessionManager(),
            nodeImageAPIKeyStore: FakeNodeImageAPIKeyStore(),
            specialFollowKeywordStore: store
        )
        let navigationController = UINavigationController(rootViewController: viewController)
        viewController.loadViewIfNeeded()

        let cell = try #require(viewController.tableView.dataSource?.tableView(
            viewController.tableView,
            cellForRowAt: IndexPath(row: 1, section: 1)
        ))
        #expect(cell.textLabel?.text == "特别关注")
        #expect(cell.detailTextLabel?.text == "帖子列表关键字高亮展示 · 2 个")
        #expect(cell.accessoryType == .disclosureIndicator)

        viewController.tableView.delegate?.tableView?(
            viewController.tableView,
            didSelectRowAt: IndexPath(row: 1, section: 1)
        )

        #expect(navigationController.topViewController is SpecialFollowKeywordsViewController)
    }

    @Test func selectingAutoCheckInPushesModuleSettingsScreen() throws {
        let viewController = SettingsViewController(
            cacheManager: FakeSettingsCacheManager(cacheByteSize: 0),
            sessionManager: FakeSettingsSessionManager(),
            nodeImageAPIKeyStore: FakeNodeImageAPIKeyStore()
        )
        let navigationController = UINavigationController(rootViewController: viewController)
        viewController.loadViewIfNeeded()

        viewController.tableView.delegate?.tableView?(
            viewController.tableView,
            didSelectRowAt: IndexPath(row: 2, section: 1)
        )

        #expect(navigationController.topViewController is AutoCheckInSettingsViewController)
    }

    @Test func returningToSettingsRefreshesAutoCheckInSummary() throws {
        let summary = AutoCheckInSummaryBox("未开启")
        let viewController = SettingsViewController(
            cacheManager: FakeSettingsCacheManager(cacheByteSize: 0),
            sessionManager: FakeSettingsSessionManager(),
            nodeImageAPIKeyStore: FakeNodeImageAPIKeyStore(),
            autoCheckInSummaryProvider: { summary.value }
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
        }
        viewController.loadViewIfNeeded()
        viewController.view.frame = window.bounds
        viewController.view.layoutIfNeeded()
        let indexPath = IndexPath(row: 2, section: 1)
        viewController.tableView.scrollToRow(at: indexPath, at: .middle, animated: false)
        viewController.tableView.layoutIfNeeded()

        let cell = try #require(viewController.tableView.cellForRow(at: indexPath))
        #expect(cell.detailTextLabel?.text == "Beta · 未开启")

        summary.value = "已开启 · 试试手气"
        #expect(cell.detailTextLabel?.text == "Beta · 未开启")
        viewController.viewWillAppear(false)
        viewController.tableView.layoutIfNeeded()
        let refreshedCell = try #require(viewController.tableView.cellForRow(at: indexPath))

        #expect(refreshedCell.detailTextLabel?.text == "Beta · 已开启 · 试试手气")
    }

    @Test func specialFollowKeywordListEditsAndDeletesKeywords() throws {
        let store = makeSpecialFollowStore()
        let viewController = SpecialFollowKeywordsViewController(store: store)
        viewController.loadViewIfNeeded()

        #expect(viewController.title == "特别关注")
        try viewController.saveKeywordForTesting(keyword: "NodeImage", colorHex: "#34C759")

        #expect(viewController.tableView.numberOfRows(inSection: 0) == 1)
        let cell = try #require(viewController.tableView.dataSource?.tableView(
            viewController.tableView,
            cellForRowAt: IndexPath(row: 0, section: 0)
        ))
        #expect(cell.textLabel?.text == "NodeImage")
        #expect(cell.detailTextLabel?.text == "#34C759")
        #expect(cell.imageView?.image?.renderingMode == .alwaysOriginal)
        let footerText = viewController.tableView.dataSource?.tableView?(
            viewController.tableView,
            titleForFooterInSection: 0
        )
        #expect(footerText?.contains("右滑删除") == true)

        try viewController.saveKeywordForTesting(keyword: "nodeimage", colorHex: "#007AFF")
        #expect(store.keywords == [
            SpecialFollowKeyword(keyword: "nodeimage", colorHex: "#007AFF")
        ])

        viewController.deleteKeywordForTesting(keyword: "nodeimage")
        #expect(store.keywords.isEmpty)
        #expect(viewController.tableView.numberOfRows(inSection: 0) == 0)
    }

    @Test func selectingClearCacheClearsCacheWithoutLoggingOut() async throws {
        let cacheManager = FakeSettingsCacheManager(cacheByteSize: 4_096)
        let sessionManager = FakeSettingsSessionManager()
        let viewController = SettingsViewController(
            cacheManager: cacheManager,
            sessionManager: sessionManager,
            nodeImageAPIKeyStore: FakeNodeImageAPIKeyStore(),
            confirmsActionsImmediately: true
        )
        viewController.loadViewIfNeeded()

        viewController.tableView.delegate?.tableView?(
            viewController.tableView,
            didSelectRowAt: IndexPath(row: 0, section: 2)
        )
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(cacheManager.clearCount == 1)
        #expect(sessionManager.logoutCount == 0)
    }

    @Test func selectingLogoutLogsOutAndRunsCallback() async throws {
        let cacheManager = FakeSettingsCacheManager(cacheByteSize: 4_096)
        let sessionManager = FakeSettingsSessionManager()
        let defaults = try #require(UserDefaults(suiteName: "settings-account-\(UUID().uuidString)"))
        let accountStore = CurrentAccountStore(userDefaults: defaults, storageKey: "account")
        await accountStore.save(AccountResponse(displayName: "mistj", isLoggedIn: true))
        var logoutCallbackCount = 0
        let viewController = SettingsViewController(
            cacheManager: cacheManager,
            sessionManager: sessionManager,
            currentAccountStore: accountStore,
            nodeImageAPIKeyStore: FakeNodeImageAPIKeyStore(),
            confirmsActionsImmediately: true,
            onLogout: {
                logoutCallbackCount += 1
            }
        )
        viewController.loadViewIfNeeded()
        try await waitUntil { viewController.tableView.numberOfRows(inSection: 5) == 1 }

        viewController.tableView.delegate?.tableView?(
            viewController.tableView,
            didSelectRowAt: IndexPath(row: 0, section: 5)
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
            nodeImageAPIKeyStore: FakeNodeImageAPIKeyStore(),
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
            didSelectRowAt: IndexPath(row: 1, section: 3)
        )
        viewController.tableView.delegate?.tableView?(
            viewController.tableView,
            didSelectRowAt: IndexPath(row: 2, section: 3)
        )

        #expect(logFileTapCount == 1)
        #expect(detailTestTapCount == 1)
    }

    @Test func selectingDetailTestKeepsSettingsOnNavigationStack() throws {
        var detailTestTapCount = 0
        let rootViewController = UIViewController()
        let viewController = SettingsViewController(
            cacheManager: FakeSettingsCacheManager(cacheByteSize: 0),
            sessionManager: FakeSettingsSessionManager(),
            nodeImageAPIKeyStore: FakeNodeImageAPIKeyStore(),
            onDetailTest: {
                detailTestTapCount += 1
            }
        )
        let navigationController = UINavigationController(rootViewController: rootViewController)
        navigationController.pushViewController(viewController, animated: false)
        viewController.loadViewIfNeeded()

        viewController.tableView.delegate?.tableView?(
            viewController.tableView,
            didSelectRowAt: IndexPath(row: 2, section: 3)
        )

        #expect(detailTestTapCount == 1)
        #expect(navigationController.viewControllers == [rootViewController, viewController])
    }

    @Test func selectingDebugLinksPushesDebugListFromSettings() throws {
        let viewController = SettingsViewController(
            cacheManager: FakeSettingsCacheManager(cacheByteSize: 0),
            sessionManager: FakeSettingsSessionManager(),
            nodeImageAPIKeyStore: FakeNodeImageAPIKeyStore()
        )
        let navigationController = UINavigationController(rootViewController: viewController)
        viewController.loadViewIfNeeded()

        viewController.tableView.delegate?.tableView?(
            viewController.tableView,
            didSelectRowAt: IndexPath(row: 3, section: 3)
        )

        #expect(navigationController.viewControllers.count == 2)
        #expect(navigationController.topViewController is PostDetailDebugLinksViewController)
    }

    @Test func detailDebugLinksListShowsFixedCasesAndReturnsSelectedTarget() throws {
        var selectedTarget: PostDetailTestTarget?
        let viewController = PostDetailDebugLinksViewController { target, _ in
            selectedTarget = target
        }
        viewController.loadViewIfNeeded()

        #expect(viewController.title == "调试链接")
        #expect(viewController.tableView.numberOfRows(inSection: 0) == 2)

        let quoteCell = try #require(viewController.tableView.dataSource?.tableView(
            viewController.tableView,
            cellForRowAt: IndexPath(row: 0, section: 0)
        ))
        let svgCell = try #require(viewController.tableView.dataSource?.tableView(
            viewController.tableView,
            cellForRowAt: IndexPath(row: 1, section: 0)
        ))

        #expect(quoteCell.textLabel?.text == "qute嵌套")
        #expect(quoteCell.detailTextLabel?.text == "https://www.nodeseek.com/post-720543-1")
        #expect(svgCell.textLabel?.text == "svg兼容问题")
        #expect(svgCell.detailTextLabel?.text == "https://www.nodeseek.com/post-720369-1")

        viewController.tableView.delegate?.tableView?(
            viewController.tableView,
            didSelectRowAt: IndexPath(row: 1, section: 0)
        )

        #expect(selectedTarget?.post.id == "720369")
        #expect(selectedTarget?.page == 1)
    }

    @Test func togglingFileLoggingSwitchUpdatesRuntimeConfig() async throws {
        try await withFileLoggingConfigIsolation {
            NodeSeekDebugConfig.enableFileLogging = false
            let viewController = SettingsViewController(
                cacheManager: FakeSettingsCacheManager(cacheByteSize: 0),
                sessionManager: FakeSettingsSessionManager(),
                nodeImageAPIKeyStore: FakeNodeImageAPIKeyStore()
            )
            viewController.loadViewIfNeeded()

            let cell = try #require(viewController.tableView.dataSource?.tableView(
                viewController.tableView,
                cellForRowAt: IndexPath(row: 0, section: 3)
            ))
            let loggingSwitch = try #require(cell.accessoryView as? UISwitch)
            loggingSwitch.isOn = true
            loggingSwitch.sendActions(for: .valueChanged)

            #expect(NodeSeekDebugConfig.enableFileLogging == true)
        }
    }

    @Test func nodeImageCellShowsCancelAuthorizationWhenAPIKeyExists() throws {
        let nodeImageAPIKeyStore = FakeNodeImageAPIKeyStore()
        nodeImageAPIKeyStore.save(apiKey: "nodeimage-key")
        let viewController = SettingsViewController(
            cacheManager: FakeSettingsCacheManager(cacheByteSize: 0),
            sessionManager: FakeSettingsSessionManager(),
            nodeImageAPIKeyStore: nodeImageAPIKeyStore
        )
        viewController.loadViewIfNeeded()

        let cell = try #require(viewController.tableView.dataSource?.tableView(
            viewController.tableView,
            cellForRowAt: IndexPath(row: 0, section: 1)
        ))

        #expect(cell.textLabel?.text == "取消 NodeImage 授权")
        #expect(cell.textLabel?.textColor == .systemRed)
        #expect(cell.accessoryType == .none)
    }

    @Test func selectingNodeImageAuthorizationStoresAPIKeyAndRefreshesCell() throws {
        let nodeImageAPIKeyStore = FakeNodeImageAPIKeyStore()
        let authorizationPresenter = FakeNodeImageAuthorizationPresenter(apiKeyToReturn: "new-nodeimage-key")
        let viewController = SettingsViewController(
            cacheManager: FakeSettingsCacheManager(cacheByteSize: 0),
            sessionManager: FakeSettingsSessionManager(),
            nodeImageAPIKeyStore: nodeImageAPIKeyStore,
            nodeImageAuthorizationPresenter: authorizationPresenter,
            confirmsActionsImmediately: true
        )
        viewController.loadViewIfNeeded()

        viewController.tableView.delegate?.tableView?(
            viewController.tableView,
            didSelectRowAt: IndexPath(row: 0, section: 1)
        )

        #expect(authorizationPresenter.presentCount == 1)
        #expect(nodeImageAPIKeyStore.apiKey() == "new-nodeimage-key")
        let cell = try #require(viewController.tableView.dataSource?.tableView(
            viewController.tableView,
            cellForRowAt: IndexPath(row: 0, section: 1)
        ))
        #expect(cell.textLabel?.text == "取消 NodeImage 授权")
    }

    @Test func selectingNodeImageAuthorizationDoesNotShowSuccessAlertAfterSavingAPIKey() throws {
        let nodeImageAPIKeyStore = FakeNodeImageAPIKeyStore()
        let authorizationPresenter = FakeNodeImageAuthorizationPresenter(apiKeyToReturn: "new-nodeimage-key")
        let viewController = SettingsViewController(
            cacheManager: FakeSettingsCacheManager(cacheByteSize: 0),
            sessionManager: FakeSettingsSessionManager(),
            nodeImageAPIKeyStore: nodeImageAPIKeyStore,
            nodeImageAuthorizationPresenter: authorizationPresenter
        )
        viewController.loadViewIfNeeded()

        viewController.tableView.delegate?.tableView?(
            viewController.tableView,
            didSelectRowAt: IndexPath(row: 0, section: 1)
        )

        #expect(nodeImageAPIKeyStore.apiKey() == "new-nodeimage-key")
        #expect(viewController.presentedViewController == nil)
    }

    @Test func selectingCancelNodeImageAuthorizationClearsAPIKeyAndRefreshesCell() throws {
        let nodeImageAPIKeyStore = FakeNodeImageAPIKeyStore()
        nodeImageAPIKeyStore.save(apiKey: "nodeimage-key")
        let viewController = SettingsViewController(
            cacheManager: FakeSettingsCacheManager(cacheByteSize: 0),
            sessionManager: FakeSettingsSessionManager(),
            nodeImageAPIKeyStore: nodeImageAPIKeyStore,
            confirmsActionsImmediately: true
        )
        viewController.loadViewIfNeeded()

        viewController.tableView.delegate?.tableView?(
            viewController.tableView,
            didSelectRowAt: IndexPath(row: 0, section: 1)
        )

        #expect(nodeImageAPIKeyStore.clearCount == 1)
        #expect(nodeImageAPIKeyStore.apiKey() == nil)
        let cell = try #require(viewController.tableView.dataSource?.tableView(
            viewController.tableView,
            cellForRowAt: IndexPath(row: 0, section: 1)
        ))
        #expect(cell.textLabel?.text == "NodeImage 授权")
    }

    @Test func defaultSessionLogoutClearsNodeImageAuthorization() async throws {
        let nodeImageAPIKeyStore = FakeNodeImageAPIKeyStore()
        nodeImageAPIKeyStore.save(apiKey: "nodeimage-key")
        let defaults = try #require(UserDefaults(suiteName: "settings-session-\(UUID().uuidString)"))
        let accountStore = CurrentAccountStore(userDefaults: defaults, storageKey: "account")
        let cookieStorage = try #require(URLSessionConfiguration.ephemeral.httpCookieStorage)
        let manager = DefaultSettingsSessionManager(
            cookieBridge: CookieBridge(
                webCookieStore: FakeWebCookieStore(),
                urlCookieStorage: cookieStorage,
                allowedDomains: []
            ),
            currentAccountStore: accountStore,
            nodeImageAPIKeyStore: nodeImageAPIKeyStore
        )

        await manager.logout()

        #expect(nodeImageAPIKeyStore.clearCount == 1)
        #expect(nodeImageAPIKeyStore.apiKey() == nil)
    }
}

private extension SettingsBuildInfo {
    static let testFlightFixture = SettingsBuildInfo(
        appVersion: "1.0.1",
        buildNumber: "42",
        gitSHA: "abcdef1234567890",
        workflowName: "TestFlight",
        githubRunID: "25443881348",
        githubRunURL: URL(string: "https://github.com/tyrad/nodeseek/actions/runs/25443881348")
    )
}

private func makeSpecialFollowStore() -> SpecialFollowKeywordStore {
    let suiteName = "settings-special-follow-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return SpecialFollowKeywordStore(userDefaults: defaults, storageKey: "keywords")
}

@MainActor
private func withFileLoggingConfigIsolation(_ body: () async throws -> Void) async throws {
    try await FileLoggingTestGate.shared.withExclusiveAccess {
        let previousFileLogging = NodeSeekDebugConfig.enableFileLogging
        let previousAvatarLogging = NodeSeekDebugConfig.enableAvatarImageLogs
        defer {
            NodeSeekDebugConfig.enableFileLogging = previousFileLogging
            NodeSeekDebugConfig.enableAvatarImageLogs = previousAvatarLogging
        }
        try await body()
    }
}

@MainActor
private final class AutoCheckInSummaryBox {
    var value: String

    init(_ value: String) {
        self.value = value
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

private final class FakeNodeImageAPIKeyStore: NodeImageAPIKeyStoring {
    private(set) var clearCount = 0
    private var storedAPIKey: String?

    func apiKey() -> String? {
        storedAPIKey
    }

    func save(apiKey: String) {
        storedAPIKey = apiKey
    }

    func clear() {
        clearCount += 1
        storedAPIKey = nil
    }
}

@MainActor
private final class FakeNodeImageAuthorizationPresenter: NodeImageAuthorizationPresenting {
    private(set) var presentCount = 0
    private let apiKeyToReturn: String

    init(apiKeyToReturn: String) {
        self.apiKeyToReturn = apiKeyToReturn
    }

    func presentAuthorization(
        from presentingViewController: UIViewController,
        onAPIKey: @escaping @MainActor (String) -> Void
    ) {
        presentCount += 1
        onAPIKey(apiKeyToReturn)
    }
}

@MainActor
private final class FakeWebCookieStore: WebCookieStore {
    func allCookies() async -> [HTTPCookie] {
        []
    }

    func setCookie(_ cookie: HTTPCookie) async {}

    func deleteCookie(_ cookie: HTTPCookie) async {}
}

@MainActor
private func waitUntil(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    condition: @escaping @MainActor () -> Bool
) async throws {
    let step: UInt64 = 25_000_000
    var waited: UInt64 = 0
    while waited < timeoutNanoseconds {
        if condition() {
            return
        }
        try await Task.sleep(nanoseconds: step)
        waited += step
    }
}
