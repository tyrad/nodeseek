//
//  MarkdownEditorTests.swift
//  nodeseekTests
//

import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import NodeSeekCore
#else
@testable import nodeseek
#endif

struct MarkdownEditorHighlighterTests {
    /// 把高亮结果转成 (文字, 样式)，断言更直观。
    private func styled(_ text: String) -> [(String, MarkdownEditorStyle)] {
        let source = text as NSString
        return MarkdownEditorHighlighter.highlights(in: text).map { (source.substring(with: $0.range), $0.style) }
    }

    private func contains(_ pairs: [(String, MarkdownEditorStyle)], _ text: String, _ style: MarkdownEditorStyle) -> Bool {
        pairs.contains { $0.0 == text && $0.1 == style }
    }

    @Test func headingMarksPrefixAndBoldsText() {
        let pairs = styled("## 需求")
        #expect(contains(pairs, "## ", .marker))
        #expect(contains(pairs, "需求", .heading))
    }

    @Test func listQuoteAndRuleMarkers() {
        let pairs = styled("- 晚高峰\n1. 第一\n> 引用\n---")
        #expect(contains(pairs, "- ", .marker))
        #expect(contains(pairs, "1. ", .marker))
        #expect(contains(pairs, "> ", .marker))
        #expect(contains(pairs, "引用", .quote))
        #expect(contains(pairs, "---", .marker))
    }

    @Test func inlineStyles() {
        let pairs = styled("**粗** *斜* ~~删~~ `code` [站点](https://nodeseek.com)")
        #expect(contains(pairs, "粗", .bold))
        #expect(contains(pairs, "斜", .italic))
        #expect(contains(pairs, "删", .strikethrough))
        #expect(contains(pairs, "code", .inlineCode))
        #expect(contains(pairs, "站点", .link))
        #expect(contains(pairs, "](https://nodeseek.com)", .marker))
    }

    @Test func halfTypedSyntaxIsIgnored() {
        let pairs = styled("**还没打完 和 `未闭合")
        #expect(pairs.isEmpty)
    }

    @Test func listBulletIsNotItalic() {
        let pairs = styled("* 列表项")
        #expect(contains(pairs, "* ", .marker))
        #expect(pairs.contains { $0.1 == .italic } == false)
    }

    @Test func codeBlockSpansLinesAndSuppressesInlineSyntax() {
        let pairs = styled("```\n**不是粗体**\n## 也不是标题\n```\n**粗体**")
        #expect(contains(pairs, "**不是粗体**", .codeBlock))
        #expect(contains(pairs, "## 也不是标题", .codeBlock))
        #expect(pairs.filter { $0.1 == .bold }.map(\.0) == ["粗体"])
    }

    @Test func imageIsOneDimmedRangeAndHidesInnerLink() {
        let pairs = styled("![图片](https://i.nodeimage.com/a.webp)")
        #expect(pairs.count == 1)
        #expect(contains(pairs, "![图片](https://i.nodeimage.com/a.webp)", .image))
    }

    @Test func codeSpanContentIsNotBold() {
        let pairs = styled("`**a**`")
        #expect(pairs.contains { $0.1 == .bold } == false)
        #expect(contains(pairs, "**a**", .inlineCode))
    }

    @Test func rangesUseUTF16ForEmojiAndChinese() {
        let text = "😀中 **粗**"
        let highlight = try! #require(MarkdownEditorHighlighter.highlights(in: text).first { $0.style == .bold })
        #expect((text as NSString).substring(with: highlight.range) == "粗")
    }
}

struct MarkdownSnippetInserterTests {
    private func apply(_ snippet: MarkdownSnippet, _ text: String, _ location: Int, _ length: Int = 0) -> MarkdownEdit {
        MarkdownSnippetInserter.apply(snippet, to: text, selection: NSRange(location: location, length: length))
    }

    private func selected(_ edit: MarkdownEdit) -> String {
        (edit.text as NSString).substring(with: edit.selection)
    }

    @Test func boldWrapsSelectionAndKeepsItSelected() {
        let edit = apply(.bold, "按月付", 0, 3)
        #expect(edit.text == "**按月付**")
        #expect(selected(edit) == "按月付")
    }

    @Test func boldTogglesOffWhenAlreadyWrapped() {
        let edit = apply(.bold, "**按月付**", 2, 3)
        #expect(edit.text == "按月付")
        #expect(selected(edit) == "按月付")
    }

    @Test func italicOnBoldTextAddsItalicInsteadOfRemovingBold() {
        let edit = apply(.italic, "**按月付**", 2, 3)
        #expect(edit.text == "***按月付***")
        #expect(selected(edit) == "按月付")

        let removed = apply(.italic, "***按月付***", 3, 3)
        #expect(removed.text == "**按月付**")

        let plain = apply(.italic, "*按月付*", 1, 3)
        #expect(plain.text == "按月付")
    }

    @Test func emptySelectionPutsCaretBetweenMarkers() {
        let edit = apply(.inlineCode, "跑 ", 2)
        #expect(edit.text == "跑 ``")
        #expect(edit.selection == NSRange(location: 3, length: 0))
    }

