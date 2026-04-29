//
//  DetailImageLayoutTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/4/28.
//

import CoreGraphics
import Testing
@testable import nodeseek

struct DetailImageLayoutTests {
    @Test func placeholderUsesFixedStickerSquare() {
        let size = DetailImageLayout.placeholderSize(
            maxWidth: 320,
            maxHeight: nil,
            isSticker: true
        )

        #expect(size.width == 65)
        #expect(size.height == 65)
    }

    @Test func placeholderUsesHalfWidthSquareForNormalImage() {
        let size = DetailImageLayout.placeholderSize(
            maxWidth: 320,
            maxHeight: 420,
            isSticker: false
        )

        #expect(size.width == 160)
        #expect(size.height == 160)
    }

    @Test func fixedNormalImageUsesHalfAvailableWidth() {
        let size = DetailImageLayout.fixedNormalImageSize(maxWidth: 375)

        #expect(size.width == 187)
        #expect(size.height == 187)
    }

    @Test func normalPhotoUsesCroppedThumbnailPresentation() {
        let presentation = DetailImageLayout.presentation(
            for: CGSize(width: 1200, height: 800),
            maxWidth: 320,
            isSticker: false
        )

        #expect(presentation.size == CGSize(width: 160, height: 160))
        #expect(presentation.mode == .thumbnailCrop)
        #expect(presentation.targetPointSide == 160)
    }

    @Test func tallScreenshotUsesContainedPresentation() {
        let presentation = DetailImageLayout.presentation(
            for: CGSize(width: 800, height: 2000),
            maxWidth: 320,
            isSticker: false
        )

        #expect(presentation.size == CGSize(width: 168, height: 420))
        #expect(presentation.mode == .aspectFit)
        #expect(presentation.targetPointSide == 420)
    }

    @Test func veryWideScreenshotUsesContainedPresentation() {
        let presentation = DetailImageLayout.presentation(
            for: CGSize(width: 2000, height: 800),
            maxWidth: 320,
            isSticker: false
        )

        #expect(presentation.size == CGSize(width: 320, height: 128))
        #expect(presentation.mode == .aspectFit)
        #expect(presentation.targetPointSide == 320)
    }
}
