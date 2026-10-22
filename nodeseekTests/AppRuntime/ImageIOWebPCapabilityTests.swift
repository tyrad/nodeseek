import CryptoKit
import ImageIO
import UIKit
import XCTest

/// 独立验证系统解码能力，不经过业务图片加载器或第三方图片库。
final class ImageIOWebPCapabilityTests: XCTestCase {
    // 来源：https://www.nodeseek.com/post-881951-1
    // 原图：https://cdn.nodeimage.com/i/WS2rftGPk8LhRyJ3wH4nHEgRDqU67Hhq.webp
    // 预期值来自 WebP 容器：25 个 ANMF，每帧 120 ms，ANIM 循环次数为 0。
    private let frameCount = 25

    func testReadsAnimationMetadata() throws {
        let source = try makeSource()
        XCTAssertEqual(CGImageSourceGetType(source) as String?, "org.webmproject.webp")
        XCTAssertEqual(CGImageSourceGetCount(source), frameCount)

        let properties = try XCTUnwrap(CGImageSourceCopyProperties(source, nil) as? [CFString: Any])
        let webP = try XCTUnwrap(properties[kCGImagePropertyWebPDictionary] as? [CFString: Any])
        XCTAssertEqual((webP[kCGImagePropertyWebPLoopCount] as? NSNumber)?.intValue, 0)
        XCTAssertEqual((webP[kCGImagePropertyWebPCanvasPixelWidth] as? NSNumber)?.intValue, 640)
        XCTAssertEqual((webP[kCGImagePropertyWebPCanvasPixelHeight] as? NSNumber)?.intValue, 640)
        let frameInfo = try XCTUnwrap(webP[kCGImagePropertyWebPFrameInfoArray] as? [[CFString: Any]])
        XCTAssertEqual(frameInfo.count, frameCount)

        var duration = 0.0
        for index in 0 ..< frameCount {
            let frameProperties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any])
            let timing = try XCTUnwrap(frameProperties[kCGImagePropertyWebPDictionary] as? [CFString: Any])
            let delay = try XCTUnwrap(timing[kCGImagePropertyWebPUnclampedDelayTime] as? NSNumber).doubleValue
            XCTAssertEqual(delay, 0.12, accuracy: 0.000_001)
            let containerDelay = try XCTUnwrap(frameInfo[index][kCGImagePropertyWebPUnclampedDelayTime] as? NSNumber)
            XCTAssertEqual(containerDelay.doubleValue, delay, accuracy: 0.000_001)
            duration += delay
        }
        XCTAssertEqual(duration, 3, accuracy: 0.000_001)
        recordObservation("metadata", "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion), 640x640, \(frameCount) frames, duration=\(duration)s, loop=0")
    }

    func testDecodesAllFramesAndSupportsOutOfOrderAccess() throws {
        let source = try makeSource()
        let start = ProcessInfo.processInfo.systemUptime
        var hashes: [SHA256.Digest] = []
        for index in 0 ..< frameCount {
            let hash = try autoreleasepool {
                let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, index, nil))
                XCTAssertEqual(image.width, 640)
                XCTAssertEqual(image.height, 640)
                if [0, 12, 24].contains(index) {
                    let attachment = XCTAttachment(image: UIImage(cgImage: image))
                    attachment.name = "WebP-frame-\(index)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
                return try pixelHash(image)
            }
            hashes.append(hash)
        }
        XCTAssertGreaterThan(Set(hashes).count, 1, "多帧解码不能一直返回首帧")
        recordObservation("full-decode", "full decode + RGBA hash + attachments=\(ProcessInfo.processInfo.systemUptime - start)s, distinct frames=\(Set(hashes).count)/\(frameCount)")

        // 使用新的 source，从末帧开始读，避免顺序解码缓存掩盖随机读取问题。
        let randomSource = try makeSource()
        for index in [24, 0, 12, 1, 23] {
            try autoreleasepool {
                let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(randomSource, index, nil))
                XCTAssertEqual(try pixelHash(image), hashes[index], "第 \(index) 帧乱序读取应与顺序读取一致")
            }
        }
    }

    func testCreatesBoundedThumbnailsForEveryFrame() throws {
        let source = try makeSource()
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 320,
        ]
        var hashes = Set<SHA256.Digest>()
        let start = ProcessInfo.processInfo.systemUptime
        for index in 0 ..< frameCount {
            try autoreleasepool {
                let thumbnail = try XCTUnwrap(CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary))
                XCTAssertEqual(thumbnail.width, 320)
                XCTAssertEqual(thumbnail.height, 320)
                hashes.insert(try pixelHash(thumbnail))
            }
        }
        XCTAssertGreaterThan(hashes.count, 1, "逐帧缩略图不能全部退化成首帧")
        recordObservation("thumbnails", "320x320 thumbnails + RGBA hash=\(ProcessInfo.processInfo.systemUptime - start)s, distinct frames=\(hashes.count)/\(frameCount)")
    }

    @MainActor
    func testSystemAnimationAPIPlaysFramesAndHonorsStopRequest() async throws {
        let data = try fixtureData()
        let completed = expectation(description: "系统动画接口回调一轮 WebP 帧")
        let unexpectedCallback = expectation(description: "停止后不应继续回调")
        unexpectedCallback.isInverted = true
        var indexes: [Int] = []
        var callbackTimes: [TimeInterval] = []
        let count = frameCount

        // 原图无限循环，明确在末帧停止，避免测试遗留后台动画任务。
        let status = CGAnimateImageDataWithBlock(data as CFData, nil) { index, image, stop in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(image.width, 640)
            XCTAssertEqual(image.height, 640)
            indexes.append(index)
            callbackTimes.append(ProcessInfo.processInfo.systemUptime)
            if indexes.count > count {
                stop.pointee = true
                unexpectedCallback.fulfill()
            } else if index == count - 1 {
                stop.pointee = true
                completed.fulfill()
            }
        }
        XCTAssertEqual(status, 0)
        guard status == 0 else { return }
        await fulfillment(of: [completed], timeout: 8)
        await fulfillment(of: [unexpectedCallback], timeout: 0.3)
        XCTAssertEqual(indexes, Array(0 ..< count))
        let span = try XCTUnwrap(callbackTimes.last) - XCTUnwrap(callbackTimes.first)
        recordObservation("system-animation", "status=\(status), callbacks=\(indexes.count), first-to-last=\(span)s, stop honored")
    }

    func testUIImageDataInitializerReturnsStaticImage() throws {
        let image = try XCTUnwrap(UIImage(data: fixtureData()))
        XCTAssertEqual(image.size, CGSize(width: 640, height: 640))
        XCTAssertNil(image.images, "能解码 WebP 不代表 UIImage(data:) 会创建动画帧数组")
        XCTAssertEqual(image.duration, 0)
    }

    private func fixtureData() throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "post-881951-animated", withExtension: "webp"))
        return try Data(contentsOf: url)
    }

    private func makeSource() throws -> CGImageSource {
        let data = try fixtureData()
        return try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary))
    }

    private func recordObservation(_ name: String, _ message: String) {
        let attachment = XCTAttachment(string: message)
        attachment.name = "ImageIO-WebP-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func pixelHash(_ image: CGImage) throws -> SHA256.Digest {
        let bytesPerRow = image.width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * image.height)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return SHA256.hash(data: Data(pixels))
    }
}
