import FramePlay
import Foundation
import ImageIO

/// 视图持有资源身份；加载器只保留弱引用，避免压缩原图常驻内存缓存。
final class DetailAnimatedImageAsset: Sendable {
    nonisolated let source: AnimatedImageSource

    nonisolated init(data: Data) { source = AnimatedImageSource(data: data) }
}

final class DetailWeakAnimatedImageAsset {
    weak var value: DetailAnimatedImageAsset?
    init(_ value: DetailAnimatedImageAsset) { self.value = value }
}

enum DetailWebPAnimation {
    nonisolated static let maximumPixelSize = 512

    nonisolated static func shouldInspectOriginal(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "webp"
            || url.absoluteString.lowercased().hasPrefix("data:image/webp")
    }

    nonisolated static func isAnimated(_ data: Data) -> Bool {
        guard data.count >= 12, data.count <= 64 * 1_024 * 1_024,
              data.prefix(4).elementsEqual("RIFF".utf8),
              data.dropFirst(8).prefix(4).elementsEqual("WEBP".utf8),
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(source) as String? == "org.webmproject.webp" else { return false }
        return CGImageSourceGetCount(source) > 1
    }
}
