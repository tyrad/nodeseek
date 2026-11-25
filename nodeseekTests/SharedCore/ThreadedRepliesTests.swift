import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import NodeSeekCore
private typealias ThreadTestComment = NodeSeekCore.Comment
private typealias ThreadTestPostDetail = NodeSeekCore.PostDetail
private typealias ThreadTestPagination = NodeSeekCore.PostDetailPagination
private typealias ThreadTestPageItem = NodeSeekCore.PostDetailPageItem
#else
@testable import nodeseek
private typealias ThreadTestComment = nodeseek.Comment
private typealias ThreadTestPostDetail = nodeseek.PostDetail
private typealias ThreadTestPagination = nodeseek.PostDetailPagination
private typealias ThreadTestPageItem = nodeseek.PostDetailPageItem
#endif

struct ThreadedRepliesTests {
    private static let postID = "12000"
    private static let postURL = NodeSeekSite.postURL(id: postID, page: 1)

    // MARK: - Markdown 关系提取

    @Test func extractsComposerRepliesQuotesAndDeduplicatesTargets() {
        let floor3 = Self.makeComment(floor: 3, author: "Mori", markdown: "杭州电信的节点有人测过吗？")
        let floor8 = Self.makeComment(floor: 8, author: "Alice", markdown: "晚高峰测了几次，挺稳的。")
        let floor10 = Self.makeComment(floor: 10, author: "Kero", markdown: "同问")

        let singleReply = CommentComposerContentBuilder.content(
            text: "测过了",
            mode: .reply([floor3]),
            postURL: Self.postURL
        )
        #expect(CommentReplyRelationParser.extractTargets(from: singleReply, postID: Self.postID, currentFloor: 12) == [3])

        let multiReply = CommentComposerContentBuilder.content(
            text: "一起回复",
            mode: .reply([floor3, floor8]),
            postURL: Self.postURL
        )
        #expect(CommentReplyRelationParser.extractTargets(from: multiReply, postID: Self.postID, currentFloor: 12) == [3, 8])

        let combined = CommentComposerContentBuilder.content(
            text: "既引用又回复同一楼",
            mode: .combined(replies: [floor8, floor10], quotes: [floor3, floor8]),
            postURL: Self.postURL
        )
        #expect(CommentReplyRelationParser.extractTargets(from: combined, postID: Self.postID, currentFloor: 15) == [3, 8, 10])

        let newlineSeparated = "@Mori [#3](/post-12000-9#3)\n@Alice [#8](/post-12000-1#8)\n谢谢"
        #expect(CommentReplyRelationParser.extractTargets(from: newlineSeparated, postID: Self.postID, currentFloor: 15) == [3, 8])
    }

    @Test func ignoresNestedQuotesBodyLinksCodeAndPlainMentions() {
        let nestedQuote = """
        > @Kero [#15](/post-12000-2#15) 发布于2026-11-15 17:00:15
        > > @Alice [#8](/post-12000-1#8) 发布于2026-11-15 17:00:08
        > > 晚高峰测了几次，挺稳的。
        >
        > 有延迟数据吗？

        刚测是 18ms。顺便看看 [#3](/post-12000-1#3) 和 `@Mori [#3](/post-12000-1#3)`

        ```markdown
        @Mori [#3](/post-12000-1#3) 代码块不算
        ```
        """
        #expect(CommentReplyRelationParser.extractTargets(from: nestedQuote, postID: Self.postID, currentFloor: 18) == [15])

        let bodyOnly = "正文里提到 @Mori [#3](/post-12000-1#3) 不应建边"
        #expect(CommentReplyRelationParser.extractTargets(from: bodyOnly, postID: Self.postID, currentFloor: 18).isEmpty)

        let codeOnly = "`@Mori [#3](/post-12000-1#3)`"
        #expect(CommentReplyRelationParser.extractTargets(from: codeOnly, postID: Self.postID, currentFloor: 18).isEmpty)

        let mentionOnly = "@Mori 你好"
        #expect(CommentReplyRelationParser.extractTargets(from: mentionOnly, postID: Self.postID, currentFloor: 18).isEmpty)
    }

    @Test func skipsInvalidTargetsWhileKeepingValidLeadingPrefixes() {
        let mixed = [
            "@OtherPost [#3](https://www.nodeseek.com/post-99999-1#3)",
            "@External [#4](https://example.com/post-12000-1#4)",
            "@BadAnchor [#5](/post-12000-1#abc)",
            "@Mismatch [#6](/post-12000-1#7)",
            "@Self [#15](/post-12000-2#15)",
            "@Future [#20](/post-12000-2#20)",
            "@Valid [#8](/post-12000-1#8)",
            "确认有效"
        ].joined(separator: " ")

        #expect(CommentReplyRelationParser.extractTargets(from: mixed, postID: Self.postID, currentFloor: 15) == [8])
    }

