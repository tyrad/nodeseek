//
//  MarkdownPreviewHTMLRendererTests.swift
//  nodeseekTests
//

import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import NodeSeekCore
#else
@testable import nodeseek
#endif

struct MarkdownPreviewHTMLRendererTests {
    private func html(_ markdown: String) -> String {
        MarkdownPreviewHTMLRenderer.html(from: markdown) { token in
            token == "yct015" ? URL(string: "https://www.nodeseek.com/static/image/sticker/yct/015.gif") : nil
        }
    }

    @Test func paragraphsKeepSingleLineBreaks() {
        #expect(html("第一行\n第二行\n\n新段落") == "<p>第一行<br>第二行</p>\n<p>新段落</p>")
    }

    @Test func headingsListsAndQuotes() {
        #expect(html("## 需求") == "<h2>需求</h2>")
        #expect(html("- 甲\n- 乙") == "<ul><li>甲</li><li>乙</li></ul>")
        #expect(html("1. 甲\n2. 乙") == "<ol><li>甲</li><li>乙</li></ol>")
        #expect(html("> 引用\n> **加粗**") == "<blockquote><p>引用<br><strong>加粗</strong></p></blockquote>")
        #expect(html("---") == "<hr>")
    }

    @Test func fencedCodeIsEscapedAndUntouched() {
        #expect(html("```swift\nlet a = **b** < c\n```") == "<pre><code class=\"language-swift\">let a = **b** &lt; c</code></pre>")
    }

    @Test func inlineStyles() {
        #expect(html("**粗** *斜* ~~删~~ `a*b*`") == "<p><strong>粗</strong> <em>斜</em> <del>删</del> <code>a*b*</code></p>")
    }

    @Test func linksImagesAndAutolinks() {
        #expect(html("[官网](https://a.com/x_y_z) ![图片](https://i.nodeimage.com/1.webp)")
            == "<p><a href=\"https://a.com/x_y_z\">官网</a> <img src=\"https://i.nodeimage.com/1.webp\" alt=\"图片\"></p>")
        #expect(html("看 https://a.com/p?q=1&r=2") == "<p>看 <a href=\"https://a.com/p?q=1&amp;r=2\">https://a.com/p?q=1&amp;r=2</a></p>")
    }

    @Test func stickersAndUploadPlaceholders() {
        #expect(html("好 :yct015: :unknown:") == "<p>好 <img class=\"sticker\" src=\"https://www.nodeseek.com/static/image/sticker/yct/015.gif\" alt=\"yct015\"> :unknown:</p>")
        #expect(html(MarkdownImagePlaceholder.text(id: "a1")) == "<p><em>（图片上传中）</em></p>")
    }

    @Test func tables() {
        #expect(html("| 列 1 | 列 2 |\n| --- | :-: |\n| a | **b** |")
            == "<table><tr><th>列 1</th><th>列 2</th></tr><tr><td>a</td><td><strong>b</strong></td></tr></table>")
    }

    @Test func rawHTMLIsEscaped() {
        #expect(html("<script>x</script>") == "<p>&lt;script&gt;x&lt;/script&gt;</p>")
    }
}
