//
//  WebPScaledDecoder.swift
//  nodeseek
//

import Foundation
import ImageIO
import libwebp
import UIKit

/// 大尺寸静态 WebP 在解码阶段直接缩放到目标尺寸。
///
/// ImageIO 解 WebP 不支持按比例解码，生成缩略图时也会先解出整张原图位图
/// （4200×8000 瞬时约 128MB，多张并发会叠加）。libwebp 逐行重采样，有损编码峰值约等于输出尺寸；
/// 无损编码（VP8L）解码器仍需整张原图缓冲区，峰值与 ImageIO 相当，不会更差。
/// 不适用的情况（动图、带旋转方向、解码失败）返回 nil，由调用方继续走 ImageIO。
enum WebPScaledDecoder {
    /// 原图位图约 16MB 以下时 ImageIO 的峰值可接受，保留原有解码路径。
    nonisolated static let minimumSourcePixels = 4_000_000

    private nonisolated static let iccFlag: UInt8 = 0x20
    private nonisolated static let exifFlag: UInt8 = 0x08

    nonisolated static func downsampledImage(
        data: Data,
        maxPixelSize: Int,
        minimumSourcePixels: Int = WebPScaledDecoder.minimumSourcePixels
    ) -> UIImage? {
        guard maxPixelSize > 0, isWebP(data) else { return nil }

        var config = WebPDecoderConfig()
        guard WebPInitDecoderConfig(&config) != 0 else { return nil }
        let featureStatus = data.withUnsafeBytes { raw in
            WebPGetFeatures(raw.bindMemory(to: UInt8.self).baseAddress, raw.count, &config.input)
        }
        guard featureStatus == VP8_STATUS_OK, config.input.has_animation == 0 else { return nil }

        let width = Int(config.input.width)
        let height = Int(config.input.height)
        let longestSide = max(width, height)
        guard width > 0, height > 0, width * height >= minimumSourcePixels, longestSide > maxPixelSize else {
            return nil
        }

        let flags = extendedFlags(data)
        // EXIF 方向需要旋转时交给 ImageIO，保持与现有缩略图一致。
        if flags & exifFlag != 0, orientation(of: data) != 1 { return nil }

        // 与 ImageIO 缩略图一致：最长边等于 maxPixelSize，短边四舍五入。
        let ratio = Double(maxPixelSize) / Double(longestSide)
        let outputWidth = max(1, Int((Double(width) * ratio).rounded()))
        let outputHeight = max(1, Int((Double(height) * ratio).rounded()))
        let (bytesPerRow, rowOverflow) = outputWidth.multipliedReportingOverflow(by: 4)
        let (byteCount, totalOverflow) = bytesPerRow.multipliedReportingOverflow(by: outputHeight)
        guard !rowOverflow, !totalOverflow,
              let scaledWidth = Int32(exactly: outputWidth),
              let scaledHeight = Int32(exactly: outputHeight),
              let stride = Int32(exactly: bytesPerRow),
              let buffer = CFDataCreateMutable(nil, byteCount)
        else { return nil }
        CFDataSetLength(buffer, byteCount)
        guard let rgba = CFDataGetMutableBytePtr(buffer) else { return nil }

        let hasAlpha = config.input.has_alpha != 0
        config.options.use_scaling = 1
        config.options.scaled_width = scaledWidth
        config.options.scaled_height = scaledHeight
        config.output.colorspace = hasAlpha ? MODE_rgbA : MODE_RGBA
        config.output.is_external_memory = 1
        config.output.u.RGBA.rgba = rgba
        config.output.u.RGBA.stride = stride
        config.output.u.RGBA.size = byteCount

        let decodeStatus = data.withUnsafeBytes { raw in
            WebPDecode(raw.bindMemory(to: UInt8.self).baseAddress, raw.count, &config)
        }
        WebPFreeDecBuffer(&config.output)
        guard decodeStatus == VP8_STATUS_OK else {
            AppLog.info(.image, "libwebp 缩放解码失败，回退 ImageIO status=\(decodeStatus.rawValue) size=\(width)x\(height)")
            return nil
        }

        let colorSpace = (flags & iccFlag != 0 ? iccColorSpace(data) : nil)
            ?? CGColorSpace(name: CGColorSpace.sRGB)
            ?? CGColorSpaceCreateDeviceRGB()
        let alphaInfo: CGImageAlphaInfo = hasAlpha ? .premultipliedLast : .noneSkipLast
        guard let provider = CGDataProvider(data: buffer),
              let image = CGImage(
                  width: outputWidth, height: outputHeight,
                  bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo(rawValue: alphaInfo.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
              )
        else { return nil }
        return UIImage(cgImage: image, scale: 1, orientation: .up)
    }

    private nonisolated static func isWebP(_ data: Data) -> Bool {
        data.count >= 16
            && data.prefix(4).elementsEqual("RIFF".utf8)
            && data.dropFirst(8).prefix(4).elementsEqual("WEBP".utf8)
    }

    /// VP8X 头的特性位（ICC、EXIF、动画等）；简单格式没有扩展头时返回 0。
    private nonisolated static func extendedFlags(_ data: Data) -> UInt8 {
        guard data.count > 20, data.dropFirst(12).prefix(4).elementsEqual("VP8X".utf8) else { return 0 }
        return data[data.startIndex + 20]
    }

    private nonisolated static func orientation(of data: Data) -> Int {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any]
        else { return 1 }
        return (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
    }

    private nonisolated static func iccColorSpace(_ data: Data) -> CGColorSpace? {
        data.withUnsafeBytes { raw -> CGColorSpace? in
            var webPData = WebPData(bytes: raw.bindMemory(to: UInt8.self).baseAddress, size: raw.count)
            guard let demux = WebPDemux(&webPData) else { return nil }
            defer { WebPDemuxDelete(demux) }
            var iterator = WebPChunkIterator()
            guard WebPDemuxGetChunk(demux, "ICCP", 1, &iterator) != 0 else { return nil }
            defer { WebPDemuxReleaseChunkIterator(&iterator) }
            guard let bytes = iterator.chunk.bytes, iterator.chunk.size > 0 else { return nil }
            let profile = Data(bytes: bytes, count: iterator.chunk.size)
            guard let colorSpace = CGColorSpace(iccData: profile as CFData), colorSpace.model == .rgb else {
                return nil
            }
            return colorSpace
        }
    }
}
