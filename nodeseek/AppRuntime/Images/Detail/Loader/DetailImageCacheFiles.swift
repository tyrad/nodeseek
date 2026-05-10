//
//  DetailImageCacheFiles.swift
//  nodeseek
//
//  Created by Codex on 2026/5/10.
//

import CryptoKit
import Foundation

struct DetailImageCacheFiles {
    let cacheDirectory: URL

    var thumbnailCacheDirectory: URL {
        cacheDirectory.appendingPathComponent("thumbnails", isDirectory: true)
    }

    func clearThumbnails() throws {
        guard FileManager.default.fileExists(atPath: thumbnailCacheDirectory.path) else { return }
        try FileManager.default.removeItem(at: thumbnailCacheDirectory)
    }

    func thumbnailByteSize() -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: thumbnailCacheDirectory,
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

    func thumbnailCacheURL(for imageURL: URL) -> URL {
        thumbnailCacheDirectory.appendingPathComponent("\(cacheKey(for: imageURL)).jpg", isDirectory: false)
    }

    func writeData(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: [.atomic])
    }

    private func cacheKey(for imageURL: URL) -> String {
        let data = Data(imageURL.absoluteString.utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
