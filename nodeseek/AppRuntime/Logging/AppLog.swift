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
    nonisolated private static let subsystem = "com.nodeseek.app"
    nonisolated private static let fileWriter = AppLogFileWriter()
    nonisolated private static let loggers: [AppLogType: Logger] = Dictionary(
        uniqueKeysWithValues: AppLogType.allCases.map { type in
            (type, Logger(subsystem: subsystem, category: type.rawValue))
        }
    )

    nonisolated static func debug(_ type: AppLogType, _ message: @autoclosure () -> String) {
        log(.debug, type, message())
    }

    nonisolated static func info(_ type: AppLogType, _ message: @autoclosure () -> String) {
        log(.info, type, message())
    }

    nonisolated static func notice(_ type: AppLogType, _ message: @autoclosure () -> String) {
        log(.notice, type, message())
    }

    nonisolated static func warning(_ type: AppLogType, _ message: @autoclosure () -> String) {
        log(.warning, type, message())
    }

    nonisolated static func error(_ type: AppLogType, _ message: @autoclosure () -> String) {
        log(.error, type, message())
    }

    nonisolated static func log(_ level: AppLogLevel, _ type: AppLogType, _ message: @autoclosure () -> String) {
        write(level, type, message())
    }

    nonisolated static var fileLogURL: URL {
        fileWriter.logURL()
    }

    nonisolated static func fileLogContent() throws -> String {
        try fileWriter.readContent()
    }

    nonisolated static func deleteFileLog() throws {
        try fileWriter.deleteLogFile()
    }

    nonisolated static func elapsedMilliseconds(since startDate: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(startDate) * 1_000))
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
        let stampedMessage = "\(messageTimestamp()) \(message)"
        let logger = loggers[type] ?? Logger(subsystem: subsystem, category: type.rawValue)
        switch level {
        case .debug:
            logger.debug("\(stampedMessage, privacy: .public)")
        case .info:
            logger.info("\(stampedMessage, privacy: .public)")
        case .notice:
            logger.notice("\(stampedMessage, privacy: .public)")
        case .warning:
            logger.warning("\(stampedMessage, privacy: .public)")
        case .error:
            logger.error("\(stampedMessage, privacy: .public)")
        }
        fileWriter.write(level: level, type: type, message: stampedMessage)
    }

    nonisolated private static func messageTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS ZZZZZ"
        return "[\(formatter.string(from: Date()))]"
    }
}

private final class AppLogFileWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.nodeseek.app.log.file")
    nonisolated(unsafe) private var directoryOverride: URL?

    nonisolated func write(level: AppLogLevel, type: AppLogType, message: String) {
        guard NodeSeekDebugConfig.enableFileLogging else { return }
        queue.async {
            let directory = self.directoryOverride ?? Self.defaultDirectory()
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let line = "\(Self.timestamp()) [\(level.rawValue)] [\(type.rawValue)] \(message)\n"
                let logURL = directory.appendingPathComponent("nodeseek.log")
                let data = Data(line.utf8)
                if FileManager.default.fileExists(atPath: logURL.path) {
                    let handle = try FileHandle(forWritingTo: logURL)
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                } else {
                    try data.write(to: logURL, options: .atomic)
                }
            } catch {
                Logger(subsystem: "com.nodeseek.app", category: "Logging")
                    .error("文件日志写入失败: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    nonisolated func logURL() -> URL {
        queue.sync {
            Self.logURL(in: directoryOverride ?? Self.defaultDirectory())
        }
    }

    nonisolated func readContent() throws -> String {
        try queue.sync {
            let logURL = Self.logURL(in: directoryOverride ?? Self.defaultDirectory())
            guard FileManager.default.fileExists(atPath: logURL.path) else {
                return ""
            }
            return try String(contentsOf: logURL, encoding: .utf8)
        }
    }

    nonisolated func deleteLogFile() throws {
        try queue.sync {
            let logURL = Self.logURL(in: directoryOverride ?? Self.defaultDirectory())
            guard FileManager.default.fileExists(atPath: logURL.path) else { return }
            try FileManager.default.removeItem(at: logURL)
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
