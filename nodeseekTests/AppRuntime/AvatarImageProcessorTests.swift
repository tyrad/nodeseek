//
//  AvatarImageProcessorTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/5/9.
//

import Kingfisher
import UIKit
import XCTest
@testable import nodeseek

final class AvatarImageProcessorTests: XCTestCase {

    func testAvatarOptionsDoNotRequestBackgroundDecode() {
        let downloader = ImageDownloader(name: "AvatarImageProcessorTests")
        let options = KingfisherParsedOptionsInfo(AvatarImageLoadingOptions.makeOptions(downloader: downloader))

        XCTAssertFalse(options.backgroundDecode)
    }

    func testProcessorIdentifierChangesWhenDecodePolicyChanges() {
        let processor = AvatarImageProcessor(size: CGSize(width: 56, height: 56))

        XCTAssertTrue(processor.identifier.contains("v2"))
    }

    func testProcessorRendersSVGToAvatarSize() throws {
        let processor = AvatarImageProcessor(size: CGSize(width: 56, height: 56))
        let image = try XCTUnwrap(processor.process(
            item: .data(Self.svgData()),
            options: KingfisherParsedOptionsInfo(nil)
        ))

        XCTAssertEqual(image.size.width, 56, accuracy: 0.5)
        XCTAssertEqual(image.size.height, 56, accuracy: 0.5)
    }

    func testProcessorDownsamplesLargeBitmapToAvatarSize() throws {
        let processor = AvatarImageProcessor(size: CGSize(width: 56, height: 56))
        let options = KingfisherParsedOptionsInfo([.scaleFactor(3)])
        let image = try XCTUnwrap(processor.process(
            item: .data(Self.pngData(size: CGSize(width: 900, height: 600))),
            options: options
        ))

        XCTAssertLessThanOrEqual(max(image.size.width, image.size.height), 56.5)
        XCTAssertEqual(image.scale, 3, accuracy: 0.1)
    }

    func testBitmapDecodePreflightRejectsHTMLChallengePayload() {
        let html = Data("""
        <!DOCTYPE html>
        <html><head><title>Just a moment...</title></head><body></body></html>
        """.utf8)

        XCTAssertFalse(AvatarImageProcessor.shouldAttemptBitmapDecode(html))
    }

    func testBitmapDecodePreflightRejectsPlainTextPayload() {
        XCTAssertFalse(AvatarImageProcessor.shouldAttemptBitmapDecode(Data("not an image".utf8)))
    }

    func testBitmapDecodePreflightAllowsPNGPayload() {
        XCTAssertTrue(AvatarImageProcessor.shouldAttemptBitmapDecode(Self.pngData(size: CGSize(width: 12, height: 12))))
    }

    func testBitmapDecodePreflightRejectsTruncatedPNGPayload() {
        let data = Self.pngData(size: CGSize(width: 12, height: 12))

        XCTAssertFalse(AvatarImageProcessor.shouldAttemptBitmapDecode(data.prefix(24)))
    }

    func testBitmapDecodePreflightRejectsTruncatedJPEGPayload() {
        let data = Self.jpegData(size: CGSize(width: 12, height: 12))

        XCTAssertFalse(AvatarImageProcessor.shouldAttemptBitmapDecode(data.dropLast(2)))
    }

    private static func pngData(size: CGSize) -> Data {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return image.pngData() ?? Data()
    }

    private static func jpegData(size: CGSize) -> Data {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return image.jpegData(compressionQuality: 0.9) ?? Data()
    }

    private static func svgData() -> Data {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="120" height="120" viewBox="0 0 120 120">
          <rect width="120" height="120" fill="#E5E7EB"/>
          <circle cx="60" cy="45" r="24" fill="#111827"/>
          <rect x="28" y="75" width="64" height="32" rx="16" fill="#111827"/>
        </svg>
        """
        return Data(svg.utf8)
    }
}
