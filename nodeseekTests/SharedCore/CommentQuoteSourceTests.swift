//
//  CommentQuoteSourceTests.swift
//  nodeseekTests
//
//  从帖子页 HTML（含 temp-script 配置）解析，到拼出引用/回复文本的完整链路。
//  规则对照网页 markdownEditor 里的引用函数：正文取 postData.comments[].markdown 逐行加 "> "，
//  编辑过追加「，编辑于」，楼层链接指向楼层所在页（0 楼第 1 页，其余每 10 楼一页）。
//

import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import NodeSeekCore
private typealias QuoteTestComment = NodeSeekCore.Comment
#else
@testable import nodeseek
private typealias QuoteTestComment = nodeseek.Comment
#endif

struct CommentQuoteSourceTests {
    private let postID = "1016685"

    // MARK: - 不分页

    @Test func singlePagePostQuotesSourceMarkdownLineByLine() throws {
        let detail = try parsePage(1, comments: [
            .init(id: 100, floor: 0, author: "楼主", markdown: "正文"),
            .init(id: 101, floor: 1, author: "alice", markdown: "line 1\nline 2\nline 3"),
            .init(
                id: 102, floor: 2, author: "bob",
                markdown: "> @alice [#1](https://www.nodeseek.com/post-1016685-1#1) 发布于2026-11-15 16:59:19\n> line 1\n\n```\ncode block\n```\n![](https://example.com/a.png) :ac03:"
            )
        ])

        #expect(quote(try comment("#1", in: detail)) == """
        > @alice [#1](https://www.nodeseek.com/post-1016685-1#1) 发布于2026-11-15 17:00:01
        > line 1
        > line 2
        > line 3
        """)
        // 嵌套引用、空行、代码块、图片和表情代码都原样带上，不从渲染后的 HTML 反推
        #expect(quote(try comment("#2", in: detail)) == """
        > @bob [#2](https://www.nodeseek.com/post-1016685-1#2) 发布于2026-11-15 17:00:02
        > > @alice [#1](https://www.nodeseek.com/post-1016685-1#1) 发布于2026-11-15 16:59:19
        > > line 1
        >\u{20}
        > ```
        > code block
        > ```
        > ![](https://example.com/a.png) :ac03:
        """)
    }

    @Test func editedCommentHeaderAppendsEditedTime() throws {
        let detail = try parsePage(1, comments: [
            .init(id: 101, floor: 1, author: "alice", markdown: "改过", editedAt: "2026-11-15 18:00:00")
        ])

        #expect(quote(try comment("#1", in: detail)) == """
        > @alice [#1](https://www.nodeseek.com/post-1016685-1#1) 发布于2026-11-15 17:00:01，编辑于2026-11-15 18:00:00
        > 改过
        """)
    }

    @Test func trailingBlankLinesInMarkdownAreKeptLikeWeb() throws {
        let detail = try parsePage(1, comments: [
            .init(id: 101, floor: 1, author: "alice", markdown: "~~\n\n")
        ])

        #expect(quote(try comment("#1", in: detail)) == """
        > @alice [#1](https://www.nodeseek.com/post-1016685-1#1) 发布于2026-11-15 17:00:01
        > ~~
        >\u{20}
        >\u{20}
        """)
    }

    @Test func commentMissingFromConfigKeepsOnlyHeader() throws {
        let detail = try parsePage(
            1,
            comments: [.init(id: 101, floor: 1, author: "alice", markdown: "有原文")],
            htmlOnlyComments: [.init(id: 999, floor: 2, author: "ghost", markdown: "")]
        )

        let ghost = try comment("#2", in: detail)
        #expect(ghost.markdown == nil)
        #expect(quote(ghost) == "> @ghost [#2](https://www.nodeseek.com/post-1016685-1#2) 发布于2026-11-15 17:00:02")
    }

    // MARK: - 分页

    @Test func secondPageCommentsCarryTheirOwnPageMarkdownAndLinks() throws {
        let page2 = try parsePage(2, comments: [
            .init(id: 211, floor: 11, author: "carol", markdown: "第二页\n第二行"),
            .init(id: 220, floor: 20, author: "dave", markdown: "第二页最后一楼")
        ])

        #expect(page2.page == 2)
        #expect(quote(try comment("#11", in: page2), postURL: pageURL(2)) == """
        > @carol [#11](https://www.nodeseek.com/post-1016685-2#11) 发布于2026-11-15 17:00:11
        > 第二页
        > 第二行
        """)
        #expect(quote(try comment("#20", in: page2), postURL: pageURL(2)) == """
        > @dave [#20](https://www.nodeseek.com/post-1016685-2#20) 发布于2026-11-15 17:00:20
        > 第二页最后一楼
        """)
    }

    /// 从第 1 页进入后滚动加载第 2 页：详情页拼内容时用的是进入页 URL，链接仍要指向各楼层所在页。
    @Test func quotesAcrossLoadedPagesUseEachFloorsPage() throws {
        let page1 = try parsePage(1, comments: [
            .init(id: 110, floor: 10, author: "alice", markdown: "第一页最后一楼")
        ])
        let page2 = try parsePage(2, comments: [
            .init(id: 211, floor: 11, author: "carol", markdown: "第二页第一楼")
        ])

        let content = CommentComposerContentBuilder.content(
            text: "回复正文",
            mode: .combined(
                replies: [try comment("#11", in: page2)],
                quotes: [try comment("#10", in: page1), try comment("#11", in: page2)]
            ),
            postURL: pageURL(1)
        )

        #expect(content == """
        > @alice [#10](https://www.nodeseek.com/post-1016685-1#10) 发布于2026-11-15 17:00:10
        > 第一页最后一楼

        > @carol [#11](https://www.nodeseek.com/post-1016685-2#11) 发布于2026-11-15 17:00:11
        > 第二页第一楼

        @carol [#11](https://www.nodeseek.com/post-1016685-2#11) 回复正文
        """)
    }

    /// 从第 3 页进入时引用第 1 页置顶展示的楼层，链接也不能沿用进入页。
    @Test func enteringLaterPageStillLinksFloorToItsOwnPage() throws {
        let page3 = try parsePage(3, comments: [
            .init(id: 221, floor: 21, author: "erin", markdown: "第三页")
        ])

        #expect(quote(try comment("#21", in: page3), postURL: pageURL(3)) == """
        > @erin [#21](https://www.nodeseek.com/post-1016685-3#21) 发布于2026-11-15 17:00:21
        > 第三页
        """)
        let reply = CommentComposerContentBuilder.content(
            text: "hi",
            mode: .reply([try comment("#21", in: page3)]),
            postURL: pageURL(1)
        )
        #expect(reply == "@erin [#21](https://www.nodeseek.com/post-1016685-3#21) hi")
    }

    /// 第 1 页置顶的跨页热评：原文也在第 1 页配置里，链接指向热评原本所在页。
    @Test func hotCommentFromLaterPageHasMarkdownAndLinksToItsPage() throws {
        let page1 = try parsePage(1, comments: [
            .init(id: 100, floor: 0, author: "楼主", markdown: "正文"),
            .init(id: 131, floor: 31, author: "hot", markdown: "热评第一行\n热评第二行", hot: true),
            .init(id: 101, floor: 1, author: "alice", markdown: "一楼")
        ])

        let hot = try comment("#31", in: page1)
        #expect(hot.isHot)
        #expect(quote(hot) == """
        > @hot [#31](https://www.nodeseek.com/post-1016685-4#31) 发布于2026-11-15 17:00:31
        > 热评第一行
        > 热评第二行
        """)
    }

    @Test func floorPageBoundariesMatchWebRule() {
        let expected: [(floor: Int, page: Int)] = [(0, 1), (1, 1), (10, 1), (11, 2), (20, 2), (21, 3), (100, 10), (101, 11)]
        for item in expected {
            #expect(CommentComposerContentBuilder.commentPage(forFloor: item.floor) == item.page, "floor \(item.floor)")
        }
    }

    // MARK: - Helpers

    private struct SourceComment {
        let id: Int
        let floor: Int
        let author: String
        let markdown: String
        var editedAt: String? = nil
        var hot: Bool = false

        /// 用楼层号生成可预测的发布时间，便于断言标题行。
        var createdAt: String { String(format: "2026-11-15 17:00:%02d", floor % 60) }
    }

    private func pageURL(_ page: Int) -> URL {
        NodeSeekSite.postURL(id: postID, page: page)
    }

    private func parsePage(
        _ page: Int,
        comments: [SourceComment],
        htmlOnlyComments: [SourceComment] = []
    ) throws -> PostDetail {
        let config: [String: Any] = [
            "pageType": "post",
            "postData": [
                "postId": Int(postID)!,
                "postPage": page,
                "comments": comments.map { comment -> [String: Any] in
                    [
                        "commentId": comment.id,
                        "floorIndex": comment.floor,
                        "hot": comment.hot,
                        "markdown": comment.markdown,
                        "poster": ["name": comment.author, "uid": comment.id],
                        "time": [
                            "createdDateFormated": comment.createdAt,
                            "editedDateFormated": comment.editedAt.map { $0 as Any } ?? NSNull()
                        ]
                    ]
                }
            ]
        ]
        let payload = try JSONSerialization.data(withJSONObject: config).base64EncodedString()
        let items = (comments + htmlOnlyComments).map { comment in
            """
            <li class="content-item" id="\(comment.floor)" data-comment-id="\(comment.id)">
              <a class="author-name" href="/space/\(comment.id)">\(comment.author)</a>
              \(comment.hot ? "<span class=\"hot-badge\">热</span>" : "")
              <span class="date-created"><time title="\(comment.createdAt)">刚刚</time></span>
              <a class="floor-link" href="#\(comment.floor)">#\(comment.floor)</a>
              <article class="post-content"><p>渲染后的内容不参与引用</p></article>
            </li>
            """
        }.joined(separator: "\n")
        let html = """
        <div class="post-title"><h1>测试贴</h1></div>
        <div class="nsk-post"><ul class="comments">\(items)</ul></div>
        <script id="temp-script" type="application/json">
            \(payload)
        </script>
        """
        return try KannaNodeSeekParser(baseURL: NodeSeekSite.baseURL)
            .parsePostDetail(html: html, url: pageURL(page))
    }

    private func comment(_ floorText: String, in detail: PostDetail) throws -> QuoteTestComment {
        try #require(detail.comments.first { $0.floorText == floorText })
    }

    private func quote(_ comment: QuoteTestComment, postURL: URL? = nil) -> String {
        CommentComposerContentBuilder.content(
            text: "",
            mode: .quote([comment]),
            postURL: postURL ?? pageURL(1)
        )
    }
}
