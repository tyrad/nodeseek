//
//  ImageDiskCache.swift
//  nodeseek
//
//  Created by Codex on 2026/5/9.
//

import CryptoKit
import Foundation

final class ImageDiskCache {
    private let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    func data(for url: URL) -> Data? {
        try? Data(contentsOf: cacheURL(for: url))
    }

    func store(_ data: Data, for url: URL) throws {
        let fileURL = cacheURL(for: url)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: [.atomic])
    }

    func byteSize() -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
            total += values?.fileSize ?? 0
        }
        return total
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    func cacheURL(for url: URL) -> URL {
        directory.appendingPathComponent(cacheKey(for: url), isDirectory: false)
    }

    private func cacheKey(for url: URL) -> String {
        let data = Data(url.absoluteString.utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
