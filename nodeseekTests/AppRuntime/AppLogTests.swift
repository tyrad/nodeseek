//
//  AppLogTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/5/2.
//

import Foundation
import Testing
import UIKit
@testable import nodeseek

@MainActor
@Suite(.serialized)
struct AppLogTests {
    @Test func fileLoggingDefaultsToDisabled() {
        NodeSeekDebugConfig.resetRuntimeLoggingForTesting()

        #expect(NodeSeekDebugConfig.enableFileLogging == false)
    }

    @Test func fileLoggingWritesOnlyWhenDebugSwitchIsEnabled() async throws {
        try withTemporaryFileLogging { directory in
            NodeSeekDebugConfig.enableFileLogging = false
            AppLog.info(.service, "disabled message")
            AppLog.flushFileLogsForTesting()
            #expect(FileManager.default.fileExists(atPath: logURL(in: directory).path) == false)

            NodeSeekDebugConfig.enableFileLogging = true
            AppLog.warning(.webView, "enabled message")
            AppLog.flushFileLogsForTesting()

            let content = try String(contentsOf: logURL(in: directory), encoding: .utf8)
            #expect(content.contains("[warning] [WebView] ["))
            #expect(content.contains("enabled message"))
            #expect(content.contains("disabled message") == false)
        }
    }

    @Test func readsCurrentFileLogContent() async throws {
        try withTemporaryFileLogging { _ in
            AppLog.info(.postDetail, "detail log message")
            AppLog.flushFileLogsForTesting()

            let content = try AppLog.fileLogContent()

            #expect(AppLog.fileLogURL.lastPathComponent == "nodeseek.log")
            #expect(content.contains("[info] [PostDetail] ["))
            #expect(content.contains("detail log message"))
        }
    }

    @Test func deleteFileLogRemovesCurrentLogFile() async throws {
        try withTemporaryFileLogging { _ in
            AppLog.info(.service, "log before delete")
            AppLog.flushFileLogsForTesting()

            try AppLog.deleteFileLog()

            #expect(FileManager.default.fileExists(atPath: AppLog.fileLogURL.path) == false)
            #expect(try AppLog.fileLogContent() == "")
        }
    }

    @Test func avatarImageLogsAreSkippedWhenDebugSwitchIsDisabled() async throws {
        try withTemporaryFileLogging(avatarImageLogs: false) { _ in
            AvatarImageLoader(cookieBridge: CookieBridge()).loadAvatar(
                into: UIImageView(),
                postID: "avatar-log-test",
                avatarURL: nil
            )
            AppLog.flushFileLogsForTesting()

            let content = try AppLog.fileLogContent()
            #expect(content.contains("头像URL缺失或非法") == false)
        }
    }

    private func withTemporaryFileLogging(
        avatarImageLogs: Bool? = nil,
        _ body: (URL) throws -> Void
    ) throws {
        let previousFileLoggingEnabled = NodeSeekDebugConfig.enableFileLogging
        let previousAvatarLoggingEnabled = NodeSeekDebugConfig.enableAvatarImageLogs
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
            NodeSeekDebugConfig.enableFileLogging = previousFileLoggingEnabled
            NodeSeekDebugConfig.enableAvatarImageLogs = previousAvatarLoggingEnabled
            AppLog.setFileLogDirectoryForTesting(nil)
        }

        AppLog.setFileLogDirectoryForTesting(directory)
        NodeSeekDebugConfig.enableFileLogging = true
        if let avatarImageLogs {
            NodeSeekDebugConfig.enableAvatarImageLogs = avatarImageLogs
        }

        try body(directory)
    }

    private func logURL(in directory: URL) -> URL {
        directory.appendingPathComponent("nodeseek.log")
    }
}