    @Test func stripsRedundantParentQuoteAndPrefixAndFallsBackWhenEmpty() {
        let quoted = """
        > @Kero [#15](/post-12000-2#15) 发布于2026-11-15 17:00:15
        > > @Alice [#8](/post-12000-1#8) 发布于2026-11-15 17:00:08
        > > 晚高峰测了几次，挺稳的。
        >
        > 有延迟数据吗？

        刚测是 18ms。
        """
        #expect(
            CommentReplyRelationParser.displayMarkdown(
                from: quoted,
                parentFloor: 15,
                postID: Self.postID,
                currentFloor: 18
            ) == "刚测是 18ms。"
        )

        let prefixed = "@Mori [#3](/post-12000-1#3) 晚高峰测了几次，挺稳的。"
        #expect(
            CommentReplyRelationParser.displayMarkdown(
                from: prefixed,
                parentFloor: 3,
                postID: Self.postID,
                currentFloor: 8
            ) == "晚高峰测了几次，挺稳的。"
        )

        let quoteOnly = "> @Mori [#3](/post-12000-1#3) 发布于2026-11-15 17:00:03\n> 仅引用无正文"
        #expect(
            CommentReplyRelationParser.displayMarkdown(
                from: quoteOnly,
                parentFloor: 3,
                postID: Self.postID,
                currentFloor: 8
            ) == quoteOnly
        )
    }

    @Test func pureMarkdownDocumentNeverFallsBackToHTML() {
        let unsupportedCheckbox = "- [x] 已完成"
        let document = CommentReplyRelationParser.pureMarkdownDocument(from: unsupportedCheckbox)
        #expect(document.blocks == [.paragraph([.text("- [x] 已完成", [], nil)])])
    }

    // MARK: - 三页固定样本与索引聚合

    @Test func threePageFixtureBuildsExpectedTreeProgressively() {
        let pages = Self.makeThreePageFixture()
        var index = ThreadedReplyIndex(postID: Self.postID)

        index.ingest(pages[0])
        let afterPage1 = index.tree(forRootFloor: 3)
        #expect(afterPage1.nodes.map(\.floor) == [8])
        #expect(afterPage1.isComplete == false)
        #expect(afterPage1.totalPages == 3)
        #expect(index.nextPageToScan(forRootFloor: 3) == 2)

        index.ingest(pages[1])
        let afterPage2 = index.tree(forRootFloor: 3)
        #expect(afterPage2.nodes.map(\.floor) == [8, 15, 18])
        #expect(afterPage2.isComplete == false)
        #expect(index.nextPageToScan(forRootFloor: 3) == 3)

        index.ingest(pages[2])
        let afterPage3 = index.tree(forRootFloor: 3)
        #expect(afterPage3.nodes.map(\.floor) == [8, 15, 18, 23, 27])
        #expect(afterPage3.nodes.map(\.depth) == [1, 2, 3, 1, 2])
        #expect(afterPage3.replyCount == 5)
        #expect(afterPage3.isComplete)
        #expect(index.nextPageToScan(forRootFloor: 3) == nil)

        let tree8 = index.tree(forRootFloor: 8)
        #expect(tree8.ancestors.map(\.floor) == [3])
        #expect(tree8.rootDisplayedParentFloor == 3)
        #expect(tree8.nodes.map(\.floor) == [15, 18])

        let tree15 = index.tree(forRootFloor: 15)
        #expect(tree15.ancestors.map(\.floor) == [3, 8])
        #expect(tree15.ancestors.map(\.parentFloorInChain) == [nil, 3])
        #expect(tree15.rootDisplayedParentFloor == 8)
        #expect(tree15.nodes.map(\.floor) == [18])
        #expect(tree15.replyCount == 1)

        let tree9 = index.tree(forRootFloor: 9)
        #expect(tree9.ancestors.isEmpty)
        #expect(tree9.nodes.map(\.floor) == [19])

        let leafTree = index.tree(forRootFloor: 27)
        #expect(leafTree.ancestors.map(\.floor) == [3, 23])
        #expect(leafTree.rootDisplayedParentFloor == 23)
        #expect(leafTree.nodes.isEmpty)
        #expect(leafTree.isComplete)
    }

    @Test func missingAncestorPageIsPrioritizedAndDeletedAncestorDoesNotLoop() {
        let pages = Self.makeThreePageFixture()
        var index = ThreadedReplyIndex(postID: Self.postID)

        // 仅加载第 2 页时，#15 回复第 1 页的 #8 -> 优先补查第 1 页
        index.ingest(pages[1])
        #expect(index.nextMissingAncestorPage(forRootFloor: 15) == 1)
        #expect(index.nextPageToScan(forRootFloor: 15) == 1)
        // 无上游父楼的 #12 直接向后扫第 3 页
        #expect(index.nextMissingAncestorPage(forRootFloor: 12) == nil)
        #expect(index.nextPageToScan(forRootFloor: 12) == 3)

        // 若第 1 页已扫描完成但 #8 已被删除，不再反复请求第 1 页
        let page1WithoutFloor8 = Self.makePage(
            page: 1,
            totalPages: 3,
            nextPage: 2,
            comments: pages[0].comments.filter { $0.anchorID != "8" }
        )
        index.ingest(page1WithoutFloor8)
        #expect(index.nextMissingAncestorPage(forRootFloor: 15) == nil)
        #expect(index.nextPageToScan(forRootFloor: 15) == 3)
    }

    @Test func doesNotUseHTMLWhenMarkdownIsMissingAndIgnoresRestrictedPage() {
        let htmlOnlyReply = Self.makeComment(
            floor: 8,
            author: "Alice",
            markdown: nil,
            html: #"<p><a href="/post-12000-1#3">#3</a> HTML 链接不应建边</p>"#
        )
        let normalWithVisibleFalse = Self.makeComment(
            floor: 9,
            author: "Bob",
            markdown: "@Mori [#3](/post-12000-1#3) hasVisibleMarkdown 为 false 也应建边",
            hasVisibleMarkdown: false
        )
        let page1 = Self.makePage(
            page: 1,
            totalPages: 1,
            comments: [Self.makeComment(floor: 3, author: "Mori", markdown: "提问"), htmlOnlyReply, normalWithVisibleFalse]
        )

        var index = ThreadedReplyIndex(postID: Self.postID)
        let ingestedPage1 = index.ingest(page1)
        #expect(ingestedPage1)
        #expect(index.tree(forRootFloor: 3).nodes.map(\.floor) == [9])

        let restricted = ThreadTestPostDetail(
            id: Self.postID,
            title: "受限",
            authorName: "op",
            avatarURL: nil,
            metadataText: nil,
            contentHTML: "权限不足",
            isRestricted: true,
            comments: [Self.makeComment(floor: 10, author: "Leak", markdown: "@Mori [#3](/post-12000-1#3) 不得泄露")],
            page: 1,
            totalPages: 1
        )
        let ingestedRestricted = index.ingest(restricted)
        #expect(ingestedRestricted == false)
        #expect(index.tree(forRootFloor: 3).nodes.map(\.floor) == [9])
    }

    @Test func outOfOrderDeliveryAndHotCommentDropPreservePrimaryFloor() {
        let pages = Self.makeThreePageFixture()
        var index = ThreadedReplyIndex(postID: Self.postID)

        // 先交付第 3 页再交付第 1 页（第 1 页含无原文的 #23 热评副本）
        index.ingest(pages[2])
        index.ingest(pages[0])
        index.ingest(pages[1])
        index.ingest(pages[0]) // 重复交付同页

        let tree = index.tree(forRootFloor: 3)
        #expect(tree.nodes.map(\.floor) == [8, 15, 18, 23, 27])
        #expect(index.comment(forFloor: 23)?.markdown?.contains("杭州节点") == true)

        // 模拟第 1 页刷新后 #23 热评掉榜，不应删掉第 3 页正式的 #23
        let page1WithoutHot = Self.makePage(
            page: 1,
            totalPages: 3,
            nextPage: 2,
            comments: pages[0].comments.filter { !$0.isHot }
        )
        index.ingest(page1WithoutHot)
        #expect(index.tree(forRootFloor: 3).nodes.map(\.floor) == [8, 15, 18, 23, 27])
    }

    @Test func pageRefreshReplacesEditedEdgeAndRemovesDeletedFloor() {
        let pages = Self.makeThreePageFixture()
        var index = ThreadedReplyIndex(postID: Self.postID)
        pages.forEach { _ = index.ingest($0) }

        // 将 #18 从回复 #15 改为回复 #9，并删除 #19
        var editedPage2Comments = pages[1].comments.filter { $0.anchorID != "19" }
        editedPage2Comments = editedPage2Comments.map { comment in
            guard comment.anchorID == "18" else { return comment }
            return Self.makeComment(floor: 18, author: "Alice", markdown: "@Other [#9](/post-12000-1#9) 改成回复 9 楼")
        }
        let refreshedPage2 = Self.makePage(page: 2, totalPages: 3, nextPage: 3, comments: editedPage2Comments)
        index.ingest(refreshedPage2)

        #expect(index.tree(forRootFloor: 15).nodes.isEmpty)
        #expect(index.tree(forRootFloor: 9).nodes.map(\.floor) == [18])
        #expect(index.comment(forFloor: 19) == nil)
    }

    @Test func multiParentDeduplicatesUnderAncestorAndCapsVisualDepthAtThree() {
        let page1 = Self.makePage(
            page: 1,
            totalPages: 1,
            comments: [
                Self.makeComment(floor: 3, author: "Mori", markdown: "根"),
                Self.makeComment(floor: 4, author: "A", markdown: "@Mori [#3](/post-12000-1#3) 一级"),
                Self.makeComment(floor: 5, author: "B", markdown: "@A [#4](/post-12000-1#4) 二级"),
                Self.makeComment(floor: 6, author: "C", markdown: "@B [#5](/post-12000-1#5) 三级"),
                Self.makeComment(floor: 7, author: "D", markdown: "@C [#6](/post-12000-1#6) 四级"),
                Self.makeComment(floor: 8, author: "E", markdown: "@Mori [#3](/post-12000-1#3) 另一分支"),
                Self.makeComment(floor: 9, author: "F", markdown: "@A [#4](/post-12000-1#4) @E [#8](/post-12000-1#8) 同时回 4 和 8")
            ]
        )
        var index = ThreadedReplyIndex(postID: Self.postID)
        index.ingest(page1)

        let treeFrom3 = index.tree(forRootFloor: 3)
        #expect(treeFrom3.nodes.map(\.floor) == [4, 5, 6, 7, 9, 8])
        #expect(treeFrom3.replyCount == 6)
        let node7 = treeFrom3.nodes.first { $0.floor == 7 }
        #expect(node7?.depth == 4)
        #expect(node7?.visualDepth == 3)
        #expect(node7?.showsParentBadge == true)
        #expect(node7?.parentFloor == 6)

        // 换根到 4 和 8，都能各自看到 9
        #expect(index.tree(forRootFloor: 4).nodes.map(\.floor).contains(9))
        #expect(index.tree(forRootFloor: 8).nodes.map(\.floor) == [9])
    }

    @Test func parserExposesPostPageCountAsTotalPages() throws {
        let parsed = try CommentQuotePageFixture.parsePage(
            2,
            pageCount: 12,
            comments: [.init(id: 90011, floor: 11, author: "alice", markdown: "第 2 页")]
        )
        #expect(parsed.totalPages == 12)
    }

    @Test func ingestingSubsequentPagesDoesNotReparseEarlierPages() {
        let pages = Self.makeThreePageFixture()
        final class Counter: @unchecked Sendable {
            var callsByFloor: [Int: Int] = [:]
        }
        let counter = Counter()
        let extractor: ThreadedReplyIndex.TargetExtractor = { markdown, postID, floor, baseURL in
            counter.callsByFloor[floor, default: 0] += 1
            return CommentReplyRelationParser.extractTargets(
                from: markdown,
                postID: postID,
                currentFloor: floor,
                baseURL: baseURL
            )
        }

        var index = ThreadedReplyIndex(postID: Self.postID)
        _ = index.ingest(pages[0], targetExtractor: extractor)
        let page1CountsAfterFirst = counter.callsByFloor

        _ = index.ingest(pages[1], targetExtractor: extractor)
        _ = index.ingest(pages[2], targetExtractor: extractor)

        // 写入第 2、3 页后，第 1 页的楼层绝不重复解析
        for (floor, count) in page1CountsAfterFirst where floor <= 10 {
            #expect(counter.callsByFloor[floor] == count)
        }
        #expect(index.tree(forRootFloor: 3).nodes.map(\.floor) == [8, 15, 18, 23, 27])
    }

    @Test func unrelatedMultiParentAncestorsDisconnectVerticalGuide() {
        let page1 = Self.makePage(
            page: 1,
            totalPages: 1,
            comments: [
                Self.makeComment(floor: 3, author: "A", markdown: "话题一"),
                Self.makeComment(floor: 5, author: "B", markdown: "互不相关的话题二"),
                Self.makeComment(floor: 10, author: "C", markdown: "@A [#3](/post-12000-1#3) @B [#5](/post-12000-1#5) 同时回复两楼")
            ]
        )
        var index = ThreadedReplyIndex(postID: Self.postID)
        _ = index.ingest(page1)

        let tree10 = index.tree(forRootFloor: 10)
        #expect(tree10.ancestors.map(\.floor) == [3, 5])
        #expect(tree10.ancestors[0].connectsFromPrevious == false)
        #expect(tree10.ancestors[0].connectsToNext == false)
        #expect(tree10.ancestors[1].connectsFromPrevious == false)
        #expect(tree10.ancestors[1].connectsToNext == true)
        #expect(tree10.rootConnectsFromTop == true)
    }

    // MARK: - 固定样本构造

    private static func makeThreePageFixture() -> [ThreadTestPostDetail] {
        let hot23Copy = ThreadTestComment(
            id: "90023",
            anchorID: "23",
            authorName: "Nova",
            avatarURL: nil,
            floorText: "#23",
            createdAtText: "1 分钟前",
            contentHTML: "<p>热评副本</p>",
            isHot: true,
            markdown: nil,
            hasVisibleMarkdown: false
        )
        let page1Comments: [ThreadTestComment] = [hot23Copy] + (1...10).map { floor in
            switch floor {
            case 3:
                return makeComment(floor: 3, author: "Mori", markdown: "杭州电信的节点有人测过吗？")
            case 8:
                return makeComment(floor: 8, author: "Alice", markdown: "@Mori [#3](/post-12000-1#3) 晚高峰测了几次，挺稳的。")
            case 9:
                return makeComment(floor: 9, author: "Liam", markdown: "另一段讨论起点")
            default:
                return makeComment(floor: floor, author: "User\(floor)", markdown: "普通正文 \(floor)")
            }
        }
        let page2Comments: [ThreadTestComment] = (11...20).map { floor in
            switch floor {
            case 15:
                return makeComment(floor: 15, author: "Kero", markdown: "@Alice [#8](/post-12000-1#8) 有延迟数据吗？")
            case 18:
                let md = """
                > @Kero [#15](/post-12000-2#15) 发布于2026-11-15 17:00:15
                > > @Alice [#8](/post-12000-1#8) 发布于2026-11-15 17:00:08
                > > 晚高峰测了几次，挺稳的。
                >
                > 有延迟数据吗？

                刚测是 18ms。
                """
                return makeComment(floor: 18, author: "Alice", markdown: md)
            case 19:
                return makeComment(floor: 19, author: "Zoe", markdown: "@Liam [#9](/post-12000-1#9) 同意")
            default:
                return makeComment(floor: floor, author: "User\(floor)", markdown: "普通正文 \(floor)")
            }
        }
        let page3Comments: [ThreadTestComment] = (21...27).map { floor in
            switch floor {
            case 23:
                return makeComment(floor: 23, author: "Nova", markdown: "@Mori [#3](/post-12000-1#3) 我刚补了一个杭州节点。")
            case 27:
                return makeComment(floor: 27, author: "Mori", markdown: "@Nova [#23](/post-12000-3#23) 收到了，这个也通了。")
            default:
                return makeComment(floor: floor, author: "User\(floor)", markdown: "普通正文 \(floor)")
            }
        }
        return [
            makePage(page: 1, totalPages: 3, nextPage: 2, comments: page1Comments),
            makePage(page: 2, totalPages: 3, nextPage: 3, comments: page2Comments),
            makePage(page: 3, totalPages: 3, nextPage: nil, comments: page3Comments)
        ]
    }

    private static func makeComment(
        floor: Int,
        author: String,
        markdown: String?,
        html: String = "<p>rendered</p>",
        hasVisibleMarkdown: Bool = true
    ) -> ThreadTestComment {
        ThreadTestComment(
            id: "\(90000 + floor)",
            anchorID: "\(floor)",
            authorName: author,
            avatarURL: nil,
            floorText: "#\(floor)",
            createdAtText: "刚刚",
            contentHTML: html,
            markdown: markdown,
            hasVisibleMarkdown: hasVisibleMarkdown
        )
    }

    private static func makePage(
        page: Int,
        totalPages: Int,
        nextPage: Int? = nil,
        comments: [ThreadTestComment]
    ) -> ThreadTestPostDetail {
        let items = (1...totalPages).map { number in
            ThreadTestPageItem(page: number, url: NodeSeekSite.postURL(id: postID, page: number), isCurrent: number == page)
        }
        let pagination = totalPages > 1
            ? ThreadTestPagination(
                currentPage: page,
                items: items,
                previousPage: page > 1 ? page - 1 : nil,
                nextPage: nextPage
            )
            : nil
        return ThreadTestPostDetail(
            id: postID,
            title: "测试贴",
            authorName: "OP",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>主楼</p>",
            comments: comments,
            page: page,
            pagination: pagination,
            isLastPage: nextPage == nil,
            totalPages: totalPages
        )
    }
}
