//
//  CommentComposerContentBuilderTests.swift
//  nodeseekTests
//

import Foundation
import Testing
@testable import nodeseek

struct CommentComposerContentBuilderTests {
    private let postURL = URL(string: "https://www.nodeseek.com/post-706576-1")!

    @Test func plainCommentUsesUserTextOnly() {
        let content = CommentComposerContentBuilder.content(
            text: "bdbd",
            mode: .plain,
            postURL: postURL
        )

        #expect(content == "bdbd")
    }

    @Test func replyCommentPrefixesMentionAndFloorLink() throws {
        let comment = Comment(
            id: "9727591",
            anchorID: "10",
            authorName: "netcup",
            avatarURL: nil,
            floorText: "#10",
            createdAtText: "1min ago",
            createdAtTitleText: "2026-04-29 13:58:43",
            contentHTML: "<p>正文</p>"
        )

        let content = CommentComposerContentBuilder.content(
            text: "bdbd",
            mode: .reply(comment),
            postURL: postURL
        )

        #expect(content == "@netcup [#10](https://www.nodeseek.com/post-706576-1#10) bdbd")
    }

    @Test func quoteCommentUsesOnlyFirstParagraphAsMarkdownQuote() {
        let comment = Comment(
            id: "9727591",
            anchorID: "10",
            authorName: "netcup",
            avatarURL: nil,
            floorText: "#10",
            createdAtText: "1min ago",
            createdAtTitleText: "2026-04-29 13:58:43",
            contentHTML: "<p>第一段<br>第二行</p><p>第二段不引用</p>"
        )

        let content = CommentComposerContentBuilder.content(
            text: "bb",
            mode: .quote(comment),
            postURL: postURL
        )

        #expect(content == """
        > @netcup [#10](https://www.nodeseek.com/post-706576-1#10) 发布于2026-04-29 13:58:43
        > 第一段 第二行

        bb
        """)
    }
}
