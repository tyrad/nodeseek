//
//  KannaNodeSeekParserTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/4/27.
//

import Foundation
import Testing
@testable import nodeseek

private final class FixtureToken {}

enum FixtureLoader {
    static func html(named name: String) throws -> String {
        let bundle = Bundle(for: FixtureToken.self)
        let url = try #require(bundle.url(forResource: name, withExtension: "html"))
        return try String(contentsOf: url, encoding: .utf8)
    }
}

struct KannaNodeSeekParserTests {
    @Test func parsesAccountFromRightPanelUserCard() throws {
        let html = """
        <div id="nsk-right-panel-container">
            <div class="user-card">
                <div class="user-head">
                    <a title="缭雾" href="/space/31037">
                        <img src="/avatar/31037.png" alt="缭雾" class="avatar-normal skeleton">
                    </a>
                    <div class="menu">
                        <a href="/space/31037" class="Username">缭雾</a>
                    </div>
                </div>
                <div class="user-stat">
                    <div class="stat-block">
                        <div><a href="/progress"><span>等级 Lv 1</span></a></div>
                        <div><a href="/credit"><span>鸡腿 306</span></a></div>
                        <div><a href="/stardust/list?member_id=31037"><span>星辰 2</span></a></div>
                    </div>
                </div>
            </div>
        </div>
        """
        let parser = KannaNodeSeekParser(baseURL: URL(string: "https://www.nodeseek.com")!)

        let account = try parser.parseAccount(html: html)

        #expect(account.isLoggedIn)
        #expect(account.displayName == "缭雾")
        #expect(account.avatarURL?.absoluteString == "https://www.nodeseek.com/avatar/31037.png")
        #expect(account.profileURL?.absoluteString == "https://www.nodeseek.com/space/31037")
        #expect(account.stats == ["等级 Lv 1", "鸡腿 306", "星辰 2"])
    }

    @Test func parsesGuestAccountWhenRightPanelHasNoUserCard() throws {
        let parser = KannaNodeSeekParser(baseURL: URL(string: "https://www.nodeseek.com")!)

        let account = try parser.parseAccount(html: "<div id=\"nsk-right-panel-container\"></div>")

        #expect(!account.isLoggedIn)
        #expect(account.displayName == "游客")
        #expect(account.avatarURL == nil)
        #expect(account.stats.isEmpty)
    }

    @Test func parsesPostListFixture() throws {
        let html = try FixtureLoader.html(named: "post-list-basic")
        let parser = KannaNodeSeekParser(baseURL: URL(string: "https://www.nodeseek.com")!)

        let posts = try parser.parsePostList(html: html)

        let post = try #require(posts.first)
        #expect(posts.count == 1)
        #expect(post.id == "123")
        #expect(post.title == "测试帖子")
        #expect(post.url.absoluteString == "https://www.nodeseek.com/post-123")
        #expect(post.authorName == "mist")
        #expect(post.nodeName == "VPS")
        #expect(post.replyCount == 2)
        #expect(post.lastActivityText == "1 分钟前")
        #expect(post.avatarURL == nil)
    }

    @Test func parsesPostListFromPostLinksWhenClassNamesChange() throws {
        let html = try FixtureLoader.html(named: "post-list-link-fallback")
        let parser = KannaNodeSeekParser(baseURL: URL(string: "https://www.nodeseek.com")!)

        let posts = try parser.parsePostList(html: html)

        let post = try #require(posts.first)
        #expect(posts.count == 1)
        #expect(post.id == "456")
        #expect(post.title == "没有标准 class 的标题")
        #expect(post.url.absoluteString == "https://www.nodeseek.com/post-456")
        #expect(post.authorName == "alice")
        #expect(post.nodeName == "日常")
        #expect(post.replyCount == 12)
        #expect(post.lastActivityText == "2 小时前")
        #expect(post.avatarURL == nil)
    }

