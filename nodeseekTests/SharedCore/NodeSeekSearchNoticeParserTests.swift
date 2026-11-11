//
//  NodeSeekSearchNoticeParserTests.swift
//  nodeseekTests
//

import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import NodeSeekCore
#else
@testable import nodeseek
#endif

/// HTML 片段按站点 /search 实际返回的结构裁剪（2026-11-10 抓取）。
struct NodeSeekSearchNoticeParserTests {
    private func page(body: String) -> String {
        """
        <html><body><section id="nsk-frame"><div id="nsk-body" class="nsk-container">
        <div id="nsk-left-panel-container"></div>
        <div id="nsk-body-left"><!----> <!----> \(body) <!----> <div id="nsk-body-left-block"></div></div>
        <div id="nsk-right-panel-container"></div>
        </div></section></body></html>
        """
    }

    @Test func extractsQueryTooShortNotice() {
        let html = page(body: """
        <div style="min-height:300px;display:flex;align-items:center;justify-content:center;font-size:2rem;"><div style="line-height: 1.25;">
                搜索词太短😭
            </div></div>
        """)
        #expect(NodeSeekSearchNoticeParser.notice(in: html) == "搜索词太短😭")
    }

    @Test func extractsInvalidCharacterNotice() {
        let html = page(body: """
        <div style="min-height:300px;display:flex;align-items:center;justify-content:center;font-size:2rem;"><div style="line-height: 1.25;"> 搜索词含有违规字符😭 </div></div>
        """)
        #expect(NodeSeekSearchNoticeParser.notice(in: html) == "搜索词含有违规字符😭")
    }

    @Test func extractsNoResultNoticeAndIgnoresPager() {
        let html = page(body: """
        <div style="text-align: center;padding: 50px 0"><span style="font-size: 1.1rem;line-height:36px">未找到有效帖子，请更换搜索词后重试</span><br> <img src="/static/image/empty.svg" alt="empty"></div>
        <ul class="post-list"></ul>
        <div style="padding: 2px 0;display: flex;justify-content: flex-end;"><div class="nsk-pager pager-bottom" style="display:none;"><a href="/search?q=x&amp;page=1" class="pager-pos">1</a></div></div>
        """)
        #expect(NodeSeekSearchNoticeParser.notice(in: html) == "未找到有效帖子，请更换搜索词后重试")
    }

    @Test func returnsNilWhenOnlyPostListAndPager() {
        let html = page(body: """
        <ul class="post-list"><li class="post-list-item">帖子</li></ul>
        <div style="padding: 2px 0;display: flex;justify-content: flex-end;"><div class="nsk-pager pager-bottom"><a href="/search?q=x&amp;page=2" class="pager-pos">2</a></div></div>
        """)
        #expect(NodeSeekSearchNoticeParser.notice(in: html) == nil)
    }
}