    @Test func linkWithLabelPutsCaretInsideParentheses() {
        let edit = apply(.link, "看这里", 0, 3)
        #expect(edit.text == "[看这里]()")
        #expect(edit.selection == NSRange(location: 6, length: 0))

        let empty = apply(.link, "", 0)
        #expect(empty.text == "[]()")
        #expect(empty.selection == NSRange(location: 1, length: 0))
    }

    @Test func headingTogglesAndReplacesOtherBlockPrefix() {
        let on = apply(.heading, "需求", 1)
        #expect(on.text == "## 需求")
        #expect(on.selection == NSRange(location: 4, length: 0))

        let off = apply(.heading, "## 需求", 4)
        #expect(off.text == "需求")

        let fromQuote = apply(.heading, "> 需求", 3)
        #expect(fromQuote.text == "## 需求")
    }

    @Test func paragraphRemovesBlockPrefix() {
        #expect(apply(.paragraph, "### 小标题", 5).text == "小标题")
        #expect(apply(.paragraph, "- 项", 2).text == "项")
    }

    @Test func listAppliesToEverySelectedLine() {
        let edit = apply(.unorderedList, "甲\n乙\n丙", 0, 5)
        #expect(edit.text == "- 甲\n- 乙\n- 丙")
        #expect(selected(edit) == "甲\n- 乙\n- 丙")
    }

    @Test func listOnlyTouchesCurrentLine() {
        let edit = apply(.orderedList, "甲\n乙", 3)
        #expect(edit.text == "甲\n1. 乙")
    }

    @Test func codeBlockGoesOnItsOwnLines() {
        let edit = apply(.codeBlock, "前文", 2)
        #expect(edit.text == "前文\n```\n\n```")
        #expect(edit.selection == NSRange(location: 7, length: 0))

        let wrapped = apply(.codeBlock, "ls -la", 0, 6)
        #expect(wrapped.text == "```\nls -la\n```")
    }

    @Test func codeBlockInsideFenceRemovesThatBlock() {
        let source = "前文\n```\nls -la\n```\n后文"
        let edit = apply(.codeBlock, source, 9)
        #expect(edit.text == "前文\nls -la\n后文")
        #expect(edit.selection == NSRange(location: 5, length: 0))

        // 光标在开头那行 ``` 末尾
        let atFence = apply(.codeBlock, source, 6)
        #expect(atFence.text == "前文\nls -la\n后文")

        // 前面还有别的代码块时，只去掉光标所在的这一个
        let twoBlocks = "```\na\n```\n```\nb\n```"
        let second = apply(.codeBlock, twoBlocks, 15)
        #expect(second.text == "```\na\n```\nb\n")
    }

    @Test func imageInsertsOnItsOwnLineMidSentence() {
        let edit = apply(.image(url: "https://i.nodeimage.com/a.webp"), "跑分如下：后文", 5)
        #expect(edit.text == "跑分如下：\n![图片](https://i.nodeimage.com/a.webp)\n后文")
        #expect(edit.selection.location == 5 + 1 + ("![图片](https://i.nodeimage.com/a.webp)" as NSString).length)
    }

    @Test func blockStyleFollowsCaretLine() {
        let text = "正文\n## 标题\n> 引用\n```\ncode\n```"
        #expect(MarkdownSnippetInserter.blockStyle(at: 1, in: text) == .paragraph)
        #expect(MarkdownSnippetInserter.blockStyle(at: 5, in: text) == .heading)
        #expect(MarkdownSnippetInserter.blockStyle(at: 11, in: text) == .quote)
        #expect(MarkdownSnippetInserter.blockStyle(at: 18, in: text) == .codeBlock)
    }

    @Test func outOfRangeSelectionIsClamped() {
        let edit = apply(.bold, "ab", 5, 10)
        #expect(edit.text == "ab****")
    }
}

struct MarkdownImagePlaceholderTests {
    private let placeholder = MarkdownImagePlaceholder.text(id: "a1")

    @Test func replacesPlaceholderWithUploadedImage() {
        let content = "前文\n\(placeholder)\n后文"
        let replaced = MarkdownImagePlaceholder.replacing(id: "a1", with: "![图片](https://i.nodeimage.com/x.webp)", in: content)
        #expect(replaced == "前文\n![图片](https://i.nodeimage.com/x.webp)\n后文")
    }

    @Test func deletedPlaceholderIsNotRestored() {
        #expect(MarkdownImagePlaceholder.replacing(id: "a1", with: "![图片](u)", in: "前文") == nil)
    }

    @Test func removingPlaceholderAlsoRemovesItsLine() {
        #expect(MarkdownImagePlaceholder.removing(id: "a1", in: "前文\n\(placeholder)\n后文") == "前文\n后文")
        #expect(MarkdownImagePlaceholder.removing(id: "a1", in: "前文\n\(placeholder)") == "前文")
        #expect(MarkdownImagePlaceholder.removing(id: "a1", in: placeholder) == "")
    }

    @Test func strippingAllKeepsRealImages() {
        let content = "\(MarkdownImagePlaceholder.text(id: "x"))\n![图片](https://a.com/1.png)\n\(placeholder)\n结尾"
        #expect(MarkdownImagePlaceholder.strippingAll(in: content) == "![图片](https://a.com/1.png)\n结尾")
        #expect(MarkdownImagePlaceholder.containsPlaceholder(content))
        #expect(!MarkdownImagePlaceholder.containsPlaceholder("![图片](https://a.com/1.png)"))
    }
}
