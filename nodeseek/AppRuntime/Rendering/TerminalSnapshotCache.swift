import Foundation
import ImageIO
import UIKit

nonisolated struct TerminalSnapshot: Codable, Sendable {
    struct Page: Codable, Sendable {
        let url: URL
        let width: Double
        let height: Double
    }
    let pages: [Page]
    let text: String
}

// 编码和磁盘访问在独立 actor 上进行，WebView 与 UIKit 展示仍归主线程。
actor TerminalSnapshotCache {
    static let shared = TerminalSnapshotCache()
    private let root: URL

    init(root: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("TerminalSnapshots-v1", isDirectory: true)) {
        self.root = root
    }

    func load(key: String) -> TerminalSnapshot? {
        let directory = root.appendingPathComponent(key, isDirectory: true)
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("manifest.json")),
              let snapshot = try? JSONDecoder().decode(TerminalSnapshot.self, from: data),
              !snapshot.pages.isEmpty else { return nil }
        // 重装/备份恢复后沙盒绝对路径可能变化，按文件名重建。
        let pages = snapshot.pages.map { page in
            TerminalSnapshot.Page(url: directory.appendingPathComponent(page.url.lastPathComponent), width: page.width, height: page.height)
        }
        guard pages.allSatisfy({ FileManager.default.fileExists(atPath: $0.url.path) }) else { return nil }
        return .init(pages: pages, text: snapshot.text)
    }

    func save(image: UIImage, key: String, index: Int) throws -> TerminalSnapshot.Page {
        let directory = root.appendingPathComponent(key, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = image.pngData(), let cgImage = image.cgImage else { throw CocoaError(.fileWriteUnknown) }
        let url = directory.appendingPathComponent("\(index).png")
        try data.write(to: url, options: .atomic)
        return .init(url: url, width: Double(cgImage.width), height: Double(cgImage.height))
    }

    func finish(_ snapshot: TerminalSnapshot, key: String) throws -> TerminalSnapshot {
        let directory = root.appendingPathComponent(key, isDirectory: true)
        let merged = try merge(snapshot.pages, in: directory)
        let result = TerminalSnapshot(pages: [merged], text: snapshot.text)
        try Task.checkCancellation()
        try JSONEncoder().encode(result).write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
        for page in snapshot.pages where page.url != merged.url {
            try? FileManager.default.removeItem(at: page.url)
        }
        prune(excluding: directory)
        return result
    }

    private func merge(_ pages: [TerminalSnapshot.Page], in directory: URL) throws -> TerminalSnapshot.Page {
        guard let first = pages.first, first.width > 0,
              pages.allSatisfy({ $0.width == first.width && $0.height > 0 }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if pages.count == 1 { return first }
        let sourceHeight = pages.reduce(0) { $0 + $1.height }
        // 常规报告保留原分辨率；极长报告等比例缩小，控制合成内存并兼容既有大图尺寸上限。
        let scale = min(1, sqrt(16_000_000 / (first.width * sourceHeight)), 16_384 / max(first.width, sourceHeight))
        let width = max(1, Int(floor(first.width * scale)))
        let height = max(1, Int(floor(sourceHeight * scale)))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CocoaError(.fileWriteUnknown)
        }
        var sourceY: Double = 0
        for page in pages {
            try Task.checkCancellation()
            let top = Int((sourceY / sourceHeight * Double(height)).rounded())
            sourceY += page.height
            let bottom = Int((sourceY / sourceHeight * Double(height)).rounded())
            try autoreleasepool {
                guard let source = CGImageSourceCreateWithURL(page.url as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                // Core Graphics 从底部计坐标，首段应放在最终图片顶部。
                context.draw(image, in: CGRect(x: 0, y: height - bottom, width: width, height: bottom - top))
            }
        }
        try Task.checkCancellation()
        let url = directory.appendingPathComponent("report.png")
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return .init(url: url, width: Double(width), height: Double(height))
    }

    private func prune(excluding current: URL) {
        let manager = FileManager.default
        let directories = (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let entries = directories.map { directory -> (URL, Int, Date) in
            let files = (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
            let size = files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
            let date = (try? directory.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return (directory, size, date)
        }.sorted { $0.2 < $1.2 }
        var total = entries.reduce(0) { $0 + $1.1 }
        for entry in entries where total > 160 * 1024 * 1024 && entry.0 != current {
            try? manager.removeItem(at: entry.0)
            total -= entry.1
        }
    }
}
