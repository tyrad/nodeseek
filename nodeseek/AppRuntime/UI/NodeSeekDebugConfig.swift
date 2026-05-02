//
//  NodeSeekDebugConfig.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import UIKit

struct NodeSeekDebugConfig {
    private nonisolated static let storage = NodeSeekDebugConfigStorage(
        fileLoggingEnabled: false,
        avatarImageLoggingEnabled: false
    )

    #if DEBUG
    static let enablePostDetailTestEntry = true
    static let enableWebViewDebugOverlay = false
    static let enableDetailRenderDiagnostics = false
    #else
    static let enablePostDetailTestEntry = false
    static let enableWebViewDebugOverlay = false
    static let enableDetailRenderDiagnostics = false
    #endif

    nonisolated static var enableFileLogging: Bool {
        get { storage.fileLoggingEnabled }
        set { storage.fileLoggingEnabled = newValue }
    }
    nonisolated static var enableAvatarImageLogs: Bool {
        get { storage.avatarImageLoggingEnabled }
        set { storage.avatarImageLoggingEnabled = newValue }
    }

    #if DEBUG
    nonisolated static func resetRuntimeLoggingForTesting() {
        storage.fileLoggingEnabled = false
        storage.avatarImageLoggingEnabled = false
    }
    #endif

    static let webViewDebugOverlaySize = CGSize(width: 180, height: 120)
    static let webViewDebugOverlayBottomInset: CGFloat = 8
    static let webViewDebugOverlayLeadingInset: CGFloat = 8
}

private final class NodeSeekDebugConfigStorage: @unchecked Sendable {
    private let lock = NSLock()
    // 只允许通过下方属性访问，NSLock 负责同步测试和后台日志线程。
    nonisolated(unsafe) private var _fileLoggingEnabled: Bool
    nonisolated(unsafe) private var _avatarImageLoggingEnabled: Bool

    init(fileLoggingEnabled: Bool, avatarImageLoggingEnabled: Bool) {
        _fileLoggingEnabled = fileLoggingEnabled
        _avatarImageLoggingEnabled = avatarImageLoggingEnabled
    }

    nonisolated var fileLoggingEnabled: Bool {
        get {
            withLock { _fileLoggingEnabled }
        }
        set {
            withLock { _fileLoggingEnabled = newValue }
        }
    }

    nonisolated var avatarImageLoggingEnabled: Bool {
        get {
            withLock { _avatarImageLoggingEnabled }
        }
        set {
            withLock { _avatarImageLoggingEnabled = newValue }
        }
    }

    nonisolated private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
