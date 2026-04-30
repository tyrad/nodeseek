//
//  DTCoreTextHTMLContentRendererTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/4/28.
//

import Foundation
import DTCoreText
import Testing
import UIKit
@testable import nodeseek

struct DTCoreTextHTMLContentRendererTests {
    @Test func rendersTableAsSeparateBlockBetweenTextBlocks() throws {
        let renderer = DTCoreTextHTMLContentRenderer()
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let blocks = renderer.render(
            fragment: """
            <p>before</p>
            <table>
              <thead><tr><th>Plan</th><th>Price</th></tr></thead>
              <tbody><tr><td>Starter</td><td>$5</td></tr></tbody>
            </table>
            <p>after</p>
            """,
            baseURL: baseURL,
            maxImageWidth: 320
        )

        #expect(blocks.count == 3)

        guard case .text(let beforeText) = blocks[0] else {
            Issue.record("Expected leading text block")
            return
        }
        #expect(beforeText.string.contains("before"))

        guard case .table(let table) = blocks[1] else {
            Issue.record("Expected table block")
            return
        }
        #expect(table.rows.count == 2)
        #expect(table.rows[0].isHeader)
        #expect(table.rows[0].cells.map(\.text) == ["Plan", "Price"])
        #expect(table.rows[1].cells.map(\.text) == ["Starter", "$5"])

        guard case .text(let afterText) = blocks[2] else {
            Issue.record("Expected trailing text block")
            return
        }
        #expect(afterText.string.contains("after"))
    }

    @Test func preservesBareTextAroundPreformattedBlock() throws {
        let renderer = DTCoreTextHTMLContentRenderer()
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let blocks = renderer.render(
            fragment: "前置说明<pre><code>let value = 1</code></pre>后置说明",
            baseURL: baseURL,
            maxImageWidth: 320
        )

        #expect(blocks.count == 3)
        guard case .text(let before) = blocks[0],
              case .codeBlock(let codeBlock) = blocks[1],
              case .text(let after) = blocks[2] else {
            Issue.record("Expected text/codeBlock/text block order")
            return
        }
        #expect(before.string.contains("前置说明"))
        #expect(codeBlock.text == "let value = 1")
        #expect(after.string.contains("后置说明"))
    }

    @Test func preservesParentTextAroundNestedTable() throws {
        let renderer = DTCoreTextHTMLContentRenderer()
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let blocks = renderer.render(
            fragment: """
            <div>表格前说明<table><tbody><tr><td>单元格</td></tr></tbody></table>表格后说明</div>
            """,
            baseURL: baseURL,
            maxImageWidth: 320
        )

        #expect(blocks.count == 3)
        guard case .text(let before) = blocks[0],
              case .table(let table) = blocks[1],
              case .text(let after) = blocks[2] else {
            Issue.record("Expected text/table/text block order")
            return
        }
        #expect(before.string.contains("表格前说明"))
        #expect(table.rows.first?.cells.first?.text == "单元格")
        #expect(after.string.contains("表格后说明"))
    }