    @Test func parsesPinnedPostListItemFromTitleIcon() throws {
        let html = """
        <ul class="post-list">
            <li class="post-list-item">
                <div class="post-list-content">
                    <div role="heading" aria-level="3" class="post-title">
                        <a href="/post-1033-1" target="">[小白入门科普] 服务器行业黑话大全 持续更新中.......</a>
                        <a href="/award" title="推荐阅读">
                            <svg class="iconpark-icon award" style="width:15px;height:15px"><use href="#diamonds"></use></svg>
                        </a>
                        <span title="置顶">
                            <svg class="iconpark-icon pined circle-icon" style="width:15px;height:15px"><use href="#pin"></use></svg>
                        </span>
                    </div>
                    <div class="post-info">
                        <span class="info-item info-author"><a href="/space/1769">斯巴达</a></span>
                        <span class="info-item info-views"><span title="169842 views">169842</span></span>
                        <span title="2403 comments" class="info-item info-comments-count"><span title="2404 comments">2403</span></span>
                        <a href="/post-1033-241#2403" class="info-item info-last-comment-time">
                            <time title="2026-04-29 08:25:40" datetime="2026-04-29T00:25:40.000Z">7h 32min ago</time>
                        </a>
                        <a href="/categories/daily" class="info-item post-category">日常</a>
                    </div>
                </div>
            </li>
        </ul>
        """
        let parser = KannaNodeSeekParser(baseURL: URL(string: "https://www.nodeseek.com")!)

        let posts = try parser.parsePostList(html: html)

        let post = try #require(posts.first)
        #expect(post.id == "1033")
        #expect(post.isPinned)
        #expect(!post.isLocked)
        #expect(post.title.contains("服务器行业黑话大全"))
        #expect(post.authorName == "斯巴达")
        #expect(post.nodeName == "日常")
        #expect(post.replyCount == 2403)
        #expect(post.viewCount == 169842)
        #expect(post.lastActivityText == "7h 32min ago")
    }

    @Test func parsesRealPageOneFixture() throws {
        let html = try FixtureLoader.html(named: "page-1")
        let parser = KannaNodeSeekParser(baseURL: URL(string: "https://www.nodeseek.com")!)

        let posts = try parser.parsePostList(html: html)

        let first = try #require(posts.first)
        #expect(posts.count > 20)
        #expect(first.id == "703692")
        #expect(first.title.contains("115非VIP账号海外上传速度如何"))
        #expect(first.authorName == "橘子海")
        #expect(first.nodeName == "日常")
        #expect(first.replyCount == 4)
        #expect(first.viewCount == 39)
        #expect(first.isLocked)
        #expect(first.lastActivityText == "24s ago")
        #expect(first.avatarURL?.path == "/avatar/17843.png")

        let unlockedPost = try #require(posts.dropFirst().first)
        #expect(unlockedPost.id == "703691")
        #expect(unlockedPost.viewCount == 45)
        #expect(!unlockedPost.isLocked)
    }

    @Test func parsesPostDetailFixture() throws {
        let html = try FixtureLoader.html(named: "post-703863-1")
        let parser = KannaNodeSeekParser(baseURL: URL(string: "https://www.nodeseek.com")!)

        let detail = try parser.parsePostDetail(
            html: html,
            url: URL(string: "https://www.nodeseek.com/post-703863-1")!
        )

        #expect(detail.id == "703863")
        #expect(detail.title == "绿云抢鸡竞赛又要开始了，一波传家宝又要来袭")
        #expect(detail.authorName == "ipv4")
        #expect(detail.avatarURL?.path == "/avatar/34378.png")
        #expect(detail.metadataText == "36min ago · 日常")
        #expect(detail.contentHTML.contains("cdn.nodeimage.com"))
        #expect(detail.contentHTML.contains("喊上你的五指小姐姐一起抢吧"))
        #expect(detail.comments.count == 10)
        #expect(detail.comments.first?.id == "9727591")
        #expect(detail.comments.first?.authorName == "ggbeng")
        #expect(detail.comments.first?.avatarURL?.path == "/avatar/24520.png")
        #expect(detail.comments.first?.floorText == "#4")
        #expect(detail.comments.first?.createdAtText == "34min ago")
        #expect(detail.comments.first?.contentHTML.contains("CPU限制30%") == true)
    }

    @Test func parsesMagicTabsDetailFixtureWithANSIAndImageTabs() throws {
        let html = try FixtureLoader.html(named: "post-705039-1")
        let parser = KannaNodeSeekParser(baseURL: URL(string: "https://www.nodeseek.com")!)

        let detail = try parser.parsePostDetail(
            html: html,
            url: URL(string: "https://www.nodeseek.com/post-705039-1")!
        )

        #expect(detail.id == "705039")
        #expect(detail.contentHTML.contains("nsk-magic-tabs"))
        #expect(detail.contentHTML.contains("language-ansi"))
        #expect(detail.contentHTML.contains("https://i.111666.best/image/G9D5ncG5qndySgQtNwvFq4.webp"))
        #expect(detail.contentHTML.contains("https://i.111666.best/image/noEhdCSyuAeuREqqSWgdY5.webp"))
    }
}
