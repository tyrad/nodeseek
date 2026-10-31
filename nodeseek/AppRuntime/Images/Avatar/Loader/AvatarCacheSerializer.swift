//
//  AvatarCacheSerializer.swift
//  nodeseek
//
//  Created by Codex on 2026/10/31.
//

import ImageIO
import Kingfisher
import UIKit

/// 头像磁盘缓存的读写。
/// 读取在 Kingfisher 的磁盘队列上执行，这里顺带解码，避免上屏时在主线程现解。
/// 不用 `.backgroundDecode`：它会对刚处理好的位图调用 `preparingForDisplay()`，系统报 -17102 解码错误。
/// 也不能只靠 ImageIO 的立即缓存：预取进内存的图上屏前可能被 ImageIO 回收，又回到主线程解码。
struct AvatarCacheSerializer: CacheSerializer {
    static let `default` = AvatarCacheSerializer()

    var originalDataUsed: Bool { false }

    func data(with image: KFCrossPlatformImage, original: Data?) -> Data? {
        DefaultCacheSerializer.default.data(with: image, original: original)
    }

    func image(with data: Data, options: KingfisherParsedOptionsInfo) -> KFCrossPlatformImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let encoded = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let bitmap = Self.decodedBitmap(from: encoded)
        else {
            return DefaultCacheSerializer.default.image(with: data, options: options)
        }
        return UIImage(cgImage: bitmap, scale: options.scaleFactor, orientation: .up)
    }

    /// 画进 8 位 sRGB 位图，像素由图片自己持有，上屏时可直接使用。
    private static func decodedBitmap(from image: CGImage) -> CGImage? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              )
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }
}