    @Test func rendersImageOnlyTableCells() throws {
        let renderer = DTCoreTextHTMLContentRenderer()
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let blocks = renderer.render(
            fragment: """
            <table>
            <thead><tr><th>IPv4测试结果</th><th>IPv6测试结果</th></tr></thead>
            <tbody>
            <tr>
            <td><img src="https://github.com/xykt/NetQuality/raw/main/res/v4_cn.png" alt="IPv4"></td>
            <td><img src="https://github.com/xykt/NetQuality/raw/main/res/v6_cn.png" alt="IPv6"></td>
            </tr>
            </tbody>
            </table>
            """,
            baseURL: baseURL,
            maxImageWidth: 320
        )

        let table = try #require(blocks.compactMap { block -> RenderedTableBlock? in
            guard case .table(let table) = block else { return nil }
            return table
        }.first)

        #expect(table.rows.count == 2)
        #expect(table.rows[1].cells.count == 2)
        #expect(table.rows[1].cells[0].text.isEmpty)
        #expect(table.rows[1].cells[0].imageURL?.absoluteString == "https://github.com/xykt/NetQuality/raw/main/res/v4_cn.png")
        #expect(table.rows[1].cells[1].imageURL?.absoluteString == "https://github.com/xykt/NetQuality/raw/main/res/v6_cn.png")
    }

    @Test func preservesExplicitLineBreaksInsideTableCells() throws {
        let renderer = DTCoreTextHTMLContentRenderer()
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let blocks = renderer.render(
            fragment: """
            <table>
            <tbody>
            <tr><td>第一行<br>第二行<p>第三行</p></td></tr>
            </tbody>
            </table>
            """,
            baseURL: baseURL,
            maxImageWidth: 320
        )

        let table = try #require(blocks.compactMap { block -> RenderedTableBlock? in
            guard case .table(let table) = block else { return nil }
            return table
        }.first)

        #expect(table.rows[0].cells[0].text == "第一行\n第二行\n第三行")
    }

    @Test func rendersLinkAsAbsoluteURL() throws {
        let renderer = DTCoreTextHTMLContentRenderer()
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let blocks = renderer.render(
            fragment: "<p><a href=\"/post-123\">Open</a></p>",
            baseURL: baseURL,
            maxImageWidth: 320
        )
        let attributed = try #require(
            blocks.compactMap { block -> NSAttributedString? in
                guard case .text(let text) = block else { return nil }
                return text
            }.first
        )

        let range = (attributed.string as NSString).range(of: "Open")
        #expect(range.location != NSNotFound)
        let link = attributed.attribute(.link, at: range.location, effectiveRange: nil) as? URL
        #expect(link?.absoluteString == "https://www.nodeseek.com/post-123")
    }

    @Test func rendersBodyTextWithReadableLineSpacing() throws {
        let renderer = DTCoreTextHTMLContentRenderer()
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let blocks = renderer.render(
            fragment: "<p>第一行<br>第二行<br>第三行</p>",
            baseURL: baseURL,
            maxImageWidth: 320
        )
        let attributed = try #require(
            blocks.compactMap { block -> NSAttributedString? in
                guard case .text(let text) = block else { return nil }
                return text
            }.first
        )

        let range = (attributed.string as NSString).range(of: "第一行")
        #expect(range.location != NSNotFound)
        let paragraphStyle = attributed.attribute(
            .paragraphStyle,
            at: range.location,
            effectiveRange: nil
        ) as? NSParagraphStyle
        #expect((paragraphStyle?.lineSpacing ?? 0) >= 5)
    }

    @Test func rendersLinksWithNodeSeekGreen() throws {
        let renderer = DTCoreTextHTMLContentRenderer()
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let blocks = renderer.render(
            fragment: "<p><a href=\"/post-704174-1\">帖子</a></p>",
            baseURL: baseURL,
            maxImageWidth: 320
        )
        let attributed = try #require(
            blocks.compactMap { block -> NSAttributedString? in
                guard case .text(let text) = block else { return nil }
                return text
            }.first
        )

        let range = (attributed.string as NSString).range(of: "帖子")
        #expect(range.location != NSNotFound)
        let color = attributed.attribute(
            .foregroundColor,
            at: range.location,
            effectiveRange: nil
        ) as? UIColor
        #expect(color?.isClose(to: UIColor(red: 15 / 255, green: 128 / 255, blue: 85 / 255, alpha: 1)) == true)
    }

    @Test func rendersBlockquoteWithTextBlockBackground() throws {
        let renderer = DTCoreTextHTMLContentRenderer()
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let blocks = renderer.render(
            fragment: """
            <blockquote><p><a href="/member?t=xiaogang-119">@xiaogang-119</a> <a href="/post-704014-1#2">#2</a><br>
            <a href="/member?t=linda">@linda</a> <a href="/post-704014-1#1">#1</a> 区别能过cf盾牌了</p></blockquote>
            """,
            baseURL: baseURL,
            maxImageWidth: 320
        )
        let attributed = try #require(
            blocks.compactMap { block -> NSAttributedString? in
                guard case .text(let text) = block else { return nil }
                return text
            }.first
        )

        let range = (attributed.string as NSString).range(of: "@xiaogang-119")
        #expect(range.location != NSNotFound)
        let textBlocks = attributed.attribute(
            NSAttributedString.Key(DTTextBlocksAttribute),
            at: range.location,
            effectiveRange: nil
        ) as? [DTTextBlock]
        #expect(textBlocks?.contains { $0.backgroundColor != nil } == true)
    }

    @Test func rendersBlockquoteWithCompactHorizontalAndRoomyVerticalPadding() throws {
        let renderer = DTCoreTextHTMLContentRenderer()
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let blocks = renderer.render(
            fragment: "<blockquote><p>引用内容</p></blockquote>",
            baseURL: baseURL,
            maxImageWidth: 320
        )
        let attributed = try #require(
            blocks.compactMap { block -> NSAttributedString? in
                guard case .text(let text) = block else { return nil }
                return text
            }.first
        )

        let range = (attributed.string as NSString).range(of: "引用内容")
        #expect(range.location != NSNotFound)
        let textBlocks = attributed.attribute(
            NSAttributedString.Key(DTTextBlocksAttribute),
            at: range.location,
            effectiveRange: nil
        ) as? [DTTextBlock]
        let quoteBlock = try #require(textBlocks?.first { $0.backgroundColor != nil })
        #expect(quoteBlock.padding.top >= 12)
        #expect(quoteBlock.padding.bottom >= 12)
        #expect(quoteBlock.padding.left <= 8)

        let paragraphStyle = try #require(attributed.attribute(
            .paragraphStyle,
            at: range.location,
            effectiveRange: nil
        ) as? NSParagraphStyle)
        #expect(paragraphStyle.firstLineHeadIndent > 0)
        #expect(paragraphStyle.firstLineHeadIndent <= 12)
        #expect(paragraphStyle.headIndent > 0)
        #expect(paragraphStyle.headIndent <= 12)
    }

    @Test func rendersSemanticHTMLWithDistinctTypography() throws {
        let renderer = DTCoreTextHTMLContentRenderer()
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let blocks = renderer.render(
            fragment: """
            <article class="post-content">
            <h4>一级小标题</h4>
            <p><strong>重点内容</strong> 普通正文<br>第二行 <a href="/jump?to=https%3A%2F%2Fexample.com%2Fkeys">链接</a></p>
            <ul><li>列表项</li></ul>
            <h5>二级小标题</h5>
            <blockquote><p>引用内容</p></blockquote>
            <pre><code>let value = 1</code></pre>
            <p><img src="https://cdn.example.com/photo.png" width="1200" height="800"></p>
            </article>
            """,
            baseURL: baseURL,
            maxImageWidth: 320
        )
        let h4Font = try #require(font(in: blocks, matching: "一级小标题"))
        let h5Font = try #require(font(in: blocks, matching: "二级小标题"))
        let strongFont = try #require(font(in: blocks, matching: "重点内容"))
        let bodyFont = try #require(font(in: blocks, matching: "普通正文"))
        let codeBlock = try #require(codeBlocks(in: blocks).first)
        let imageBlock = try #require(imageBlocks(in: blocks).first)
        let renderedText = combinedText(in: blocks)

        #expect(h4Font.pointSize > bodyFont.pointSize)
        #expect(h5Font.pointSize > bodyFont.pointSize)
        #expect(strongFont.fontDescriptor.symbolicTraits.contains(.traitBold))
        #expect(codeBlock.text == "let value = 1")
        #expect(imageBlock.url.absoluteString == "https://cdn.example.com/photo.png")
        #expect(renderedText.contains("普通正文\n第二行") || renderedText.contains("普通正文\u{2028}第二行"))
        #expect(renderedText.contains("• 列表项"))

        let quoteAttributed = try #require(attributedText(in: blocks, matching: "引用内容"))
        let resolvedQuoteRange = (quoteAttributed.string as NSString).range(of: "引用内容")
        #expect(resolvedQuoteRange.location != NSNotFound)

        let linkAttributed = try #require(attributedText(in: blocks, matching: "链接"))
        let linkRange = (linkAttributed.string as NSString).range(of: "链接")
        #expect(linkRange.location != NSNotFound)
        let link = linkAttributed.attribute(.link, at: linkRange.location, effectiveRange: nil) as? URL
        #expect(link?.absoluteString == "https://www.nodeseek.com/jump?to=https%3A%2F%2Fexample.com%2Fkeys")

        #expect(imageBlocks(in: blocks).count == 1)
    }

    @Test func rendersRelativeImageAsAttachmentWithResolvedURL() throws {
        let renderer = DTCoreTextHTMLContentRenderer()
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let blocks = renderer.render(
            fragment: "<p>before<img src=\"/static/image/sticker/xhj/003.png\">after</p>",
            baseURL: baseURL,
            maxImageWidth: 240
        )
        let attributed = try #require(
            blocks.compactMap { block -> NSAttributedString? in
                guard case .text(let text) = block else { return nil }
                return text
            }.first
        )

        var attachmentURL: URL?
        attributed.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributed.length)
        ) { value, _, stop in
            guard let attachment = value as? DTTextAttachment else { return }
            attachmentURL = attachment.contentURL
            stop.pointee = true
        }

        #expect(attachmentURL?.absoluteString == "https://www.nodeseek.com/static/image/sticker/xhj/003.png")
    }

    @Test func usesHalfWidthSquareForNonStickerImageAttachments() throws {
        let renderer = DTCoreTextHTMLContentRenderer()
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let blocks = renderer.render(
            fragment: "<p>before<img src=\"https://cdn.example.com/photo.png\" width=\"1200\" height=\"800\">after</p>",
            baseURL: baseURL,
            maxImageWidth: 320
        )
        let attributed = try #require(
            blocks.compactMap { block -> NSAttributedString? in
                guard case .text(let text) = block else { return nil }
                return text
            }.first
        )

        var attachment: DTTextAttachment?
        attributed.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributed.length)
        ) { value, _, stop in
            guard let value = value as? DTTextAttachment else { return }
            attachment = value
            stop.pointee = true
        }

        let displaySize = try #require(attachment?.displaySize)
        #expect(displaySize.width == 160)
        #expect(displaySize.height == 160)
    }

    @Test func usesContainedPresentationForExtremeRatioImageAttachments() throws {
        let renderer = DTCoreTextHTMLContentRenderer()
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let blocks = renderer.render(
            fragment: "<p>before<img src=\"https://cdn.example.com/tall.png\" width=\"800\" height=\"2000\">after</p>",
            baseURL: baseURL,
            maxImageWidth: 320
        )
        let attributed = try #require(
            blocks.compactMap { block -> NSAttributedString? in
                guard case .text(let text) = block else { return nil }
                return text
            }.first
        )

        var attachment: DTTextAttachment?
        attributed.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributed.length)
        ) { value, _, stop in
            guard let value = value as? DTTextAttachment else { return }
            attachment = value
            stop.pointee = true
        }

        let displaySize = try #require(attachment?.displaySize)
        #expect(displaySize.width == 168)
        #expect(displaySize.height == 420)
    }

    @Test func keepsStickerImageAttachmentsLimitedByFixedWidthOnly() throws {
        let renderer = DTCoreTextHTMLContentRenderer()
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let blocks = renderer.render(
            fragment: "<p><img src=\"/static/image/sticker/xhj/003.png\" width=\"800\" height=\"1600\"></p>",
            baseURL: baseURL,
            maxImageWidth: 320
        )
        let attributed = try #require(
            blocks.compactMap { block -> NSAttributedString? in
                guard case .text(let text) = block else { return nil }
                return text
            }.first
        )

        var attachment: DTTextAttachment?
        attributed.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributed.length)
        ) { value, _, stop in
            guard let value = value as? DTTextAttachment else { return }
            attachment = value
            stop.pointee = true
        }

        let displaySize = try #require(attachment?.displaySize)
        #expect(displaySize.width == 65)
        #expect(displaySize.height == 130)
    }

    @Test func treatsStickerClassAsStickerEvenWhenURLDoesNotContainSticker() throws {
        let renderer = DTCoreTextHTMLContentRenderer()
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let blocks = renderer.render(
            fragment: "<p><img class=\"sticker\" src=\"/static/image/yct/015.gif\" alt=\"yct015\"></p>",
            baseURL: baseURL,
            maxImageWidth: 320
        )
        let attributed = try #require(
            blocks.compactMap { block -> NSAttributedString? in
                guard case .text(let text) = block else { return nil }
                return text
            }.first
        )

        var displaySize: CGSize?
        attributed.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributed.length)
        ) { value, _, stop in
            guard let attachment = value as? DTTextAttachment else { return }
            displaySize = attachment.displaySize
            stop.pointee = true
        }

        #expect(displaySize == CGSize(width: 65, height: 65))
    }

    @Test func rendersVideoStickerAsInlineAttachmentAndKeepsFollowingText() throws {
        let renderer = DTCoreTextHTMLContentRenderer()
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let blocks = renderer.render(
            fragment: """
            <p><video autoplay="" loop="" muted="" playsinline="" class="sticker" width="100" height="100">
                <source src="/static/image/sticker/emoji/00.webm" type="video/webm; codecs=&quot;vp9&quot;">
                <source src="/static/image/sticker/emoji/00.mov" type="video/mp4; codecs=&quot;hvc1&quot;">
            </video> 这个表情后面还有文字</p>
            """,
            baseURL: baseURL,
            maxImageWidth: 320
        )
        let attributed = try #require(
            blocks.compactMap { block -> NSAttributedString? in
                guard case .text(let text) = block else { return nil }
                return text
            }.first
        )
        #expect(attributed.string.contains("这个表情后面还有文字"))

        var attachment: DTTextAttachment?
        attributed.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributed.length)
        ) { value, _, stop in
            guard let value = value as? DTTextAttachment else { return }
            attachment = value
            stop.pointee = true
        }

        #expect(attachment?.contentURL?.absoluteString == "https://www.nodeseek.com/static/image/sticker/emoji/00.mov")
        #expect(attachment?.displaySize == CGSize(width: 65, height: 65))
    }

    @Test func videoStickerSourceSelectionPrefersIOSFriendlySource() throws {
        let renderer = DTCoreTextHTMLContentRenderer()
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let blocks = renderer.render(
            fragment: """
            <p><video class="sticker">
                <source src="/static/image/sticker/emoji/01.webm" type="video/webm">
                <source src="/static/image/sticker/emoji/01.mp4" type="video/mp4">
            </video></p>
            """,
            baseURL: baseURL,
            maxImageWidth: 320
        )
        let attributed = try #require(
            blocks.compactMap { block -> NSAttributedString? in
                guard case .text(let text) = block else { return nil }
                return text
            }.first
        )

        var attachmentURL: URL?
        attributed.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributed.length)
        ) { value, _, stop in
            guard let attachment = value as? DTTextAttachment else { return }
            attachmentURL = attachment.contentURL
            stop.pointee = true
        }

        #expect(attachmentURL?.absoluteString == "https://www.nodeseek.com/static/image/sticker/emoji/01.mp4")
    }

    @Test func keepsStickerClassClassificationAfterVideoAttachment() throws {
        let renderer = DTCoreTextHTMLContentRenderer()
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let blocks = renderer.render(
            fragment: """
            <p><video class="sticker" width="100" height="100">
                <source src="/static/image/sticker/emoji/01.mp4" type="video/mp4">
            </video><img class="sticker" src="/static/image/yct/015.gif" alt="yct015"></p>
            """,
            baseURL: baseURL,
            maxImageWidth: 320
        )
        let attributed = try #require(
            blocks.compactMap { block -> NSAttributedString? in
                guard case .text(let text) = block else { return nil }
                return text
            }.first
        )

        var attachments: [DTTextAttachment] = []
        attributed.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributed.length)
        ) { value, _, _ in
            guard let attachment = value as? DTTextAttachment else { return }
            attachments.append(attachment)
        }

        #expect(attachments.map { $0.displaySize } == [
            CGSize(width: 65, height: 65),
            CGSize(width: 65, height: 65)
        ])
        #expect(attachments.last?.contentURL?.absoluteString == "https://www.nodeseek.com/static/image/yct/015.gif")
    }

    @Test func treatsVideoStickerClassAsStickerWhenURLDoesNotContainSticker() throws {
        let renderer = DTCoreTextHTMLContentRenderer()
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let blocks = renderer.render(
            fragment: """
            <p><video class="sticker" width="100" height="100">
                <source src="/static/image/emoji/01.mp4" type="video/mp4">
            </video></p>
            """,
            baseURL: baseURL,
            maxImageWidth: 320
        )
        let attributed = try #require(
            blocks.compactMap { block -> NSAttributedString? in
                guard case .text(let text) = block else { return nil }
                return text
            }.first
        )

        var attachment: DTTextAttachment?
        attributed.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributed.length)
        ) { value, _, stop in
            guard let value = value as? DTTextAttachment else { return }
            attachment = value
            stop.pointee = true
        }

        #expect(attachment?.contentURL?.absoluteString == "https://www.nodeseek.com/static/image/emoji/01.mp4")
        #expect(attachment?.displaySize == CGSize(width: 65, height: 65))
    }

    @Test func keepsDTCoreTextImageAttachmentForDataURL() throws {
        let renderer = DTCoreTextHTMLContentRenderer()
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let pngDataURL = """
        data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=
        """
        let blocks = renderer.render(
            fragment: "<p>before<img src=\"\(pngDataURL)\">after</p>",
            baseURL: baseURL,
            maxImageWidth: 240
        )
        let attributed = try #require(
            blocks.compactMap { block -> NSAttributedString? in
                guard case .text(let text) = block else { return nil }
                return text
            }.first
        )

        var attachment: DTTextAttachment?
        attributed.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributed.length)
        ) { value, _, stop in
            guard let value = value as? DTTextAttachment else { return }
            attachment = value
            stop.pointee = true
        }

        #expect(attachment?.contentURL.absoluteString == pngDataURL)
        #expect(attachment is DTImageTextAttachment)
    }

    @Test func rendersNodeSeekMagicTabsAfterLongCodeBlock() throws {
        let renderer = DTCoreTextHTMLContentRenderer()
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let separator = String(repeating: "+", count: 80)
        let blocks = renderer.render(
            fragment: """
            <div class="nsk-magic-tabs">
            <div class="nsk-magic-tab-title">💻基本信息</div>
            <div class="nsk-magic-tab-body"><pre><code>\(separator)
            一、操作系统信息
            \(separator)</code></pre></div>
            <div class="nsk-magic-tab-title">🎬IP质量</div>
            <div class="nsk-magic-tab-body"><pre><code>IP质量内容</code></pre></div>
            <div class="nsk-magic-tab-title">🌐网络质量</div>
            <div class="nsk-magic-tab-body"><p><img src="https://i.111666.best/image/network.webp" alt="image"></p></div>
            <div class="nsk-magic-tab-title">📍回程路由</div>
            <div class="nsk-magic-tab-body"><p><img src="https://i.111666.best/image/route.webp" alt="image"></p></div>
            </div>
            """,
            baseURL: baseURL,
            maxImageWidth: 240
        )
        let renderedText = combinedText(in: blocks)

        #expect(renderedText.contains("💻基本信息"))
        #expect(renderedText.contains("一、操作系统信息"))
        #expect(renderedText.contains("🎬IP质量"))
        #expect(renderedText.contains("IP质量内容"))
        #expect(renderedText.contains("🌐网络质量"))
        #expect(renderedText.contains("📍回程路由"))
        #expect(imageURLs(in: blocks).map(\.absoluteString) == [
            "https://i.111666.best/image/network.webp",
            "https://i.111666.best/image/route.webp"
        ])
    }

    @Test func rendersMagicTabImagesAfterXtermDOMBodies() throws {
        let renderer = DTCoreTextHTMLContentRenderer()
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let noisyTerminalStyles = String(repeating: ".xterm-fg-1 { color: #cc0000; }", count: 120)
        let blocks = renderer.render(
            fragment: """
            <div class="nsk-magic-tabs enabled">
            <div class="nsk-magic-tab-title">💻基本信息</div>
            <div class="nsk-magic-tab-body">
              <div class="terminal-container embedMode">
                <textarea aria-label="Terminal input">hidden helper</textarea>
                <style>\(noisyTerminalStyles)</style>
                <div class="xterm-rows">
                  <div><span>硬件质量体检报告</span></div>
                  <div><span>https://github.com/xykt/HardwareQuality</span></div>
                </div>
              </div>
            </div>
            <div class="nsk-magic-tab-title">🎬IP质量</div>
            <div class="nsk-magic-tab-body">
              <div class="terminal-container embedMode">
                <style>\(noisyTerminalStyles)</style>
                <div class="xterm-rows">
                  <div><span>IP质量体检报告</span></div>
                  <div><span>报告链接：https://Report.Check.Place/ip/demo.svg</span></div>
                </div>
              </div>
            </div>
            <div class="nsk-magic-tab-title">🌐网络质量</div>
            <div class="nsk-magic-tab-body"><p><img src="https://i.111666.best/image/network.webp" alt="image"></p></div>
            <div class="nsk-magic-tab-title">📍回程路由</div>
            <div class="nsk-magic-tab-body"><p><img src="https://i.111666.best/image/route.webp" alt="image"></p></div>
            </div>
            """,
            baseURL: baseURL,
            maxImageWidth: 240
        )
        let renderedText = combinedText(in: blocks)

        #expect(renderedText.contains("💻基本信息"))
        #expect(renderedText.contains("硬件质量体检报告"))
        #expect(renderedText.contains("🎬IP质量"))
        #expect(renderedText.contains("IP质量体检报告"))
        #expect(renderedText.contains("🌐网络质量"))
        #expect(renderedText.contains("📍回程路由"))
        #expect(renderedText.contains("xterm-fg-1") == false)
        #expect(renderedText.contains("hidden helper") == false)
        #expect(imageURLs(in: blocks).map(\.absoluteString) == [
            "https://i.111666.best/image/network.webp",
            "https://i.111666.best/image/route.webp"
        ])
    }

    @Test func sanitizesMagicTabANSICodeBlocks() throws {
        let renderer = DTCoreTextHTMLContentRenderer()
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let blocks = renderer.render(
            fragment: """
            <div class="nsk-magic-tabs">
            <div class="nsk-magic-tab-title">🎬IP质量</div>
            <div class="nsk-magic-tab-body">
              <pre><code class="language-ansi">########################################################################
                       <span data-ansicode="27"></span>[1mIP质量体检报告：<span data-ansicode="27"></span>[36m69.63.*.*<span data-ansicode="27"></span>[0m
                   <span data-ansicode="27"></span>[4mhttps://github.com/xykt/IPQuality<span data-ansicode="27"></span>[0m
              报告链接：<span data-ansicode="27"></span>[4mhttps://Report.Check.Place/ip/demo.svg<span data-ansicode="27"></span>[0m
              </code></pre>
            </div>
            <div class="nsk-magic-tab-title">🌐网络质量</div>
            <div class="nsk-magic-tab-body"><p><img src="https://i.111666.best/image/network.webp" alt="image"></p></div>
            </div>
            """,
            baseURL: baseURL,
            maxImageWidth: 240
        )
        let renderedText = combinedText(in: blocks)

        #expect(renderedText.contains("🎬IP质量"))
        #expect(renderedText.contains("IP质量体检报告：69.63.*.*"))
        #expect(renderedText.contains("https://github.com/xykt/IPQuality"))
        #expect(renderedText.contains("报告链接：https://Report.Check.Place/ip/demo.svg"))
        #expect(renderedText.contains("[1m") == false)
        #expect(renderedText.contains("[36m") == false)
        #expect(renderedText.contains("[4m") == false)
        #expect(renderedText.contains("[0m") == false)
        #expect(imageURLs(in: blocks).map(\.absoluteString) == ["https://i.111666.best/image/network.webp"])
    }

    @Test func rendersPost705039MagicTabsFixtureWithAllTabsAndImages() throws {
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let html = try FixtureLoader.html(named: "post-705039-1")
        let parser = KannaNodeSeekParser(baseURL: baseURL)
        let detail = try parser.parsePostDetail(
            html: html,
            url: URL(string: "https://www.nodeseek.com/post-705039-1")!
        )
        let renderer = DTCoreTextHTMLContentRenderer()
        let blocks = renderer.render(
            fragment: detail.contentHTML,
            baseURL: baseURL,
            maxImageWidth: 320
        )
        let renderedText = combinedText(in: blocks)
        let images = imageBlocks(in: blocks)

        #expect(renderedText.contains("💻基本信息"))
        #expect(renderedText.contains("IP质量体检报告"))
        #expect(renderedText.contains("IP质量体检报告(Lite)"))
        #expect(renderedText.contains("🌐网络质量"))
        #expect(renderedText.contains("📍回程路由"))
        #expect(renderedText.contains("报告链接：https://Report.Check.Place/ip/1TZZHW387.svg"))
        #expect(renderedText.contains("[1m") == false)
        #expect(renderedText.contains("[36m") == false)
        #expect(renderedText.contains("[0m") == false)
        #expect(images.map { $0.url.absoluteString } == [
            "https://i.111666.best/image/G9D5ncG5qndySgQtNwvFq4.webp",
            "https://i.111666.best/image/noEhdCSyuAeuREqqSWgdY5.webp"
        ])
        #expect(images.count == 2)
    }

    @Test func splitsStandaloneImageParagraphIntoImageBlocks() throws {
        let renderer = DTCoreTextHTMLContentRenderer()
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let blocks = renderer.render(
            fragment: """
            <article class="post-content"><p><img src="https://img.imgdd.com/859a2738-af24-4c00-85c3-149ea7ea3fd8.jpg" alt="1000512053.jpg" class=""><br>
            <img src="https://img.imgdd.com/988d4da2-a819-4e98-a294-25e7365b47dd.jpg" alt="1000512054.jpg" class=""></p>
            <p><span class="emoji">😓</span>说好的睁一只眼闭一只眼呢 越活越回去了</p>
            </article>
            """,
            baseURL: baseURL,
            maxImageWidth: 320
        )

        #expect(blocks.count == 3)
        guard case .image(let firstImage) = blocks[0],
              case .image(let secondImage) = blocks[1],
              case .text(let text) = blocks[2] else {
            Issue.record("Expected image/image/text block order")
            return
        }

        #expect(firstImage.url.absoluteString == "https://img.imgdd.com/859a2738-af24-4c00-85c3-149ea7ea3fd8.jpg")
        #expect(firstImage.altText == "1000512053.jpg")
        #expect(secondImage.url.absoluteString == "https://img.imgdd.com/988d4da2-a819-4e98-a294-25e7365b47dd.jpg")
        #expect(secondImage.altText == "1000512054.jpg")
        #expect(text.string.contains("😓说好的睁一只眼闭一只眼呢"))
    }

    @MainActor
    @Test func wrapsLongPreformattedLinesToAvailableWidth() throws {
        let renderer = DTCoreTextHTMLContentRenderer()
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let blocks = renderer.render(
            fragment: "<pre><code>\(String(repeating: "+", count: 120))</code></pre>",
            baseURL: baseURL,
            maxImageWidth: 160
        )
        let codeBlock = try #require(codeBlocks(in: blocks).first)
        #expect(codeBlock.text == String(repeating: "+", count: 120))
        #expect(DetailCodeBlockLayout.naturalCodeWidth(for: codeBlock.text) > 160)
    }

    @Test func extractsCopyWrappedPreCodeAsCodeBlock() throws {
        let renderer = DTCoreTextHTMLContentRenderer()
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let blocks = renderer.render(
            fragment: """
            <pre class="code-copy-wrapper"><code data-has-copy-button="1">2个级别分别是优化线路和非优化线路
            IPv4&amp;IPv6-三网9929/CMIN2
            T1系列是普通线路机器</code><button class="code-copy-btn always" type="button">
              <svg class="lucide lucide-copy"><rect width="14" height="14"></rect></svg>
            </button></pre>
            """,
            baseURL: baseURL,
            maxImageWidth: 320
        )

        let codeBlock = try #require(blocks.compactMap { block -> RenderedCodeBlock? in
            guard case .codeBlock(let codeBlock) = block else { return nil }
            return codeBlock
        }.first)

        #expect(codeBlock.text.contains("2个级别分别是优化线路和非优化线路"))
        #expect(codeBlock.text.contains("IPv4&IPv6-三网9929/CMIN2"))
        #expect(codeBlock.text.contains("T1系列是普通线路机器"))
        #expect(codeBlock.text.contains("button") == false)
        #expect(codeBlock.text.contains("svg") == false)
        #expect(codeBlock.text.contains("lucide") == false)
    }

    @Test func extractsChineseCopyWrappedPreCodeAsCodeBlock() throws {
        let renderer = DTCoreTextHTMLContentRenderer()
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let blocks = renderer.render(
            fragment: """
            <pre class="code-copy-wrapper"><code data-has-copy-button="1">各位大佬好！作为一枚 VPS 玩家，你是否经常遇到这些令人抓狂的“心塞时刻”：
            刚买的极品原生 IP 小鸡，没用多久 Google 定位就莫名其妙漂移到了 HK 甚至直接“送中”了？
            查一下 IPQS 和 Scamalytics，风险分红得发紫，Netflix 掉解锁、ChatGPT 狂弹验证码？
            遇到个“好邻居”瞎搞乱发包，连累你这台本分的小鸡 IP 信用直接破产？
            </code><button class="code-copy-btn always" type="button">
              <svg class="lucide lucide-copy"><rect width="14" height="14"></rect></svg>
            </button></pre>
            """,
            baseURL: baseURL,
            maxImageWidth: 320
        )

        let codeBlock = try #require(blocks.compactMap { block -> RenderedCodeBlock? in
            guard case .codeBlock(let codeBlock) = block else { return nil }
            return codeBlock
        }.first)

        #expect(codeBlock.text.contains("各位大佬好！作为一枚 VPS 玩家"))
        #expect(codeBlock.text.contains("Google 定位"))
        #expect(codeBlock.text.contains("ChatGPT 狂弹验证码"))
        #expect(codeBlock.text.contains("button") == false)
        #expect(codeBlock.text.contains("svg") == false)
    }

    @Test func extractsHighlightedPreCodeAsPlainCodeBlock() throws {
        let renderer = DTCoreTextHTMLContentRenderer()
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let blocks = renderer.render(
            fragment: """
            <pre class="code-copy-wrapper"><code class="language-Bash" data-has-copy-button="1">curl -fsSL https://raw.githubusercontent.com/hotyue/IP-Sentinel/main/core/install.sh -o /tmp/ins_agent.sh &amp;&amp; <span class="hljs-built_in">sudo</span> bash /tmp/ins_agent.sh
            </code><button class="code-copy-btn always" type="button">
              <svg class="lucide lucide-copy"><rect width="14" height="14"></rect></svg>
            </button></pre>
            """,
            baseURL: baseURL,
            maxImageWidth: 320
        )

        let codeBlock = try #require(blocks.compactMap { block -> RenderedCodeBlock? in
            guard case .codeBlock(let codeBlock) = block else { return nil }
            return codeBlock
        }.first)

        #expect(codeBlock.text == "curl -fsSL https://raw.githubusercontent.com/hotyue/IP-Sentinel/main/core/install.sh -o /tmp/ins_agent.sh && sudo bash /tmp/ins_agent.sh")
    }

    @Test func keepsCodeBlockOrderBetweenTextBlocks() throws {
        let renderer = DTCoreTextHTMLContentRenderer()
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let blocks = renderer.render(
            fragment: "<p>before</p><pre><code>let value = 1</code></pre><p>after</p>",
            baseURL: baseURL,
            maxImageWidth: 320
        )

        #expect(blocks.count == 3)
        guard case .text(let before) = blocks[0],
              case .codeBlock(let codeBlock) = blocks[1],
              case .text(let after) = blocks[2] else {
            Issue.record("Expected text/codeBlock/text block order")
            return
        }
        #expect(before.string.contains("before"))
        #expect(codeBlock.text == "let value = 1")
        #expect(after.string.contains("after"))
    }

    @Test func rendersHTMLListsWithVisibleMarkers() throws {
        let renderer = DTCoreTextHTMLContentRenderer()
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let blocks = renderer.render(
            fragment: """
            <ul><li>first</li><li>second</li></ul>
            <ol><li>alpha</li><li>beta</li></ol>
            """,
            baseURL: baseURL,
            maxImageWidth: 320
        )
        let attributed = try #require(
            blocks.compactMap { block -> NSAttributedString? in
                guard case .text(let text) = block else { return nil }
                return text
            }.first
        )

        #expect(attributed.string.contains("• first"))
        #expect(attributed.string.contains("• second"))
        #expect(attributed.string.contains("1. alpha"))
        #expect(attributed.string.contains("2. beta"))
    }

    private func font(in attributed: NSAttributedString, matching text: String) -> UIFont? {
        let range = (attributed.string as NSString).range(of: text)
        guard range.location != NSNotFound else { return nil }
        return attributed.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont
    }

    private func font(in blocks: [RenderedContentBlock], matching text: String) -> UIFont? {
        for block in blocks {
            guard case .text(let attributed) = block,
                  let font = font(in: attributed, matching: text) else {
                continue
            }
            return font
        }
        return nil
    }

    private func attributedText(in blocks: [RenderedContentBlock], matching text: String) -> NSAttributedString? {
        blocks.compactMap { block -> NSAttributedString? in
            guard case .text(let attributed) = block,
                  attributed.string.contains(text) else {
                return nil
            }
            return attributed
        }.first
    }

    private func combinedText(in blocks: [RenderedContentBlock]) -> String {
        blocks.compactMap { block -> String? in
            switch block {
            case .text(let text):
                return text.string
            case .codeBlock(let codeBlock):
                return codeBlock.text
            default:
                return nil
            }
        }.joined(separator: "\n")
    }

    private func codeBlocks(in blocks: [RenderedContentBlock]) -> [RenderedCodeBlock] {
        blocks.compactMap { block in
            guard case .codeBlock(let codeBlock) = block else { return nil }
            return codeBlock
        }
    }

    private func imageBlocks(in blocks: [RenderedContentBlock]) -> [RenderedImageBlock] {
        blocks.compactMap { block in
            guard case .image(let imageBlock) = block else { return nil }
            return imageBlock
        }
    }

    private func imageURLs(in blocks: [RenderedContentBlock]) -> [URL] {
        var urls = imageBlocks(in: blocks).map(\.url)
        for block in blocks {
            guard case .text(let attributed) = block else { continue }
            attributed.enumerateAttribute(
                .attachment,
                in: NSRange(location: 0, length: attributed.length)
            ) { value, _, _ in
                guard let attachment = value as? DTTextAttachment,
                      let contentURL = attachment.contentURL else {
                    return
                }
                urls.append(contentURL)
            }
        }
        return urls
    }
}

private extension UIColor {
    func isClose(to other: UIColor) -> Bool {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        var otherRed: CGFloat = 0
        var otherGreen: CGFloat = 0
        var otherBlue: CGFloat = 0
        var otherAlpha: CGFloat = 0
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha),
              other.getRed(&otherRed, green: &otherGreen, blue: &otherBlue, alpha: &otherAlpha) else {
            return false
        }
        let tolerance: CGFloat = 0.01
        return abs(red - otherRed) <= tolerance
            && abs(green - otherGreen) <= tolerance
            && abs(blue - otherBlue) <= tolerance
            && abs(alpha - otherAlpha) <= tolerance
    }
}
