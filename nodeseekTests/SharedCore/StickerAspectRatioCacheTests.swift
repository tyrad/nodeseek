//
//  StickerAspectRatioCacheTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/5/12.
//

import CoreGraphics
import Foundation
import Testing
#if SWIFT_PACKAGE
    @testable import NodeSeekCore
#else
    @testable import nodeseek
#endif

struct StickerAspectRatioCacheTests {
    @Test func cachedSourceSizeUsesLoadedImageAspectRatio() throws {
        let url = try #require(URL(string: "https://www.nodeseek.com/static/image/sticker/xhj/003.png?cache=1"))
        let cache = StickerAspectRatioCache(storageURL: nil)

        cache.recordLoadedSize(CGSize(width: 80, height: 160), for: url)

        let sourceSize = try #require(cache.cachedSourceSize(for: url))
        #expect(sourceSize == CGSize(width: 0.5, height: 1))
    }

    @Test func normalizedKeysIgnoreQueryAndFragment() throws {
        let loadedURL = try #require(URL(string: "https://www.nodeseek.com/static/image/sticker/xhj/003.png?cache=1#preview"))
        let renderURL = try #require(URL(string: "https://www.nodeseek.com/static/image/sticker/xhj/003.png"))
        let cache = StickerAspectRatioCache(storageURL: nil)

        cache.recordLoadedSize(CGSize(width: 120, height: 80), for: loadedURL)

        let sourceSize = try #require(cache.cachedSourceSize(for: renderURL))
        #expect(sourceSize == CGSize(width: 1.5, height: 1))
    }

    @Test func invalidRatiosAreIgnored() throws {
        let url = try #require(URL(string: "https://www.nodeseek.com/static/image/sticker/xhj/003.png"))
        let cache = StickerAspectRatioCache(storageURL: nil)

        cache.recordLoadedSize(CGSize(width: 1000, height: 1), for: url)

        #expect(cache.cachedSourceSize(for: url) == nil)
    }
}
