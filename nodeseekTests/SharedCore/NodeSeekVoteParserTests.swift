import XCTest
#if SWIFT_PACKAGE
@testable import NodeSeekCore
#else
@testable import nodeseek
#endif

final class NodeSeekVoteParserTests: XCTestCase {
    func testOriginalMarkerPreservesSurroundingContentAndOrder() throws {
        let html = """
        <p>前文 <a href="javascript://void(0)" data-href="nsapp://vote?id=3108">nsapp://vote?id=3108</a> 后文</p>
        <p><img src="/image.png"></p><a href="nsapp://vote?id=42">另一个投票</a>
        """
        let parts = try XCTUnwrap(NodeSeekVoteParser.parts(in: html))
        XCTAssertEqual(ids(parts), [3108, 42])
        XCTAssertTrue(text(parts).contains("前文"))
        XCTAssertTrue(text(parts).contains("后文"))
        XCTAssertTrue(text(parts).contains("/image.png"))
    }

    func testMountedPanelDoesNotDuplicateOptionsOrVote() throws {
        let html = """
        <div class="vote-panel"><div class="embed-vote"><h2>题目</h2>
        <input id="vote-item-3108-14131" type="radio"><label>plus</label>
        <div>nsapp://vote?id=3108 (公开投票)</div></div></div>
        """
        let parts = try XCTUnwrap(NodeSeekVoteParser.parts(in: html))
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(ids(parts), [3108])
    }

    func testMountedPanelCanUseOptionIDWhileFooterIsLoading() throws {
        let parts = try XCTUnwrap(NodeSeekVoteParser.parts(in: "<div class='vote-panel'><input id='vote-item-3108-14131'></div>"))
        XCTAssertEqual(ids(parts), [3108])
    }

    func testKeepsNestedQuoteAndDoesNotInterpretCodeExamples() throws {
        let html = """
        <blockquote><p>引用</p><blockquote><a href="nsapp://vote?id=2">投票</a></blockquote></blockquote>
        <pre><code><a href="nsapp://vote?id=999">示例</a></code></pre>
        """
        let parts = try XCTUnwrap(NodeSeekVoteParser.parts(in: html))
        XCTAssertEqual(ids(parts), [2])
        guard case .quote(let children) = parts.first else { return XCTFail("引用层级应保留") }
        XCTAssertTrue(children.contains { if case .quote = $0 { return true }; return false })
        XCTAssertTrue(text(parts).contains("999"))
    }

    func testPlainTextAndInvalidReferencesAreNotVotes() {
        for html in ["<p>nsapp://vote?id=3108</p>", "<code>nsapp://vote?id=3108</code>", "<a href='nsapp://vote?id=no'>错误</a>", "<div class='vote-panel'>加载中</div>"] {
            XCTAssertNil(NodeSeekVoteParser.parts(in: html), html)
        }
        for value in ["https://vote?id=1", "nsapp://vote?id=-1", "nsapp://vote?id=0", "nsapp://vote?id=1&id=2", "nsapp://vote/path?id=1", "nsapp://vote?id=9007199254740992", "nsapp://vote?id=1.5", "nsapp://user@vote?id=1"] {
            XCTAssertNil(NodeSeekVoteParser.voteID(in: URL(string: value)!), value)
        }
    }

    func testMissingCountsStayUnknownAndSelectionRulesFollowServer() throws {
        let response = try JSONDecoder().decode(NodeSeekVoteResponse.self, from: Data(#"{"success":true,"vote":{"id":3108,"title":"套餐","multiple":false,"isPublic":true,"locked":false,"items":[{"vote_item_id":14131,"text":"plus","voted":false},{"vote_item_id":14132,"text":"pro","voted":false}]}}"#.utf8))
        let vote = try XCTUnwrap(response.vote)
        XCTAssertNil(vote.items[0].count)
        XCTAssertTrue(vote.accepts([14131]))
        XCTAssertFalse(vote.accepts([]))
        XCTAssertFalse(vote.accepts([14131, 14132]))
        XCTAssertFalse(vote.accepts([999]))
    }

    private func ids(_ parts: [NodeSeekVoteParser.Part]) -> [Int] {
        parts.flatMap { part -> [Int] in
            switch part {
            case .html: return []
            case .vote(let id): return [id]
            case .quote(let children): return ids(children)
            }
        }
    }

    private func text(_ parts: [NodeSeekVoteParser.Part]) -> String {
        parts.map { part in
            switch part {
            case .html(let html): return html
            case .vote: return ""
            case .quote(let children): return text(children)
            }
        }.joined()
    }
}
