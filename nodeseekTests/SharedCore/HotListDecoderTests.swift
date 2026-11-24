//
//  HotListDecoderTests.swift
//  nodeseekTests
//

import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import NodeSeekCore
#else
@testable import nodeseek
#endif

private final class HotListFixtureToken {}

struct HotListDecoderTests {
    private func fixtureData(_ name: String) throws -> Data {
        #if SWIFT_PACKAGE
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        #else
        let url = try #require(Bundle(for: HotListFixtureToken.self).url(forResource: name, withExtension: "json"))
        #endif
        return try Data(contentsOf: url)
    }

    @Test func decodesRealtimeFixtureInScoreOrder() throws {
        let response = try HotListDecoder.decode(fixtureData("hot-list-realtime"))

        #expect(response.entries.count == 30)
        #expect(response.updatedAt == Date(timeIntervalSince1970: 1_795_508_253))
        let first = try #require(response.entries.first)
        #expect(first.postID == 1_076_818)
        #expect(first.title == "出总价1.5万打包出21鸡")
        #expect(first.authorName == "Mumu0808")
        #expect(first.authorID == 73375)
        #expect(first.viewCount == 1002)
        #expect(first.commentCount == 45)
        #expect(first.categoryTitle == "交易")
        let scores = response.entries.map(\.score)
        #expect(scores == scores.sorted(by: >))
    }

    @Test func convertsEntryToPostSummaryWithSiteURLs() throws {
        let response = try HotListDecoder.decode(fixtureData("hot-list-realtime"))
        let summary = try #require(response.entries.first).postSummary

        #expect(summary.id == "1076818")
        #expect(summary.url.absoluteString == "https://www.nodeseek.com/post-1076818-1")
        #expect(summary.avatarURL?.absoluteString == "https://www.nodeseek.com/avatar/73375.png")
        #expect(summary.authorProfileURL?.absoluteString == "https://www.nodeseek.com/space/73375")
        #expect(summary.nodeName == "交易")
        #expect(summary.replyCount == 45)
        #expect(summary.viewCount == 1002)
    }

    @Test func skipsEntriesWithoutIDOrTitleAndDefaultsOptionalFields() throws {
        let json = """
        {"posts": [
          {"post": {"id": 1, "title": "  "}, "score": 9},
          {"post": {"title": "缺 ID"}, "score": 8},
          {"post": {"id": "2", "title": "只有必填字段", "category": "unknown"}},
          "not-an-object"
        ]}
        """
        let response = try HotListDecoder.decode(Data(json.utf8))

        #expect(response.updatedAt == nil)
        #expect(response.entries.count == 1)
        let entry = try #require(response.entries.first)
        #expect(entry.postID == 2)
        #expect(entry.authorName.isEmpty)
        #expect(entry.authorID == nil)
        #expect(entry.avatarURL == nil)
        #expect(entry.categoryTitle == nil)
        #expect(entry.score == 0)
    }

    @Test func rejectsPayloadWithoutPostsArray() {
        #expect(throws: HotListDecodingError.invalidFormat) {
            try HotListDecoder.decode(Data("<html>challenge</html>".utf8))
        }
        #expect(throws: HotListDecodingError.invalidFormat) {
            try HotListDecoder.decode(Data(#"{"updated_at": 1}"#.utf8))
        }
    }
}
