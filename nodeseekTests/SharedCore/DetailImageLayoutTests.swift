//
//  DetailImageLayoutTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/4/28.
//

import CoreGraphics
import Testing
#if SWIFT_PACKAGE
@testable import NodeSeekCore
#else
@testable import nodeseek
#endif

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

    @Test func normalPhotoUsesAspectFitPresentation() {
        let presentation = DetailImageLayout.presentation(
            for: CGSize(width: 1200, height: 800),
            maxWidth: 320,
            isSticker: false
        )

        #expect(presentation.size.width == 320)
        #expect(abs(presentation.size.height - 213.333) < 0.01)
        #expect(presentation.mode == .aspectFit)
        #expect(presentation.targetPointSide == 320)
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

    @Test func fixedNormalImageAllowsInlineAnimation() {
        #expect(DetailImageLayout.allowsInlineAnimation(
            for: CGSize(width: 1200, height: 800),
            maxWidth: 320,
            isSticker: false
        ))
    }

    @Test func containedImageDoesNotAllowInlineAnimation() {
        #expect(DetailImageLayout.allowsInlineAnimation(
            for: CGSize(width: 800, height: 2000),
            maxWidth: 320,
            isSticker: false
        ) == false)
    }

    @Test func stickerAllowsInlineAnimation() {
        #expect(DetailImageLayout.allowsInlineAnimation(
            for: CGSize(width: 65, height: 65),
            maxWidth: 320,
            isSticker: true
        ))
    }

    @Test func stickerAllowsInlineAnimationBeforeOriginalSizeIsKnown() {
        #expect(DetailImageLayout.allowsInlineAnimation(
            for: .zero,
            maxWidth: 320,
            isSticker: true
        ))
    }
}
