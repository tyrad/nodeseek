import Darwin
import ImageIO
@testable import nodeseek
import UIKit
import XCTest

/// 大 WebP 解码阶段缩放：尺寸、颜色、透明度与 ImageIO 一致，内存峰值不再随原图尺寸增长。
final class WebPScaledDecoderTests: XCTestCase {
    func testLargeWebPMatchesImageIOSizeAndColorProfile() throws {
        let data = try DetailWebPTestFixture.data(name: "webp-large-p3-6000x4000")
        let image = try XCTUnwrap(WebPScaledDecoder.downsampledImage(data: data, maxPixelSize: 1100))
        let reference = try XCTUnwrap(imageIOThumbnail(data, maxPixelSize: 1100))
        let cgImage = try XCTUnwrap(image.cgImage)

        XCTAssertEqual(cgImage.width, reference.width)
        XCTAssertEqual(cgImage.height, reference.height)
        XCTAssertEqual(cgImage.colorSpace?.name, CGColorSpace.displayP3, "应沿用 ICC 颜色配置")
        // 左上绿色块、中部渐变的颜色与 ImageIO 结果一致（统一转到 sRGB 比较）。
        for point in [CGPoint(x: 0.1, y: 0.05), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.9, y: 0.9)] {
            assertSimilar(pixel(cgImage, at: point), pixel(reference, at: point), tolerance: 12)
        }
    }

    func testAlphaIsPreserved() throws {
        let data = try DetailWebPTestFixture.data(name: "webp-alpha-1600x1200")
        // 夹具低于默认阈值，这里放开阈值单测透明通道。
        let image = try XCTUnwrap(WebPScaledDecoder.downsampledImage(data: data, maxPixelSize: 400, minimumSourcePixels: 0))
        let cgImage = try XCTUnwrap(image.cgImage)

        XCTAssertEqual(cgImage.width, 400)
        XCTAssertEqual(cgImage.height, 300)
        XCTAssertEqual(pixel(cgImage, at: CGPoint(x: 0.75, y: 0.75))[3], 0, "右下透明区域应保持透明")
        XCTAssertEqual(pixel(cgImage, at: CGPoint(x: 0.25, y: 0.25))[3], 255)
    }

    func testUnsupportedInputsFallBackToImageIO() throws {
        // 动图：交给 ImageIO / FramePlay。
        XCTAssertNil(WebPScaledDecoder.downsampledImage(data: try DetailWebPTestFixture.data(), maxPixelSize: 100, minimumSourcePixels: 0))
        // 小图：低于阈值保持原路径。
        XCTAssertNil(WebPScaledDecoder.downsampledImage(data: try DetailWebPTestFixture.data(name: "webp-alpha-1600x1200"), maxPixelSize: 400))
        // 目标不小于原图：不需要缩放。
        XCTAssertNil(WebPScaledDecoder.downsampledImage(data: try DetailWebPTestFixture.data(name: "webp-alpha-1600x1200"), maxPixelSize: 4000, minimumSourcePixels: 0))
        // 非 WebP、截断数据。
        XCTAssertNil(WebPScaledDecoder.downsampledImage(data: Data("not an image".utf8), maxPixelSize: 100, minimumSourcePixels: 0))
        let large = try DetailWebPTestFixture.data(name: "webp-large-p3-6000x4000")
        XCTAssertNil(WebPScaledDecoder.downsampledImage(data: large.prefix(large.count / 2), maxPixelSize: 1100))
    }

    func testNonRGBICCProfileFallsBackToSRGBWithoutDroppingScaledDecode() throws {
        let large = try DetailWebPTestFixture.data(name: "webp-large-p3-6000x4000")
        let grayICC = try XCTUnwrap(CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)?.copyICCData() as Data?)
        let mutated = try replacingChunk("ICCP", in: large, with: grayICC)

        let image = try XCTUnwrap(WebPScaledDecoder.downsampledImage(data: mutated, maxPixelSize: 1100))
        let cgImage = try XCTUnwrap(image.cgImage)
        XCTAssertEqual(cgImage.width, 1100)
        XCTAssertEqual(cgImage.height, 733)
        XCTAssertEqual(cgImage.colorSpace?.name, CGColorSpace.sRGB)
    }

    func testEmptyICCPChunkDoesNotCrashAndFallsBackToSRGB() throws {
        let large = try DetailWebPTestFixture.data(name: "webp-large-p3-6000x4000")
        let mutated = try replacingChunk("ICCP", in: large, with: Data())

        let image = try XCTUnwrap(WebPScaledDecoder.downsampledImage(data: mutated, maxPixelSize: 1100))
        let cgImage = try XCTUnwrap(image.cgImage)
        XCTAssertEqual(cgImage.width, 1100)
        XCTAssertEqual(cgImage.height, 733)
        XCTAssertEqual(cgImage.colorSpace?.name, CGColorSpace.sRGB)
    }

    func testEXIFRotatedWebPFallsBackToImageIOAndPreservesRotation() throws {
        let large = try DetailWebPTestFixture.data(name: "webp-large-p3-6000x4000")
        let rotated = try appendingEXIFOrientation(6, to: large)

        XCTAssertNil(WebPScaledDecoder.downsampledImage(data: rotated, maxPixelSize: 1100))
        let image = try XCTUnwrap(ImageRenderer.downsampledImage(data: rotated, maxPixelSize: 1100))
        let cgImage = try XCTUnwrap(image.cgImage)
        // 6000×4000 顺时针旋转 90° 后变为竖图 733×1100。
        XCTAssertEqual(cgImage.width, 733)
        XCTAssertEqual(cgImage.height, 1100)
    }

    func testImageRendererUsesScaledDecodeForLargeWebP() throws {
        let data = try DetailWebPTestFixture.data(name: "webp-large-p3-6000x4000")
        // 6000×4000 原图位图约 92MB；ImageIO 路径峰值与之相当，解码阶段缩放应远低于此。
        let (image, peak) = measurePeak { ImageRenderer.downsampledImage(data: data, maxPixelSize: 1100) }
        let (_, imageIOPeak) = measurePeak { imageIOThumbnail(data, maxPixelSize: 1100) }

        XCTAssertEqual(image?.cgImage?.width, 1100)
        XCTAssertLessThan(peak, 30 * 1_048_576, "峰值增量 \(peak / 1_048_576)MB")
        XCTAssertGreaterThan(imageIOPeak, 60 * 1_048_576, "对照组应体现 ImageIO 的整图解码峰值，否则本测试失去意义")
    }

    // MARK: - Helpers

    /// 替换 WebP RIFF 容器内指定 FourCC 块的内容，并更新 RIFF 总长度。
    private func replacingChunk(_ fourCC: String, in data: Data, with payload: Data) throws -> Data {
        let target = Data(fourCC.utf8)
        var offset = 12
        var result = Data(data.prefix(12))
        var replaced = false
        while offset + 8 <= data.count {
            let chunkID = data[offset ..< offset + 4]
            let size = Int(readUInt32LE(data, at: offset + 4))
            let padded = size + (size & 1)
            let next = offset + 8 + padded
            guard next <= data.count else { break }
            if chunkID == target, !replaced {
                appendChunk(fourCC, payload: payload, to: &result)
                replaced = true
            } else {
                result.append(data[offset ..< next])
            }
            offset = next
        }
        XCTAssertTrue(replaced, "夹具中应包含 \(fourCC) 块")
        writeUInt32LE(UInt32(result.count - 8), into: &result, at: 4)
        return result
    }

    /// 在 VP8X WebP 末尾追加带方向标记的 EXIF 块并置位 VP8X EXIF 标志。
    private func appendingEXIFOrientation(_ orientation: UInt16, to data: Data) throws -> Data {
        var result = data
        XCTAssertEqual(String(data: result[12 ..< 16], encoding: .ascii), "VP8X")
        result[20] |= 0x08
        // 最小小端 TIFF EXIF：IFD0 仅包含 Orientation (0x0112)。
        let exif: [UInt8] = [
            0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00,
            0x01, 0x00,
            0x12, 0x01, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00,
            UInt8(orientation & 0xFF), UInt8(orientation >> 8), 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
        ]
        appendChunk("EXIF", payload: Data(exif), to: &result)
        writeUInt32LE(UInt32(result.count - 8), into: &result, at: 4)
        return result
    }

    private func appendChunk(_ fourCC: String, payload: Data, to data: inout Data) {
        data.append(contentsOf: fourCC.utf8)
        var size = UInt32(payload.count).littleEndian
        withUnsafeBytes(of: &size) { data.append(contentsOf: $0) }
        data.append(payload)
        if payload.count & 1 == 1 { data.append(0) }
    }

    private func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private func writeUInt32LE(_ value: UInt32, into data: inout Data, at offset: Int) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.replaceSubrange(offset ..< offset + 4, with: $0) }
    }

    private func imageIOThumbnail(_ data: Data, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary)
    }

    /// 绘制到 sRGB 1×1 位图读取 RGBA，y 自顶向下。
    private func pixel(_ image: CGImage, at point: CGPoint) -> [UInt8] {
        var rgba = [UInt8](repeating: 0, count: 4)
        rgba.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            let x = CGFloat(image.width) * point.x, y = CGFloat(image.height) * (1 - point.y)
            context.draw(image, in: CGRect(x: -x, y: -y, width: CGFloat(image.width), height: CGFloat(image.height)))
        }
        return rgba
    }

    private func assertSimilar(_ lhs: [UInt8], _ rhs: [UInt8], tolerance: Int, file: StaticString = #filePath, line: UInt = #line) {
        let diff = zip(lhs, rhs).map { abs(Int($0) - Int($1)) }.max() ?? 0
        XCTAssertLessThanOrEqual(diff, tolerance, "\(lhs) vs \(rhs)", file: file, line: line)
    }

    private func measurePeak<T>(_ body: () -> T) -> (T, Int) {
        let base = footprint()
        let lock = NSLock()
        var peak = base, running = true
        let sampler = Thread {
            while lock.withLock({ running }) {
                let value = self.footprint()
                lock.withLock { peak = max(peak, value) }
                usleep(500)
            }
        }
        sampler.start()
        let value = body()
        lock.withLock { running = false; peak = max(peak, footprint()) }
        return (value, lock.withLock { peak } - base)
    }

    private nonisolated func footprint() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint) : 0
    }
}
