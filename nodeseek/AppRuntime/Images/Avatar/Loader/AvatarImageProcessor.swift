//
//  AvatarImageProcessor.swift
//  nodeseek
//
//  Created by Codex on 2026/5/9.
//

import Kingfisher
import UIKit

struct AvatarImageProcessor: ImageProcessor {
    let size: CGSize
    let identifier: String

    init(size: CGSize) {
        self.size = size
        self.identifier = "com.nodeseek.avatar.v2(\(Int(size.width))x\(Int(size.height)))"
    }

    func process(item: ImageProcessItem, options: KingfisherParsedOptionsInfo) -> KFCrossPlatformImage? {
        switch item {
        case .data(let data) where SVGContentInspector.looksLikeSVG(data):
            return SVGImageRenderer.image(from: data, size: size)
        case .data(let data) where Self.shouldAttemptBitmapDecode(data) == false:
            return nil
        default:
            return DownsamplingImageProcessor(size: size).process(item: item, options: options)
        }
    }

    static func shouldAttemptBitmapDecode(_ data: Data) -> Bool {
        guard data.isEmpty == false else { return false }
        guard HTMLPayloadInspector.looksLikeHTMLPayload(data) == false else { return false }

        return isCompletePNG(data)
            || isCompleteJPEG(data)
            || isCompleteGIF(data)
            || isCompleteWebP(data)
            || isLikelyCompleteHEIF(data)
            || isLikelyCompleteTIFF(data)
            || isCompleteBMP(data)
    }

    private static func isCompletePNG(_ data: Data) -> Bool {
        data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
            && hasSuffix(data, [0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82])
    }

    private static func isCompleteJPEG(_ data: Data) -> Bool {
        data.starts(with: [0xFF, 0xD8, 0xFF]) && hasSuffix(data, [0xFF, 0xD9])
    }

    private static func isCompleteGIF(_ data: Data) -> Bool {
        (data.starts(with: Array("GIF87a".utf8)) || data.starts(with: Array("GIF89a".utf8)))
            && hasSuffix(data, [0x3B])
    }

    private static func isCompleteWebP(_ data: Data) -> Bool {
        guard hasSignature(data, Array("RIFF".utf8), at: 0),
              hasSignature(data, Array("WEBP".utf8), at: 8),
              let declaredSize = littleEndianUInt32(in: data, at: 4)
        else { return false }

        return Int(declaredSize) + 8 == data.count
    }

    private static func isLikelyCompleteHEIF(_ data: Data) -> Bool {
        guard hasSignature(data, Array("ftyp".utf8), at: 4) else { return false }

        let brands = [
            "avif", "avis", "heic", "heix", "hevc", "hevx", "mif1", "msf1"
        ].map { Array($0.utf8) }
        return data.count >= 32 && brands.contains { hasSignature(data, $0, at: 8) }
    }

    private static func isLikelyCompleteTIFF(_ data: Data) -> Bool {
        data.count >= 8
            && (data.starts(with: [0x49, 0x49, 0x2A, 0x00])
            || data.starts(with: [0x4D, 0x4D, 0x00, 0x2A])
        )
    }

    private static func isCompleteBMP(_ data: Data) -> Bool {
        guard data.starts(with: Array("BM".utf8)),
              let declaredSize = littleEndianUInt32(in: data, at: 2)
        else { return false }

        return Int(declaredSize) == data.count
    }

    private static func hasSignature(_ data: Data, _ signature: [UInt8], at offset: Int) -> Bool {
        guard offset >= 0, data.count >= offset + signature.count else { return false }
        return Array(data.dropFirst(offset).prefix(signature.count)) == signature
    }

    private static func hasSuffix(_ data: Data, _ suffix: [UInt8]) -> Bool {
        guard data.count >= suffix.count else { return false }
        return Array(data.suffix(suffix.count)) == suffix
    }

    private static func littleEndianUInt32(in data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, data.count >= offset + 4 else { return nil }
        let bytes = Array(data.dropFirst(offset).prefix(4))
        return UInt32(bytes[0])
            | (UInt32(bytes[1]) << 8)
            | (UInt32(bytes[2]) << 16)
            | (UInt32(bytes[3]) << 24)
    }
}
