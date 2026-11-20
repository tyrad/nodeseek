//
//  CommentComposerContentBuilderTests.swift
//  nodeseekTests
//

import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import NodeSeekCore
private typealias ComposerTestComment = NodeSeekCore.Comment
#else
@testable import nodeseek
private typealias ComposerTestComment = nodeseek.Comment
#endif

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
        let comment = makeComment(
            id: "9727591",
            anchorID: "10",
            authorName: "netcup",
            floorText: "#10",
            createdAtText: "1min ago",
            createdAtTitleText: "2026-04-29 13:58:43",
            contentHTML: "<p>正文</p>"
        )

        let content = CommentComposerContentBuilder.content(
            text: "bdbd",
            mode: .reply([comment]),
            postURL: postURL
        )

        #expect(content == "@netcup [#10](https://www.nodeseek.com/post-706576-1#10) bdbd")
    }

    @Test func replyCommentsPrefixMultipleMentionAndFloorLinks() throws {
        let first = makeComment(
            id: "9727591",
            anchorID: "10",
            authorName: "netcup",
            floorText: "#10"
        )
        let second = makeComment(
            id: "9727592",
            anchorID: "11",
            authorName: "alice",
            floorText: "#11"
        )

        let content = CommentComposerContentBuilder.content(
            text: "bdbd",
            mode: .reply([first, second]),
            postURL: postURL
        )

        #expect(content == """
        @netcup [#10](https://www.nodeseek.com/post-706576-1#10) @alice [#11](https://www.nodeseek.com/post-706576-2#11) bdbd
        """)
    }

    @Test func quoteCommentWithoutMarkdownKeepsParagraphAndLineBreaks() {
        let comment = makeComment(
            id: "9727591",
            anchorID: "10",
            authorName: "netcup",
            floorText: "#10",
            createdAtText: "1min ago",
            createdAtTitleText: "2026-04-29 13:58:43",
            contentHTML: "<p>第一段<br>第二行</p><p>第二段</p>"
        )

        let content = CommentComposerContentBuilder.content(
            text: "bb",
            mode: .quote([comment]),
            postURL: postURL
        )

        #expect(content == """
        > @netcup [#10](https://www.nodeseek.com/post-706576-1#10) 发布于2026-04-29 13:58:43
        > 第一段
        > 第二行
        > 第二段

        bb
        """)
    }

    // 与网页「引用」一致：正文取原始 Markdown 逐行加 "> "，空行也保留；编辑过的评论标题行带编辑时间。
    @Test func quoteCommentUsesSourceMarkdownLikeWeb() {
        let comment = ComposerTestComment(
            id: "14144966",
            anchorID: "4",
            authorName: "缭雾",
            avatarURL: nil,
            floorText: "#4",
            createdAtText: "4days ago",
            createdAtTitleText: "2026-11-15 17:03:24",
            contentHTML: "<p>渲染后的 HTML 不应被使用</p>",
            markdown: "> @缭雾 [#3](https://www.nodeseek.com/post-1016685-1#3) 发布于2026-11-15 16:59:19\n> 旧引用\n\n**Bold** and `code`.\nSecond.",
            editedAtTitleText: "2026-11-15 17:05:01"
        )

        let content = CommentComposerContentBuilder.content(
            text: "",
            mode: .quote([comment]),
            postURL: URL(string: "https://www.nodeseek.com/post-1016685-1")!
        )

        #expect(content == """
        > @缭雾 [#4](https://www.nodeseek.com/post-1016685-1#4) 发布于2026-11-15 17:03:24，编辑于2026-11-15 17:05:01
        > > @缭雾 [#3](https://www.nodeseek.com/post-1016685-1#3) 发布于2026-11-15 16:59:19
        > > 旧引用
        > 
        > **Bold** and `code`.
        > Second.
        """)
    }

    @Test func floorLinkPointsToPageContainingFloor() {
        #expect(CommentComposerContentBuilder.commentPage(forFloor: 0) == 1)
        #expect(CommentComposerContentBuilder.commentPage(forFloor: 10) == 1)
        #expect(CommentComposerContentBuilder.commentPage(forFloor: 11) == 2)
        #expect(CommentComposerContentBuilder.commentPage(forFloor: 31) == 4)

        let comment = makeComment(id: "1", anchorID: "31", authorName: "a", floorText: "#31")
        let content = CommentComposerContentBuilder.content(
            text: "hi",
            mode: .reply([comment]),
            postURL: URL(string: "https://www.nodeseek.com/post-706576-1")!
        )
        #expect(content == "@a [#31](https://www.nodeseek.com/post-706576-4#31) hi")
    }

    @Test func quoteCommentsRenderMultipleMarkdownQuoteBlocks() {
        let first = makeComment(
            id: "9727591",
            anchorID: "10",
            authorName: "netcup",
            floorText: "#10",
            createdAtTitleText: "2026-04-29 13:58:43",
            contentHTML: "<p>第一段</p>"
        )
        let second = makeComment(
            id: "9727592",
            anchorID: "11",
            authorName: "alice",
            floorText: "#11",
            createdAtTitleText: "2026-04-29 14:00:00",
            contentHTML: "<p>第二条</p>"
        )

        let content = CommentComposerContentBuilder.content(
            text: "bb",
            mode: .quote([first, second]),
            postURL: postURL
        )

        #expect(content == """
        > @netcup [#10](https://www.nodeseek.com/post-706576-1#10) 发布于2026-04-29 13:58:43
        > 第一段

        > @alice [#11](https://www.nodeseek.com/post-706576-2#11) 发布于2026-04-29 14:00:00
        > 第二条

        bb
        """)
    }

    @Test func replyAndQuoteCommentsCanCoexistInOneSubmission() {
        let reply = makeComment(
            id: "9727591",
            anchorID: "10",
            authorName: "netcup",
            floorText: "#10"
        )
        let quote = makeComment(
            id: "9727592",
            anchorID: "11",
            authorName: "alice",
            floorText: "#11",
            createdAtTitleText: "2026-04-29 14:00:00",
            contentHTML: "<p>引用段落</p>"
        )

        let content = CommentComposerContentBuilder.content(
            text: "正文",
            mode: .combined(replies: [reply], quotes: [quote]),
            postURL: postURL
        )

        #expect(content == """
        > @alice [#11](https://www.nodeseek.com/post-706576-2#11) 发布于2026-04-29 14:00:00
        > 引用段落

        @netcup [#10](https://www.nodeseek.com/post-706576-1#10) 正文
        """)
    }

    @Test func stickerTokenInsertionAddsReadableSpacingAtCaret() {
        let result = StickerTokenInsertion.inserting(
            token: "yct001",
            into: "hello",
            selectedRange: NSRange(location: 5, length: 0)
        )

        #expect(result.text == "hello :yct001: ")
        #expect(result.selectedRange.location == 15)
        #expect(result.selectedRange.length == 0)
    }

    @Test func stickerTokenInsertionReplacesSelectionWithBoundedSpaces() {
        let result = StickerTokenInsertion.inserting(
            token: "xhj022",
            into: "hello world",
            selectedRange: NSRange(location: 6, length: 5)
        )

        #expect(result.text == "hello :xhj022: ")
        #expect(result.selectedRange.location == 15)
        #expect(result.selectedRange.length == 0)
    }

    @Test func stickerTokenInsertionDoesNotDuplicateExistingTrailingSpace() {
        let result = StickerTokenInsertion.inserting(
            token: "xhj022",
            into: "hello world",
            selectedRange: NSRange(location: 0, length: 5)
        )

        #expect(result.text == ":xhj022: world")
        #expect(result.selectedRange.location == 8)
        #expect(result.selectedRange.length == 0)
    }

    private func makeComment(
        id: String,
        anchorID: String? = nil,
        authorName: String,
        floorText: String?,
        createdAtText: String? = "1min ago",
        createdAtTitleText: String? = nil,
        contentHTML: String = "<p>正文</p>"
    ) -> ComposerTestComment {
        ComposerTestComment(
            id: id,
            anchorID: anchorID,
            authorName: authorName,
            avatarURL: nil,
            floorText: floorText,
            createdAtText: createdAtText,
            createdAtTitleText: createdAtTitleText,
            contentHTML: contentHTML
        )
    }
}
