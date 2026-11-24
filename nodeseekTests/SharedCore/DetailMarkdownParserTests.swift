import CoreFoundation
import Foundation
import Kanna
import Testing
#if SWIFT_PACKAGE
@testable import NodeSeekCore
#else
@testable import nodeseek
#endif

struct DetailMarkdownParserTests {
    let parser = DetailMarkdownParser(baseURL: NodeSeekSite.baseURL)
    private struct Page: Decodable {
        struct Item: Decodable { let id: String; let markdown: String; let html: String; let main: Bool }
        let path: String
        let items: [Item]
    }

    private func data(_ name: String) throws -> Data {
        #if SWIFT_PACKAGE
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        #else
        let url = Bundle(for: FixtureBundle.self).url(forResource: name, withExtension: "json")
        #endif
        return try Data(contentsOf: #require(url))
    }
    private final class FixtureBundle {}

    private func parse(_ text: String) throws -> [DetailDocument.Block] {
        let result = parser.render(.init(html: "", visibleMarkdown: text))
        guard case .native(let doc) = result else { throw TestError.fallback }
        return doc.blocks
    }
    private enum TestError: Error { case fallback }

    private struct VisibleContent {
        var paragraphs: [String] = []
        var links: [URL] = []
        var images: [URL] = []

        mutating func read(_ runs: [DetailDocument.Inline]) {
            var paragraph = ""
            for run in runs {
                switch run {
                case let .text(text, _, url):
                    paragraph += text
                    if let url { links.append(url) }
                case .sticker(_, let url): images.append(url)
                }
            }
            paragraphs.append(paragraph)
        }

        mutating func read(_ blocks: [DetailDocument.Block]) {
            for block in blocks {
                switch block {
                case .paragraph(let runs), .heading(_, let runs): read(runs)
                case .quote(let children): read(children)
                case .list(_, let items): for item in items { read(item) }
                case .table(let rows): for row in rows { for cell in row { read(cell) } }
                case .tabs(let tabs): for tab in tabs { paragraphs.append(tab.title); read(tab.blocks) }
                case .code(_, let text), .terminal(let text): paragraphs.append(text)
                case .image(_, let url): images.append(url)
                case .vote, .divider, .brokenImage: break
                }
            }
        }
    }

    private func compareWithPage(_ item: Page.Item, blocks: [DetailDocument.Block]) throws {
        let html = item.html.replacingOccurrences(of: "<span data-ansicode=\"27\"></span>", with: "ESCAPE_FOR_TEST")
            .replacingOccurrences(of: "<span data-ansicode=\"8\"></span>", with: "BACKSPACE_FOR_TEST")
        let body = try Kanna.HTML(html: "<html><body>\(html)</body></html>", encoding: .utf8)
        func url(_ raw: String?) -> URL? {
            guard let raw, let resolved = URL(string: raw, relativeTo: NodeSeekSite.baseURL)?.absoluteURL else { return nil }
            if resolved.path == "/jump", let target = URLComponents(url: resolved, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "to" })?.value {
                return URL(string: target)
            }
            return resolved
        }
        var native = VisibleContent()
        native.read(blocks)
        let links = body.css("a[href]").compactMap { url($0["href"]) }
        let images = body.css("img[src]").compactMap { url($0["src"]) }
        #expect(native.links == links, "链接与网页不同：\(item.id)")
        #expect(native.images == images, "图片与网页不同：\(item.id)")
        func normalize(_ string: String) -> String {
            string.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        }
        let content = body.xpath("//p[not(ancestor::li)] | //li[not(descendant::ul or descendant::ol)] | //th | //td | //pre | //h1 | //h2 | //h3 | //h4 | //h5 | //h6 | //*[@class='nsk-magic-tab-title']")
        let expected = content.map { normalize(($0.text ?? "").replacingOccurrences(of: "ESCAPE_FOR_TEST", with: "\u{1b}").replacingOccurrences(of: "BACKSPACE_FOR_TEST", with: "\u{8}")) }.filter { !$0.isEmpty }
        let actual = native.paragraphs.map(normalize).filter { !$0.isEmpty }
        if expected != actual {
            let first = zip(expected, actual).first { $0 != $1 }
            Issue.record("网页正文与原生段落不同：\(item.id)，\(expected.count)/\(actual.count)，\(first?.0.prefix(60) ?? "") / \(first?.1.prefix(60) ?? "")")
        }
    }

