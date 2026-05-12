//
//  StickerAspectRatioCache.swift
//  nodeseek
//
//  Created by Codex on 2026/5/12.
//

import CoreGraphics
import Foundation

protocol StickerAspectRatioProviding: AnyObject {
    func cachedSourceSize(for url: URL) -> CGSize?
    func recordLoadedSize(_ imageSize: CGSize, for url: URL)
}

final class StickerAspectRatioCache: StickerAspectRatioProviding, @unchecked Sendable {
    static let shared = StickerAspectRatioCache()

    private struct Entry: Codable {
        let ratio: Double
        let updatedAt: Date
    }

    private enum Limits {
        static let minRatio: CGFloat = 0.25
        static let maxRatio: CGFloat = 4
        static let unchangedTolerance: CGFloat = 0.001
        static let maxEntries = 2_000
        static let maxDirtyBeforeFlush = 100
        static let writeDelay: TimeInterval = 120
    }

    private let storageURL: URL?
    private let maxEntries: Int
    private let maxDirtyBeforeFlush: Int
    private let writeDelay: TimeInterval
    private let lock = NSLock()
    private let writeQueue = DispatchQueue(label: "com.mistj.nodeseek.sticker-aspect-ratio-cache", qos: .utility)

    private var entries: [String: Entry]
    private var dirtyCount = 0
    private var pendingWriteWorkItem: DispatchWorkItem?

    init(
        storageURL: URL? = StickerAspectRatioCache.defaultStorageURL(),
        maxEntries: Int = Limits.maxEntries,
        maxDirtyBeforeFlush: Int = Limits.maxDirtyBeforeFlush,
        writeDelay: TimeInterval = Limits.writeDelay
    ) {
        self.storageURL = storageURL
        self.maxEntries = maxEntries
        self.maxDirtyBeforeFlush = maxDirtyBeforeFlush
        self.writeDelay = writeDelay
        self.entries = storageURL.flatMap(Self.loadEntries(from:)) ?? [:]
    }

    func cachedSourceSize(for url: URL) -> CGSize? {
        let key = Self.normalizedKey(for: url)
        guard let ratio = lock.nsLocked({ entries[key].map { CGFloat($0.ratio) } }),
              Self.isValid(ratio) else {
            return nil
        }
        return CGSize(width: ratio, height: 1)
    }

    func recordLoadedSize(_ imageSize: CGSize, for url: URL) {
        guard imageSize.width > 0,
              imageSize.height > 0 else {
            return
        }

        let ratio = imageSize.width / imageSize.height
        guard Self.isValid(ratio) else { return }

        let key = Self.normalizedKey(for: url)
        let shouldFlushNow = lock.nsLocked {
            if let oldRatio = entries[key].map({ CGFloat($0.ratio) }),
               abs(oldRatio - ratio) < Limits.unchangedTolerance {
                return false
            }

            entries[key] = Entry(ratio: Double(ratio), updatedAt: Date())
            trimEntriesIfNeeded()
            guard storageURL != nil else { return false }

            dirtyCount += 1

            if dirtyCount >= maxDirtyBeforeFlush {
                pendingWriteWorkItem?.cancel()
                pendingWriteWorkItem = nil
                return true
            }

            scheduleLazyWriteLocked()
            return false
        }

        if shouldFlushNow {
            writeQueue.async { [weak self] in
                self?.flushToDisk()
            }
        }
    }

    func flush() {
        lock.nsLocked {
            pendingWriteWorkItem?.cancel()
            pendingWriteWorkItem = nil
        }
        writeQueue.async { [weak self] in
            self?.flushToDisk()
        }
    }

    private func scheduleLazyWriteLocked() {
        guard storageURL != nil else { return }

        pendingWriteWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.flushToDisk()
        }
        pendingWriteWorkItem = workItem
        writeQueue.asyncAfter(deadline: .now() + writeDelay, execute: workItem)
    }

    private func flushToDisk() {
        let snapshot: [String: Entry]? = lock.nsLocked {
            guard dirtyCount > 0 else { return nil }
            dirtyCount = 0
            pendingWriteWorkItem = nil
            return entries
        }
        guard let storageURL, let snapshot else { return }

        do {
            let data = try JSONEncoder().encode(snapshot)
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: storageURL, options: .atomic)
        } catch {
            lock.nsLocked {
                dirtyCount += snapshot.count
                scheduleLazyWriteLocked()
            }
        }
    }

    private func trimEntriesIfNeeded() {
        guard entries.count > maxEntries else { return }

        let overflow = entries.count - maxEntries
        let keysToRemove = entries
            .sorted { $0.value.updatedAt < $1.value.updatedAt }
            .prefix(overflow)
            .map(\.key)
        keysToRemove.forEach { entries.removeValue(forKey: $0) }
    }

    private static func isValid(_ ratio: CGFloat) -> Bool {
        ratio.isFinite && ratio >= Limits.minRatio && ratio <= Limits.maxRatio
    }

    private static func normalizedKey(for url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.query = nil
        components.fragment = nil
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        return components.url?.absoluteString ?? url.absoluteString
    }

    private static func defaultStorageURL() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("sticker-aspect-ratios.json", isDirectory: false)
    }

    private static func loadEntries(from url: URL) -> [String: Entry] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else {
            return [:]
        }
        return decoded.filter { Self.isValid(CGFloat($0.value.ratio)) }
    }
}

private extension NSLock {
    func nsLocked<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
