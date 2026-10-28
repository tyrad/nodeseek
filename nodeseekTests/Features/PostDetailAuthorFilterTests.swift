//
//  PostDetailAuthorFilterTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/10/29.
//

import Foundation
import Testing
@testable import nodeseek

struct PostDetailAuthorFilterTests {
    private func comment(name: String, profile: String?, isPoster: Bool = false) -> nodeseek.Comment {
        Comment(
            id: UUID().uuidString,
            authorName: name,
            isPoster: isPoster,
            avatarURL: nil,
            authorProfileURL: profile.flatMap(URL.init(string:)),
            floorText: nil,
            createdAtText: nil,
            contentHTML: ""
        )
    }

    @Test func authorFilterPrefersProfileURLOverName() {
        let filter = PostDetailAuthorFilter.author(of: comment(name: "a", profile: "https://www.nodeseek.com/space/1"))

        #expect(filter.matches(comment(name: "改名后", profile: "https://www.nodeseek.com/space/1")))
        #expect(filter.matches(comment(name: "a", profile: "https://www.nodeseek.com/space/2")) == false)
        #expect(filter.matches(comment(name: "a", profile: nil)))
        #expect(filter.bannerText == "只看 a 的回复")
    }

    @Test func posterFilterMatchesPosterFlag() {
        let header = PostDetailHeaderContent(
            postID: "1",
            title: "标题",
            authorName: "op",
            avatarURL: nil,
            authorProfileURL: URL(string: "https://www.nodeseek.com/space/9"),
            metadataText: nil
        )
        let filter = PostDetailAuthorFilter.poster(of: header)

        #expect(filter.matches(comment(name: "op", profile: nil, isPoster: true)))
        #expect(filter.matches(comment(name: "op", profile: "https://www.nodeseek.com/space/9")))
        #expect(filter.matches(comment(name: "other", profile: "https://www.nodeseek.com/space/3")) == false)
        #expect(filter.bannerText == "只看楼主的回复")
    }
}
