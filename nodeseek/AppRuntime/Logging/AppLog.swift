//
//  AppLog.swift
//  nodeseek
//
//  Created by Codex on 2026/5/2.
//

import Foundation
import OSLog

enum AppLogType: String, CaseIterable {
    case service = "Service"
    case webView = "WebView"
    case postList = "PostList"
    case postDetail = "PostDetail"
    case image = "Image"
    case rendering = "Rendering"
    case account = "Account"
}

enum AppLogLevel: String {
    case debug
    case info
    case notice
    case warning
    case error
}

enum AppLog {
    nonisolated static let accountDebugMessageKey = "message"
    nonisolated private static let subsystem = "com.nodeseek.app"
    nonisolated private static let fileWriter = AppLogFileWriter()
    nonisolated private static let loggers: [AppLogType: Logger] = Dictionary(
        uniqueKeysWithValues: AppLogType.allCases.map { type in
            (type, Logger(subsystem: subsystem, category: type.rawValue))
        }
    )

    nonisolated static func debug(_ type: AppLogType, _ message: @autoclosure () -> String) {
        write(.debug, type, message())
    }

    nonisolated static func info(_ type: AppLogType, _ message: @autoclosure () -> String) {
        write(.info, type, message())
    }

    nonisolated static func notice(_ type: AppLogType, _ message: @autoclosure () -> String) {
        write(.notice, type, message())
    }

    nonisolated static func warning(_ type: AppLogType, _ message: @autoclosure () -> String) {
        write(.warning, type, message())
    }

    nonisolated static func error(_ type: AppLogType, _ message: @autoclosure () -> String) {
        write(.error, type, message())
    }

    nonisolated static func debugPanel(_ type: AppLogType, _ message: @autoclosure () -> String) {
        let value = message()
        write(.debug, type, value)
        #if DEBUG
        NotificationCenter.default.post(
            name: .nodeSeekCurrentAccountDebugMessage,
            object: nil,
            userInfo: [accountDebugMessageKey: value]
        )
        #endif
    }

    nonisolated static var fileLogURL: URL {
        fileWriter.logURL()
    }

    nonisolated static func fileLogContent() throws -> String {
        try fileWriter.readContent()
    }

    #if DEBUG
    nonisolated static func setFileLogDirectoryForTesting(_ directory: URL?) {
        fileWriter.setDirectoryOverride(directory)
    }

    nonisolated static func flushFileLogsForTesting() {
        fileWriter.flush()
    }
    #endif

    nonisolated private static func write(_ level: AppLogLevel, _ type: AppLogType, _ message: String) {
        let logger = loggers[type] ?? Logger(subsystem: subsystem, category: type.rawValue)
        switch level {
        case .debug:
            logger.debug("\(message, privacy: .public)")
        case .info:
            logger.info("\(message, privacy: .public)")
        case .notice:
            logger.notice("\(message, privacy: .public)")
        case .warning:
            logger.warning("\(message, privacy: .public)")
        case .error:
            logger.error("\(message, privacy: .public)")
        }
        fileWriter.write(level: level, type: type, message: message)
    }
}

private final class AppLogFileWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.nodeseek.app.log.file")
    nonisolated(unsafe) private var directoryOverride: URL?

    nonisolated func write(level: AppLogLevel, type: AppLogType, message: String) {
        #if DEBUG
        guard NodeSeekDebugConfig.enableFileLogging else { return }
        queue.async { [directoryOverride] in
            let directory = directoryOverride ?? Self.defaultDirectory()
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let line = "\(Self.timestamp()) [\(level.rawValue)] [\(type.rawValue)] \(message)\n"
                let logURL = directory.appendingPathComponent("nodeseek.log")
                let data = Data(line.utf8)
                if FileManager.default.fileExists(atPath: logURL.path) {
                    let handle = try FileHandle(forWritingTo: logURL)
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                } else {
                    try data.write(to: logURL, options: .atomic)
                }
            } catch {
                Logger(subsystem: "com.nodeseek.app", category: "Logging")
                    .error("文件日志写入失败: \(error.localizedDescription, privacy: .public)")
            }
        }
        #endif
    }

    nonisolated func logURL() -> URL {
        queue.sync {
            Self.logURL(in: directoryOverride ?? Self.defaultDirectory())
        }
    }

    nonisolated func readContent() throws -> String {
        queue.sync {
            let logURL = Self.logURL(in: directoryOverride ?? Self.defaultDirectory())
            guard FileManager.default.fileExists(atPath: logURL.path) else {
                return ""
            }
            return (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        }
    }

    #if DEBUG
    nonisolated func setDirectoryOverride(_ directory: URL?) {
        queue.sync {
            directoryOverride = directory
        }
    }

    nonisolated func flush() {
        queue.sync {}
    }
    #endif

    nonisolated private static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
    }

    nonisolated private static func logURL(in directory: URL) -> URL {
        directory.appendingPathComponent("nodeseek.log")
    }

    nonisolated private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

extension Notification.Name {
    nonisolated static let nodeSeekCurrentAccountDebugMessage = Notification.Name("nodeSeekCurrentAccountDebugMessage")
}