    @Test func capturedFloorsAndReview() throws {
        let pages = try JSONDecoder().decode([Page].self, from: data("post-markdown-pages"))
        #expect(pages.flatMap(\.items).count == 47)
        for page in pages {
            for item in page.items {
                let config = ["postData": ["comments": [[
                    "commentId": item.main ? 1 : 2, "blocked": false, "markdown": item.markdown
                ]]]]
                let payload = try JSONSerialization.data(withJSONObject: config)
                let detail = try self.page(payload: String(decoding: payload, as: UTF8.self),
                                           main: item.main ? item.html : "", reply: item.main ? "" : item.html)
                let source = item.main ? DetailFloorSource(post: detail) : DetailFloorSource(comment: detail.comments[0])
                guard case .native(let document) = parser.render(source) else {
                    Issue.record("网页取源后意外回退：\(item.id)")
                    continue
                }
                let blocks = document.blocks
                try compareWithPage(item, blocks: blocks)
                if page.path == "/post-1067722-1" && item.main {
                    let tabs = try #require(blocks.compactMap { if case .tabs(let tabs) = $0 { tabs } else { nil } }.first)
                    #expect(tabs.map(\.title) == ["💻基本信息", "🎬IP质量", "🌐网络质量", "📍回程路由"])
                    let reports = tabs.flatMap(\.blocks).compactMap { if case .terminal(let ansi) = $0 { ansi } else { nil } }
                    #expect(reports.count == 2)
                    for text in reports { #expect(item.markdown.contains(text)); #expect(text.contains("\u{1B}[")) }
                }
            }
        }
    }

    @Test func associatesSourceByCommentIDEvenWhenConfigOrderDiffers() throws {
        let payload = #"{"postData":{"comments":[{"commentId":2,"blocked":false,"markdown":"回复"},{"commentId":1,"blocked":false,"markdown":"主帖"}]}}"#
        let detail = try page(payload: payload, main: "<p>主帖</p>", reply: "<p>回复</p>")
        #expect(DetailFloorSource(post: detail).visibleMarkdown == "主帖")
        #expect(DetailFloorSource(comment: detail.comments[0]).visibleMarkdown == "回复")
        #expect(DetailFloorSource(comment: detail.comments[1]).visibleMarkdown == nil)
    }

    @Test func restrictedOrUncertainFloorsOnlyExposeWebpage() throws {
        for (flags, article) in [
            (#""blocked":true"#, "<p>屏蔽提示</p>"),
            (#""blocked":false,"deleted":true"#, "<p>作者撤回</p>"),
            (#""blocked":false"#, "<p><strong>已删除</strong></p>"),
            (#""blocked":false"#, "<a href='/help'>状态未知</a>"),
            (#""floorIndex":1"#, "<p>只显示提示</p>"),
            (#""blocked":false"#, "<p>可见提示<span hidden>SECRET</span></p>")
        ] {
            let payload = #"{"postData":{"comments":[{"commentId":1,\#(flags),"markdown":"SECRET"},{"commentId":2,\#(flags),"markdown":"SECRET"}]}}"#
            let detail = try page(payload: payload, main: article, reply: article)
            for source in [DetailFloorSource(post: detail), DetailFloorSource(comment: detail.comments[0])] {
                #expect(source.visibleMarkdown == nil)
                #expect(!source.html.contains("SECRET"))
                #expect(parser.render(source) == .webpage(html: source.html))
            }
        }
    }

    @Test func floorsThatMerelyMentionNoticeWordsKeepTheirMarkdown() throws {
        // 取自 1067259 第 3 页 #22、1044406 #3、1058358 主楼：作者自己写到「已删除」「权限不足」，原文数据未标记屏蔽或删除。
        let reply = "（已删除，不小心重复发布了上面的内容，抱歉——版主请帮忙删除）"
        let main = "# 更新\n\n修复提示**权限不足**的问题，已删除旧配置"
        let payload = #"{"postData":{"comments":[{"commentId":1,"blocked":false,"markdown":"\#(main.replacingOccurrences(of: "\n", with: "\\n"))"},{"commentId":2,"blocked":false,"markdown":"\#(reply)"}]}}"#
        let detail = try page(payload: payload, main: "<h1>更新</h1><p>修复提示<strong>权限不足</strong>的问题，已删除旧配置</p>", reply: "<p>\(reply)</p>")
        #expect(DetailFloorSource(post: detail).visibleMarkdown == main)
        #expect(DetailFloorSource(comment: detail.comments[0]).visibleMarkdown == reply)
    }

    @Test func pageNoticeOverridesAllRawContentButAReplyCannotRestrictThePage() throws {
        let payload = #"{"postData":{"comments":[{"commentId":1,"blocked":false,"markdown":"主帖"},{"commentId":2,"blocked":false,"markdown":"回复"}]}}"#
        let ordinary = try page(payload: payload, main: "主帖", reply: "<p>命令提示权限不足</p>")
        #expect(!ordinary.isRestricted)
        #expect(DetailFloorSource(post: ordinary).visibleMarkdown == "主帖")
        let restricted = try page(payload: payload, main: "SECRET", reply: "SECRET", notice: "<div>本帖需要注册用户才能查看</div>")
        #expect(restricted.isRestricted)
        for source in [DetailFloorSource(post: restricted), DetailFloorSource(comment: restricted.comments[0])] {
            #expect(source.visibleMarkdown == nil)
            #expect(source.html == "本帖需要注册用户才能查看")
        }
    }

    @Test func titleOrSignatureMentioningPermissionDoesNotRestrictThePage() throws {
        let payload = #"{"postData":{"comments":[{"commentId":1,"blocked":false,"markdown":"主帖"},{"commentId":2,"blocked":false,"markdown":"回复"}]}}"#
        // 标题、签名都是普通楼层内容，只有独立的站点提示才算受限页。
        let detail = try page(payload: payload, main: "主帖", reply: "回复", title: "Docker 提示权限不足怎么办",
                              signature: #"<div class="signature">需要注册用户才能查看的资源别问我</div>"#)
        #expect(!detail.isRestricted)
        #expect(detail.contentHTML == "主帖")
        #expect(DetailFloorSource(post: detail).visibleMarkdown == "主帖")
        #expect(detail.comments.first?.contentHTML == "回复")
    }

    @Test func quotingAReplyKeepsItsSourceWhenNativeRenderingFallsBack() throws {
        let payload = #"{"postData":{"comments":[{"commentId":1,"blocked":false,"markdown":"主帖"},{"commentId":2,"blocked":false,"markdown":"a\\_b 我的帖子已删除了吗"},{"commentId":3,"blocked":true,"markdown":"屏蔽原文"}]}}"#
        let detail = try page(payload: payload, main: "主帖", reply: "<p>a_b 我的帖子已删除了吗</p>")
        let reply = try #require(detail.comments.first { $0.id == "2" })
        // 正文走网页兜底不影响引用：未屏蔽的评论按网页逻辑引用原文。
        #expect(DetailFloorSource(comment: reply).visibleMarkdown == nil)
        #expect(reply.markdown == #"a\_b 我的帖子已删除了吗"#)
        #expect(detail.comments.first { $0.id == "3" }?.markdown == nil)
    }

    @Test func bareLinksStopWhereTheWebpageLinkifierStops() throws {
        let site = try #require(URL(string: "https://example.com"))
        #expect(try parse("官网 https://example.com，欢迎访问") == [.paragraph([.text("官网 ", [], nil), .text("https://example.com", [], site), .text("，欢迎访问", [], nil)])])
        #expect(try parse("(见 https://example.com).") == [.paragraph([.text("(见 ", [], nil), .text("https://example.com", [], site), .text(").", [], nil)])])
        #expect(try parse("https://example.com，@bob") == [.paragraph([.text("https://example.com", [], site), .text("，", [], nil),
                                                                    .text("@bob", [], URL(string: "https://www.nodeseek.com/member?t=bob"))])])
        #expect(try bareLinkTarget("https://en.wikipedia.org/wiki/A_(B)") == "https://en.wikipedia.org/wiki/A_(B)")
    }

    private func page(payload: String, main: String, reply: String, notice: String = "", title: String = "标题", signature: String = "") throws -> PostDetail {
        let html = """
        <div id="nsk-body-left">\(notice)<div class="post-title"><h1><a class="post-title-link">\(title)</a></h1></div>
        <div class="nsk-post"><div class="content-item" id="0" data-comment-id="1"><a class="author-name">楼主</a><article class="post-content">\(main)</article>\(signature)</div>
        <ul class="comments"><li class="content-item" id="1" data-comment-id="2"><a class="author-name">回复者</a><article class="post-content">\(reply)</article></li>
        <li class="content-item" id="2" data-comment-id="3"><a class="author-name">跨页热评</a><article class="post-content">其他楼层</article></li></ul></div></div>
        <script id="temp-script">\(Data(payload.utf8).base64EncodedString())</script>
        """
        return try KannaNodeSeekParser(baseURL: NodeSeekSite.baseURL).parsePostDetail(html: html, url: NodeSeekSite.postURL(id: "1", page: 1))
    }

    @Test func votesAndLiteralDelimiters() throws {
        let pages = try JSONDecoder().decode([Page].self, from: data("detail-replay-pages"))
        let vote = try #require(pages.first { $0.path == "/post-917518-1" }?.items.first)
        #expect(try parse(vote.markdown) == [.vote(3108)])
        #expect(try parse("> 前\n> nsapp://vote?id=3108\n> 后") == [.quote([.paragraph([.text("前", [], nil)]), .vote(3108), .paragraph([.text("后", [], nil)])])])
        let tab = ":::: tabs\n::: tab-item A\nnsapp://vote?id=3108\n\n```\n::::\n```\n:::\n::::"
        #expect(try parse(tab) == [.tabs([.init(title: "A", blocks: [.vote(3108), .code(language: nil, text: "::::\n")])])])
        #expect(try parse("`:xhj003: @a nsapp://vote?id=3`") == [.paragraph([.text(":xhj003: @a nsapp://vote?id=3", .code, nil)])])
        for bad in ["前\n\n:::: tabs\n::: tab-item A\n后", "前 nsapp://vote?id=bad", "<iframe src='x'></iframe>"] {
            #expect(parser.render(.init(html: "整楼", visibleMarkdown: bad)) == .webpage(html: "整楼"))
        }
    }

    private func bareLinkTarget(_ text: String) throws -> String {
        let blocks = try parse(text)
        guard case .paragraph(let runs) = blocks.first, case .text(let label, _, let link) = runs.first else {
            throw TestError.fallback
        }
        #expect(label == text)
        return try #require(link).absoluteString
    }

    @Test func onlyDoubleTildesStrikeTextInTheDetail() throws {
        let share = "/~99423cRA5z~:/"
        #expect(try parse(share) == [.paragraph([.text(share, [], nil)])])
        #expect(try parse("~单~ 和 ~~双~~") == [.paragraph([.text("~单~ 和 ", [], nil), .text("双", .strike, nil)])])
        #expect(try parse("中文 ~**强调**~") == [.paragraph([.text("中文 ~", [], nil), .text("强调", .bold, nil), .text("~", [], nil)])])
        #expect(try parse("> ~跨\r\n> 行~") == [.quote([.paragraph([.text("~跨", [], nil), .text("\n", [], nil), .text("行~", [], nil)])])])
        #expect(try parse("~x~ [链接](/~user~/)") == [.paragraph([.text("~x~ ", [], nil), .text("链接", [], NodeSeekSite.baseURL.appendingPathComponent("~user~/"))])])
        #expect(try parse(#"\~原样\~"#) == [.paragraph([.text("~原样~", [], nil)])])
        #expect(try parse("`~原样~`") == [.paragraph([.text("~原样~", .code, nil)])])
        #expect(try bareLinkTarget("https://example.com/~user~/file") == "https://example.com/~user~/file")
        #expect(try parse("~~~swift\n~x~\n~~~") == [.code(language: "swift", text: "~x~\n")])
    }

    @Test func mixedEscapesSurviveNavigation() throws {
        let raw = "https://example.com/a%2Fb中文?q=%23）&raw=%xx#段"
        let target = "https://example.com/a%2Fb%E4%B8%AD%E6%96%87?q=%23%EF%BC%89&raw=%25xx#%E6%AE%B5"
        #expect(CFURLCreateWithString(nil, raw as CFString, nil) == nil)
        let rendered = try bareLinkTarget(raw)
        #expect(rendered == target)
        #expect(CFURLCreateWithString(nil, rendered as CFString, nil) != nil)
        #expect(try bareLinkTarget(target) == target)
    }

    @Test func bareDomainsLinkedByTheWebpageStayLinks() throws {
        // 取自 832584 #83：网页把不带协议的域名转成了跳转链接。
        let html = #"<p>可以把 <a href="/jump?to=http%3A%2F%2Fping.nodeseek.com" target="_blank">ping.nodeseek.com</a> 跳转过去，xping.nodeseek.com 不算</p>"#
        let result = parser.render(.init(html: html, visibleMarkdown: "可以把 ping.nodeseek.com 跳转过去，xping.nodeseek.com 不算"))
        let url = try #require(URL(string: "http://ping.nodeseek.com"))
        #expect(result == .native(.init(blocks: [.paragraph([
            .text("可以把 ", [], nil), .text("ping.nodeseek.com", [], url), .text(" 跳转过去，xping.nodeseek.com 不算", [], nil),
        ])])))
        // 网页没有链接的域名保持普通文字。
        #expect(try parse("README.md") == [.paragraph([.text("README.md", [], nil)])])
    }

    @Test func invalidImageAddressStaysNativeAsBrokenImage() throws {
        // 取自 1074863 #1：图片地址只有 https://，网页显示加载失败。
        #expect(try parse("![image](https://)-10+1") == [.brokenImage(alt: "image"), .paragraph([.text("-10+1", [], nil)])])
    }

    @Test func lineBreaksAroundImagesDoNotBecomeBlankParagraphs() throws {
        // 取自 1075030 主楼：文字与多张图片之间只隔换行，旧版图片紧挨着排列。
        let a = try #require(URL(string: "https://example.com/a.webp")), b = try #require(URL(string: "https://example.com/b.webp"))
        #expect(try parse("文字\n![a](https://example.com/a.webp)\n![b](https://example.com/b.webp)\n结尾") == [
            .paragraph([.text("文字", [], nil)]), .image(alt: "a", url: a), .image(alt: "b", url: b), .paragraph([.text("结尾", [], nil)]),
        ])
    }

    @Test func relativeLinkAndImageKeepExistingEscapes() throws {
        let raw = "/a%2Fb 中文?q=%23）"
        let url = try #require(URL(string: "/a%2Fb%20%E4%B8%AD%E6%96%87?q=%23%EF%BC%89", relativeTo: NodeSeekSite.baseURL)?.absoluteURL)
        #expect(try parse("[详情](<" + raw + ">)") == [.paragraph([.text("详情", [], url)])])
        #expect(try parse("![图](<" + raw + ">)") == [.image(alt: "图", url: url)])
        #expect(try bareLinkTarget("https://[::1]/a%2Fb") == "https://[::1]/a%2Fb")
        #expect(parser.render(.init(html: "网页", visibleMarkdown: "[链接](<https://bad host/path>)")) == .webpage(html: "网页"))
    }

    @Test func dialectMatchesCapturedExamples() throws {
        struct Example: Decodable { struct Item: Decodable { let markdown: String; let html: String }; let item: Item; let match: String }
        let cases = try JSONDecoder().decode([String: Example].self, from: data("detail-replay-dialect"))
        for (key, example) in cases { if case .webpage = parser.render(.init(html: "", visibleMarkdown: example.item.markdown)) { Issue.record("Unexpected fallback: \(key)") } }
        #expect(try parse("# 标题\n\n甲\n乙") == [.heading(2, [.text("标题", [], nil)]), .paragraph([.text("甲", [], nil), .text("\n", [], nil), .text("乙", [], nil)])])
        #expect(try parse("**点进去**就") == [.paragraph([.text("点进去", .bold, nil), .text("就", [], nil)])])
        let url = try #require(cases["urlBoundary"]?.match)
        let page = try #require(cases["urlBoundary"])
        let anchor = try #require(Kanna.HTML(html: page.item.html, encoding: .utf8).at_xpath("//a"))
        let href = try #require(anchor["href"])
        let jump = try #require(URLComponents(string: href))
        let target = try #require(jump.queryItems?.first(where: { $0.name == "to" })?.value)
        #expect(try bareLinkTarget(url) == target)
        #expect(try parse("| A |\n|---|\n| <br> |") == [.table(rows: [[[.text("A", [], nil)]], [[.text("<br>", [], nil)]]])])
        let sticker = try #require(NodeSeekStickerLibrary.urlsByToken["xhj003"])
        #expect(try parse("@男朋友 :xhj003:") == [.paragraph([.text("@男朋友", [], URL(string: "/member?t=%E7%94%B7%E6%9C%8B%E5%8F%8B", relativeTo: NodeSeekSite.baseURL)?.absoluteURL), .text(" ", [], nil), .sticker(token: ":xhj003:", url: sticker)])])
    }
}
