//
//  KannaNodeSeekParserTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/4/27.
//

import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import NodeSeekCore
#else
@testable import nodeseek
#endif

private final class FixtureToken {}

enum FixtureLoader {
    static func html(named name: String) throws -> String {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        let url = try #require(bundle.url(forResource: name, withExtension: "html", subdirectory: "Fixtures"))
        #else
        let bundle = Bundle(for: FixtureToken.self)
        let url = try #require(bundle.url(forResource: name, withExtension: "html"))
        #endif
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

    @Test func parsesAccountFromTempScriptWhenRightPanelIsSkeleton() throws {
        let accountJSON = """
        {
          "user": {
            "member_id": 31037,
            "member_name": "缭雾",
            "rank": 1,
            "coin": 330,
            "stardust": 2
          }
        }
        """
        let payload = Data(accountJSON.utf8).base64EncodedString()
        let html = """
        <div id="nsk-right-panel-container">
            <div id="usercard-me" class="skeleton" style="height: 146px; margin-bottom: 10px"></div>
        </div>
        <script id="temp-script" type="application/json">\(payload)</script>
        """
        let parser = KannaNodeSeekParser(baseURL: URL(string: "https://www.nodeseek.com")!)

        let account = try parser.parseAccount(html: html)

        #expect(account.isLoggedIn)
        #expect(account.displayName == "缭雾")
        #expect(account.avatarURL?.absoluteString == "https://www.nodeseek.com/avatar/31037.png")
        #expect(account.profileURL?.absoluteString == "https://www.nodeseek.com/space/31037")
        #expect(account.stats == ["等级 Lv 1", "鸡腿 330", "星辰 2"])
    }

    @Test func parsesAccountFromTempScriptWithoutSkeletonUserCard() throws {
        let accountJSON = """
        {
          "user": {
            "member_id": 31037,
            "member_name": "缭雾",
            "rank": 1,
            "coin": 330,
            "stardust": 2
          }
        }
        """
        let payload = Data(accountJSON.utf8).base64EncodedString()
        let html = """
        <div id="nsk-right-panel-container"></div>
        <script id="temp-script" type="application/json">\(payload)</script>
        """
        let parser = KannaNodeSeekParser(baseURL: URL(string: "https://www.nodeseek.com")!)

        let account = try parser.parseAccount(html: html)

        #expect(account.isLoggedIn)
        #expect(account.displayName == "缭雾")
        #expect(account.avatarURL?.absoluteString == "https://www.nodeseek.com/avatar/31037.png")
        #expect(account.profileURL?.absoluteString == "https://www.nodeseek.com/space/31037")
        #expect(account.stats == ["等级 Lv 1", "鸡腿 330", "星辰 2"])
    }

    @Test func parsesAccountFromCapturedWebViewConfig() throws {
        let html = """
        <script id="nodeseek-captured-config" type="application/json">
        {
          "user": {
            "member_id": 31037,
            "member_name": "缭雾",
            "rank": 1,
            "coin": 330,
            "stardust": 2
          }
        }
        </script>
        """
        let parser = KannaNodeSeekParser(baseURL: URL(string: "https://www.nodeseek.com")!)

        let account = try parser.parseAccount(html: html)

        #expect(account.isLoggedIn)
        #expect(account.displayName == "缭雾")
        #expect(account.avatarURL?.absoluteString == "https://www.nodeseek.com/avatar/31037.png")
        #expect(account.profileURL?.absoluteString == "https://www.nodeseek.com/space/31037")
        #expect(account.stats == ["等级 Lv 1", "鸡腿 330", "星辰 2"])
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

    @Test func parsesMissingPostListAuthorAsEmpty() throws {
        let html = """
        <ul class="post-list">
            <li class="post-list-item">
                <div class="post-list-content">
                    <div role="heading" aria-level="3" class="post-title">
                        <a href="/post-789-1">缺少作者的帖子</a>
                    </div>
                    <div class="post-info">
                        <span class="info-item info-views"><span title="45 views">45</span></span>
                        <span title="3 comments" class="info-item info-comments-count"><span title="4 comments">3</span></span>
                        <a href="/post-789-1#3" class="info-item info-last-comment-time">
                            <time title="2026-04-29 13:46:24">32s ago</time>
                        </a>
                    </div>
                </div>
            </li>
        </ul>
        """
        let parser = KannaNodeSeekParser(baseURL: URL(string: "https://www.nodeseek.com")!)

        let post = try #require(try parser.parsePostList(html: html).first)

        #expect(post.authorName.isEmpty)
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
        #expect(detail.authorProfileURL?.absoluteString == "https://www.nodeseek.com/space/34378#/general")
        #expect(detail.metadataText == "36min ago · 日常")
        #expect(detail.contentHTML.contains("cdn.nodeimage.com"))
        #expect(detail.contentHTML.contains("喊上你的五指小姐姐一起抢吧"))
        #expect(detail.comments.count == 10)
        #expect(detail.comments.first?.id == "9727591")
        #expect(detail.comments.first?.authorName == "ggbeng")
        #expect(detail.comments.first?.avatarURL?.path == "/avatar/24520.png")
        #expect(detail.comments.first?.authorProfileURL?.absoluteString == "https://www.nodeseek.com/space/24520#/general")
        #expect(detail.comments.first?.floorText == "#4")
        #expect(detail.comments.first?.createdAtText == "34min ago")
        #expect(detail.comments.first?.createdAtTitleText == "2026-04-27 15:58:51")
        #expect(detail.comments.first?.contentHTML.contains("CPU限制30%") == true)
        #expect(detail.isLastPage == false)
    }

    @Test func parsesLoginRequiredNoticeFromBodyLeftFallback() throws {
        let html = """
        <body class="bg1 light-layout">
            <header></header>
            <section id="nsk-frame">
                <div id="nsk-body" class="nsk-container">
                    <div id="nsk-body-left">
                        <div style="min-height:300px;display:flex;align-items:center;justify-content:center;font-size:2rem;">
                            <div style="line-height: 1.25;"> 本帖需要注册用户才能查看😭 </div>
                        </div>
                    </div>
                </div>
                <div id="search-panel-mount"></div>
            </section>
            <title>受限帖子 - NodeSeek</title>
        </body>
        """
        let parser = KannaNodeSeekParser(baseURL: URL(string: "https://www.nodeseek.com")!)

        let detail = try parser.parsePostDetail(
            html: html,
            url: URL(string: "https://www.nodeseek.com/post-704286-1")!
        )

        #expect(detail.id == "704286")
        #expect(detail.title == "受限帖子 - NodeSeek")
        #expect(detail.contentHTML == "本帖需要注册用户才能查看😭")
        #expect(detail.comments.isEmpty)
    }

    @Test func parsesPostDetailPaginationFromFixture() throws {
        let html = try FixtureLoader.html(named: "post-703863-1")
        let parser = KannaNodeSeekParser(baseURL: URL(string: "https://www.nodeseek.com")!)

        let detail = try parser.parsePostDetail(
            html: html,
            url: URL(string: "https://www.nodeseek.com/post-703863-1")!
        )

        let pagination = try #require(detail.pagination)
        #expect(detail.page == 1)
        #expect(pagination.currentPage == 1)
        #expect(pagination.previousPage == nil)
        #expect(pagination.nextPage == 2)
        #expect(pagination.items.map(\.page) == [1, 2, 3, 4])
        #expect(pagination.items.first?.isCurrent == true)
        #expect(pagination.items.dropFirst().first?.isCurrent == false)
        #expect(pagination.items.dropFirst().first?.url?.path == "/post-703863-2")
    }

    @Test func parsesPostDetailLaterPageWithoutPostBody() throws {
        let html = """
        <div class="nsk-post-wrapper">
            <div class="nsk-post">
                <div class="post-title">
                    <h1><a href="/post-706714-1" class="post-title-link">一周内第五个龟壳到手，圣何塞区</a></h1>
                </div>
            </div>
            <div class="comment-container">
                <div class="nsk-pager post-top-pager">
                    <div role="navigation" aria-label="pagination">
                        <a href="/post-706714-1" rel="prev" class="pager-prev"><div class="triangle-left"></div></a>
                        <a href="/post-706714-1" aria-label="page1" class="pager-pos">1</a>
                        <span href="/post-706714-2" aria-label="page2" aria-current="page" class="pager-pos pager-cur">2</span>
                        <a href="/post-706714-3" aria-label="page3" class="pager-pos">3</a>
                        <a href="/post-706714-3" rel="next" class="pager-next"><div class="triangle-right"></div></a>
                    </div>
                </div>
                <ul class="comments">
                    <li data-comment-id="9765301" id="11" class="content-item">
                        <div class="nsk-content-meta-info">
                            <div class="avatar-wrapper"><a title="liuqin" href="/space/2077"><img src="/avatar/2077.png" alt="liuqin" class="avatar-normal"></a></div>
                            <div><div class="author-info"><a href="/space/2077" class="author-name">liuqin</a></div>
                            <div class="content-info"><span class="date-created"><time datetime="2026-04-29T07:36:40.000Z">1h 18min ago</time></span></div></div>
                            <div class="floor-link-wrapper"><a href="#11" class="floor-link">#11</a></div>
                        </div>
                        <article class="post-content"><p>有没搞错，5个龟壳，真离谱啊</p></article>
                    </li>
                </ul>
            </div>
        </div>
        """
        let parser = KannaNodeSeekParser(baseURL: URL(string: "https://www.nodeseek.com")!)

        let detail = try parser.parsePostDetail(
            html: html,
            url: URL(string: "https://www.nodeseek.com/post-706714-2")!
        )

        #expect(detail.id == "706714")
        #expect(detail.title == "一周内第五个龟壳到手，圣何塞区")
        #expect(detail.page == 2)
        #expect(detail.contentHTML.isEmpty)
        #expect(detail.comments.count == 1)
        #expect(detail.comments.first?.authorName == "liuqin")
        let pagination = try #require(detail.pagination)
        #expect(pagination.currentPage == 2)
        #expect(pagination.previousPage == 1)
        #expect(pagination.nextPage == 3)
        #expect(pagination.items.map(\.page) == [1, 2, 3])
        #expect(pagination.items[1].isCurrent)
    }

    @Test func parsesPostDetailContentFromDivPostContentFallback() throws {
        let html = """
        <html>
        <head><title>测试详情</title></head>
        <body>
          <div class="nsk-post">
            <div class="content-item">
              <a class="author-name" href="/space/1">mist</a>
              <div class="post-content">
                <p>div 容器里的正文也要保留</p>
              </div>
            </div>
          </div>
        </body>
        </html>
        """
        let parser = KannaNodeSeekParser(baseURL: URL(string: "https://www.nodeseek.com")!)

        let detail = try parser.parsePostDetail(
            html: html,
            url: URL(string: "https://www.nodeseek.com/post-1-1")!
        )

        #expect(detail.contentHTML.contains("div 容器里的正文也要保留"))
    }

    @Test func parsesCommentsFromNonListCommentContainers() throws {
        let html = """
        <html>
        <head><title>测试详情</title></head>
        <body>
          <div class="nsk-post">
            <div class="content-item">
              <a class="author-name" href="/space/1">mist</a>
              <article class="post-content"><p>正文</p></article>
            </div>
          </div>
          <div class="comments">
            <div class="content-item" id="comment-1" data-comment-id="1">
              <a class="author-name" href="/space/2">alice</a>
              <article class="post-content"><p>非 ul/li 评论也要解析</p></article>
            </div>
          </div>
        </body>
        </html>
        """
        let parser = KannaNodeSeekParser(baseURL: URL(string: "https://www.nodeseek.com")!)

        let detail = try parser.parsePostDetail(
            html: html,
            url: URL(string: "https://www.nodeseek.com/post-1-1")!
        )

        #expect(detail.comments.count == 1)
        #expect(detail.comments.first?.contentHTML.contains("非 ul/li 评论也要解析") == true)
    }

    @Test func parsesAuthorProfileURLFromAvatarWrapperFallback() throws {
        let html = """
        <html>
        <head><title>测试详情</title></head>
        <body>
          <div class="nsk-post">
            <div class="content-item">
              <div class="avatar-wrapper"><a href="/space/1541"><img class="avatar-normal" src="/avatar/1541.png"></a></div>
              <a class="author-name">mist</a>
              <article class="post-content"><p>正文</p></article>
            </div>
          </div>
          <div class="comments">
            <div class="content-item" id="comment-1" data-comment-id="1">
              <div class="avatar-wrapper"><a href="/space/17851"><img class="avatar-normal" src="/avatar/17851.png"></a></div>
              <a class="author-name">luren</a>
              <article class="post-content"><p>评论</p></article>
            </div>
          </div>
        </body>
        </html>
        """
        let parser = KannaNodeSeekParser(baseURL: URL(string: "https://www.nodeseek.com")!)

        let detail = try parser.parsePostDetail(
            html: html,
            url: URL(string: "https://www.nodeseek.com/post-1-1")!
        )

        #expect(detail.authorProfileURL?.absoluteString == "https://www.nodeseek.com/space/1541#/general")
        #expect(detail.comments.first?.authorProfileURL?.absoluteString == "https://www.nodeseek.com/space/17851#/general")
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
        #expect(detail.isLastPage)
    }

    @Test func parsesLastPageStateFromPagerNextLink() throws {
        let baseURL = URL(string: "https://www.nodeseek.com")!
        let parser = KannaNodeSeekParser(baseURL: baseURL)
        let htmlWithNext = """
        <div class="nsk-post">
            <div class="post-title"><h1><a class="post-title-link" href="/post-1-1">标题</a></h1></div>
            <div class="content-item">
                <a class="author-name">作者</a>
                <article class="post-content"><p>正文</p></article>
            </div>
        </div>
        <div class="comment-container">
            <a href="/post-1-2" rel="next" class="pager-next"></a>
            <ul class="comments"></ul>
        </div>
        """
        let htmlWithoutNext = """
        <div class="nsk-post">
            <div class="post-title"><h1><a class="post-title-link" href="/post-1-2">标题</a></h1></div>
            <div class="content-item">
                <a class="author-name">作者</a>
                <article class="post-content"><p>正文</p></article>
            </div>
        </div>
        <div class="comment-container">
            <span class="pager-next" aria-disabled="true"></span>
            <ul class="comments"></ul>
        </div>
        """

        let firstPage = try parser.parsePostDetail(html: htmlWithNext, url: URL(string: "https://www.nodeseek.com/post-1-1")!)
        let lastPage = try parser.parsePostDetail(html: htmlWithoutNext, url: URL(string: "https://www.nodeseek.com/post-1-2")!)

        #expect(firstPage.isLastPage == false)
        #expect(lastPage.isLastPage)
    }
}
