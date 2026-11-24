import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import NodeSeekCore
#else
@testable import nodeseek
#endif

struct DetailSignatureDocumentTests {
    private func blocks(_ html: String) -> [DetailDocument.Block]? {
        DetailSignatureDocument.blocks(html: html, baseURL: NodeSeekSite.baseURL)
    }

    private func url(_ string: String) throws -> URL { try #require(URL(string: string)) }

    @Test func linksInOneLineStaySeparateAndClickable() throws {
        // 取自 703863 的签名。
        let html = #"<p><a href="https://www.nodeseek.com/notification#/message?mode=talk&amp;to=24520">站内私信</a> | <a href="https://t.me/GGbeng1_bot">我的TG</a></p>"#
        #expect(blocks(html) == [.paragraph([
            .text("站内私信", [], try url("https://www.nodeseek.com/notification#/message?mode=talk&to=24520")),
            .text(" | ", [], nil),
            .text("我的TG", [], try url("https://t.me/GGbeng1_bot")),
        ])])
    }

    @Test func linkedImageFallsBackSoTheLinkStaysTappable() {
        // 用图片做入口的签名：图片外层的链接是作者要的跳转，原生图片块带不了链接，整段退回网页渲染。
        #expect(blocks(#"<p><a href="https://example.com/shop"><img src="https://example.com/banner.png"></a></p>"#) == nil)
    }

    @Test func leadingRulesAreDroppedLikeTexture() throws {
        // 取自 1075091 #3 的签名：旧版只画文字下方的分隔线，开头的 <hr> 不显示。
        let html = "<hr>\n<hr>\n<p>签名</p>\n<hr>\n"
        #expect(blocks(html) == [.paragraph([.text("签名", [], nil)]), .divider])
    }

    @Test func headingsBreaksAndWhitespaceFollowTheWebpage() throws {
        let html = "<h2><strong><a href=\"https://t.me/vps\">VPS交流群</a></strong>  |\n <a href=\"/space/1\">主页</a></h2><p>第一行<br>  第二行 </p>"
        #expect(blocks(html) == [
            .paragraph([.text("VPS交流群", [.bold], try url("https://t.me/vps")), .text(" | ", [], nil),
                        .text("主页", [], try url("https://www.nodeseek.com/space/1"))]),
            .paragraph([.text("第一行\n第二行", [], nil)]),
        ])
    }

    @Test func stickersStayInlineAndImagesBecomeBlocks() throws {
        let html = #"<p>早<img class="sticker" src="/static/image/sticker/ac/01.png" alt="ac01"></p><p><img src="https://example.com/banner.png" alt="横幅"></p>"#
        let result = try #require(blocks(html))
        guard case .paragraph(let runs) = result.first, case .sticker(let token, _) = runs.last else {
            Issue.record("表情没有留在文字里：\(result)")
            return
        }
        #expect(token == ":ac01:")
        #expect(result.last == .image(alt: "横幅", url: try url("https://example.com/banner.png")))
    }

    @Test func unsupportedStructureFallsBackToWebpage() {
        #expect(blocks("<ul><li>一</li></ul>") == nil)
        #expect(blocks("<table><tr><td>格</td></tr></table>") == nil)
        #expect(blocks("  ") == nil)
    }
}
