//
//  AppLogTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/5/2.
//

import Foundation
import Testing
@testable import nodeseek

@MainActor
struct AppLogTests {
    @Test func debugPanelPostsAccountMessageNotification() async throws {
        var receivedMessage: String?
        let observer = NotificationCenter.default.addObserver(
            forName: .nodeSeekCurrentAccountDebugMessage,
            object: nil,
            queue: .main
        ) { notification in
            receivedMessage = notification.userInfo?[AppLog.accountDebugMessageKey] as? String
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        AppLog.debugPanel(.account, "account refresh started")
        try await Task.sleep(nanoseconds: 20_000_000)

        #expect(receivedMessage == "account refresh started")
    }

    @Test func fileLoggingWritesOnlyWhenDebugSwitchIsEnabled() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
            NodeSeekDebugConfig.enableFileLogging = false
            AppLog.setFileLogDirectoryForTesting(nil)
        }

        AppLog.setFileLogDirectoryForTesting(directory)
        NodeSeekDebugConfig.enableFileLogging = false
        AppLog.info(.service, "disabled message")
        AppLog.flushFileLogsForTesting()
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("nodeseek.log").path) == false)

        NodeSeekDebugConfig.enableFileLogging = true
        AppLog.warning(.webView, "enabled message")
        AppLog.flushFileLogsForTesting()

        let logURL = directory.appendingPathComponent("nodeseek.log")
        let content = try String(contentsOf: logURL, encoding: .utf8)
        #expect(content.contains("[warning] [WebView] enabled message"))
        #expect(content.contains("disabled message") == false)
    }

    @Test func readsCurrentFileLogContent() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
            NodeSeekDebugConfig.enableFileLogging = false
            AppLog.setFileLogDirectoryForTesting(nil)
        }

        AppLog.setFileLogDirectoryForTesting(directory)
        NodeSeekDebugConfig.enableFileLogging = true
        AppLog.info(.postDetail, "detail log message")
        AppLog.flushFileLogsForTesting()

        let content = try AppLog.fileLogContent()

        #expect(AppLog.fileLogURL.lastPathComponent == "nodeseek.log")
        #expect(content.contains("[info] [PostDetail] detail log message"))
    }
}
