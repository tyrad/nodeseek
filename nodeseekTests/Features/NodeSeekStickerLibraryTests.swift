//
//  NodeSeekStickerLibraryTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/5/3.
//

import Foundation
import Testing
@testable import nodeseek

struct NodeSeekStickerLibraryTests {
    @Test func acPackUsesServerTokenAndImagePath() throws {
        let pack = try #require(NodeSeekStickerLibrary.defaultPacks.first { $0.title == "AC娘" })
        let firstItem = try #require(pack.items.first)

        #expect(firstItem.token == "ac01")
        #expect(firstItem.imageURLs.first?.absoluteString == "https://www.nodeseek.com/static/image/sticker/ac/01.png")
        #expect(pack.items.count == 149)
        #expect(pack.items.contains { $0.token == "ac1001" })
        #expect(pack.items.contains { $0.token == "ac2055" })
    }

    @Test func fluentPackUsesEmojiTokenAndPreviewImagePath() throws {
        let pack = try #require(NodeSeekStickerLibrary.defaultPacks.first { $0.title == "Fluent" })
        let firstItem = try #require(pack.items.first)
        let lastItem = try #require(pack.items.last)

        #expect(firstItem.token == "emoji00")
        #expect(firstItem.imageURLs.first?.absoluteString == "https://www.nodeseek.com/static/image/sticker/emoji/00.png")
        #expect(pack.items.count == 49)
        #expect(lastItem.token == "emoji48")
        #expect(lastItem.imageURLs.first?.absoluteString == "https://www.nodeseek.com/static/image/sticker/emoji/48.png")
    }
}
