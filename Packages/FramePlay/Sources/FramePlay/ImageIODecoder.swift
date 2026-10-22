import CoreGraphics
import Foundation
import ImageIO

internal protocol FrameDecoding: AnyObject, Sendable {
    var metadata: AnimationMetadata { get }
    func frame(at index: Int) throws -> CGImage
}

internal typealias DecoderFactory = @Sendable (Data, PlaybackConfiguration) throws -> any FrameDecoding
internal typealias PosterFactory = @Sendable (Data, PlaybackConfiguration) -> CGImage?

/// CGImageSource 的访问由锁串行化；返回的帧与 source 脱离，允许主线程显示。
internal final class ImageIODecoder: FrameDecoding, @unchecked Sendable {
    let metadata: AnimationMetadata
    private let source: CGImageSource
    private let configuration: PlaybackConfiguration
    private let lock = NSLock()

    init(data: Data, configuration: PlaybackConfiguration) throws {
        guard configuration.isValid else { throw PlaybackFailure.invalidConfiguration }
        guard data.count <= configuration.limits.maximumDataBytes else { throw PlaybackFailure.resourceLimitExceeded }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetStatus(source) == .statusComplete else { throw PlaybackFailure.invalidImageData }
        self.source = source
        self.configuration = configuration
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { throw PlaybackFailure.invalidImageData }
        guard count <= configuration.limits.maximumFrameCount else { throw PlaybackFailure.resourceLimitExceeded }
        let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any] ?? [:]
        guard let first = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (first[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (first[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0 else { throw PlaybackFailure.invalidMetadata }
        guard width <= configuration.limits.maximumCanvasPixels / height else { throw PlaybackFailure.resourceLimitExceeded }

        let type = CGImageSourceGetType(source) as String? ?? ""
        let dictionaryKey: CFString
        let delayKey: CFString
        let loopKey: CFString
        switch type {
        case "com.compuserve.gif":
            dictionaryKey = kCGImagePropertyGIFDictionary
            delayKey = kCGImagePropertyGIFUnclampedDelayTime
            loopKey = kCGImagePropertyGIFLoopCount
        case "public.png":
            dictionaryKey = kCGImagePropertyPNGDictionary
            delayKey = kCGImagePropertyAPNGUnclampedDelayTime
            loopKey = kCGImagePropertyAPNGLoopCount
        case "org.webmproject.webp":
            dictionaryKey = kCGImagePropertyWebPDictionary
            delayKey = kCGImagePropertyWebPUnclampedDelayTime
            loopKey = kCGImagePropertyWebPLoopCount
        default:
            guard count == 1 else { throw PlaybackFailure.unsupportedAnimatedFormat }
            dictionaryKey = kCGImagePropertyGIFDictionary
            delayKey = kCGImagePropertyGIFUnclampedDelayTime
            loopKey = kCGImagePropertyGIFLoopCount
        }
        let container = properties[dictionaryKey] as? [CFString: Any] ?? [:]
        var durations: [TimeInterval] = []
        for index in 0 ..< count {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else {
                throw PlaybackFailure.invalidMetadata
            }
            let frame = properties[dictionaryKey] as? [CFString: Any] ?? [:]
            let delay = (frame[delayKey] as? NSNumber)?.doubleValue ?? 0.1
            durations.append(delay.isFinite && delay > 0 ? max(delay, 1 / 120) : 0.1)
        }
        let rawLoops = (container[loopKey] as? NSNumber)?.intValue
        guard rawLoops == nil || rawLoops! >= 0 else { throw PlaybackFailure.invalidMetadata }
        let plays: Int?
        if rawLoops == 0 {
            plays = nil
        } else if let rawLoops {
            // GIF 的正数表示首轮后的重复次数；APNG/WebP 表示总轮数。
            guard rawLoops < Int.max else { throw PlaybackFailure.invalidMetadata }
            plays = type == "com.compuserve.gif" ? rawLoops + 1 : rawLoops
        } else {
            plays = 1
        }
        let orientation = (first[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        metadata = AnimationMetadata(
            pixelWidth: (5 ... 8).contains(orientation) ? height : width,
            pixelHeight: (5 ... 8).contains(orientation) ? width : height,
            frameDurations: durations, totalPlayCount: plays
        )
    }

    func frame(at index: Int) throws -> CGImage {
        lock.lock()
        defer { lock.unlock() }
        guard (0 ..< metadata.frameCount).contains(index) else { throw PlaybackFailure.frameDecodingFailed(index: index) }
        guard let image = Self.thumbnail(source, index: index, maximumPixelSize: configuration.maximumPixelSize),
              let detached = Self.detached(image) else { throw PlaybackFailure.frameDecodingFailed(index: index) }
        return detached
    }

    static func poster(data: Data, configuration: PlaybackConfiguration) -> CGImage? {
        guard configuration.isValid, data.count <= configuration.limits.maximumDataBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0, width <= configuration.limits.maximumCanvasPixels / height,
              let image = thumbnail(source, index: 0, maximumPixelSize: configuration.maximumPixelSize) else { return nil }
        return detached(image)
    }

    private static func thumbnail(_ source: CGImageSource, index: Int, maximumPixelSize: Int) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(source, index, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
        ] as CFDictionary)
    }

    private static func detached(_ image: CGImage) -> CGImage? {
        // 保留必要的离屏解码，避免 ImageIO 的惰性源引用跨线程显示；已计入性能测量。
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }
}
