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
            fragment: "<p><img src=\"https://cdn.example.com/photo.png\" width=\"1200\" height=\"800\"></p>",
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
            fragment: "<p><img src=\"https://cdn.example.com/tall.png\" width=\"800\" height=\"2000\"></p>",
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

    @Test func keepsDTCoreTextImageAttachmentForDataURL() throws {
        let renderer = DTCoreTextHTMLContentRenderer()
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let pngDataURL = """
        data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=
        """
        let blocks = renderer.render(
            fragment: "<p><img src=\"\(pngDataURL)\"></p>",
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
        let attributed = try #require(
            blocks.compactMap { block -> NSAttributedString? in
                guard case .text(let text) = block else { return nil }
                return text
            }.first
        )

        #expect(attributed.string.contains("💻基本信息"))
        #expect(attributed.string.contains("一、操作系统信息"))
        #expect(attributed.string.contains("🎬IP质量"))
        #expect(attributed.string.contains("IP质量内容"))
        #expect(attributed.string.contains("🌐网络质量"))
        #expect(attributed.string.contains("📍回程路由"))

        var attachmentURLs: [URL] = []
        attributed.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributed.length)
        ) { value, _, _ in
            guard let attachment = value as? DTTextAttachment else { return }
            if let contentURL = attachment.contentURL {
                attachmentURLs.append(contentURL)
            }
        }
        #expect(attachmentURLs.map(\.absoluteString) == [
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
        let attributed = try #require(
            blocks.compactMap { block -> NSAttributedString? in
                guard case .text(let text) = block else { return nil }
                return text
            }.first
        )

        #expect(attributed.string.contains("💻基本信息"))
        #expect(attributed.string.contains("硬件质量体检报告"))
        #expect(attributed.string.contains("🎬IP质量"))
        #expect(attributed.string.contains("IP质量体检报告"))
        #expect(attributed.string.contains("🌐网络质量"))
        #expect(attributed.string.contains("📍回程路由"))
        #expect(attributed.string.contains("xterm-fg-1") == false)
        #expect(attributed.string.contains("hidden helper") == false)

        var attachmentURLs: [URL] = []
        attributed.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributed.length)
        ) { value, _, _ in
            guard let attachment = value as? DTTextAttachment else { return }
            if let contentURL = attachment.contentURL {
                attachmentURLs.append(contentURL)
            }
        }
        #expect(attachmentURLs.map(\.absoluteString) == [
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
        let attributed = try #require(
            blocks.compactMap { block -> NSAttributedString? in
                guard case .text(let text) = block else { return nil }
                return text
            }.first
        )

        #expect(attributed.string.contains("🎬IP质量"))
        #expect(attributed.string.contains("IP质量体检报告：69.63.*.*"))
        #expect(attributed.string.contains("https://github.com/xykt/IPQuality"))
        #expect(attributed.string.contains("报告链接：https://Report.Check.Place/ip/demo.svg"))
        #expect(attributed.string.contains("[1m") == false)
        #expect(attributed.string.contains("[36m") == false)
        #expect(attributed.string.contains("[4m") == false)
        #expect(attributed.string.contains("[0m") == false)

        var attachmentURLs: [URL] = []
        attributed.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributed.length)
        ) { value, _, _ in
            guard let attachment = value as? DTTextAttachment else { return }
            if let contentURL = attachment.contentURL {
                attachmentURLs.append(contentURL)
            }
        }
        #expect(attachmentURLs.map(\.absoluteString) == ["https://i.111666.best/image/network.webp"])
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
        let attributed = try #require(
            blocks.compactMap { block -> NSAttributedString? in
                guard case .text(let text) = block else { return nil }
                return text
            }.first
        )

        #expect(attributed.string.contains("💻基本信息"))
        #expect(attributed.string.contains("IP质量体检报告"))
        #expect(attributed.string.contains("IP质量体检报告(Lite)"))
        #expect(attributed.string.contains("🌐网络质量"))
        #expect(attributed.string.contains("📍回程路由"))
        #expect(attributed.string.contains("报告链接：https://Report.Check.Place/ip/1TZZHW387.svg"))
        #expect(attributed.string.contains("[1m") == false)
        #expect(attributed.string.contains("[36m") == false)
        #expect(attributed.string.contains("[0m") == false)

        var attachmentURLs: [String] = []
        var attachmentDisplaySizes: [CGSize] = []
        attributed.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributed.length)
        ) { value, _, _ in
            guard let attachment = value as? DTTextAttachment,
                  let contentURL = attachment.contentURL else {
                return
            }
            attachmentURLs.append(contentURL.absoluteString)
            attachmentDisplaySizes.append(attachment.displaySize)
        }

        #expect(attachmentURLs == [
            "https://i.111666.best/image/G9D5ncG5qndySgQtNwvFq4.webp",
            "https://i.111666.best/image/noEhdCSyuAeuREqqSWgdY5.webp"
        ])
        #expect(attachmentDisplaySizes.count == 2)
        #expect(attachmentDisplaySizes.allSatisfy { $0.width > 0 && $0.height > 0 })
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
        let attributed = try #require(
            blocks.compactMap { block -> NSAttributedString? in
                guard case .text(let text) = block else { return nil }
                return text
            }.first
        )

        let label = UILabel()
        label.numberOfLines = 0
        label.attributedText = attributed
        let fittingSize = label.systemLayoutSizeFitting(
            CGSize(width: 160, height: CGFloat.greatestFiniteMagnitude),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )

        #expect(fittingSize.height > UIFont.preferredFont(forTextStyle: .body).lineHeight * 2)
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
}
