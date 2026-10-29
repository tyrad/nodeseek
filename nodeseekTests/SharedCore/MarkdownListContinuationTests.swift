//
//  MarkdownListContinuationTests.swift
//  nodeseekTests
//

import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import NodeSeekCore
#else
@testable import nodeseek
#endif

struct MarkdownListContinuationTests {
    private func newline(_ text: String, at location: Int? = nil) -> MarkdownEdit? {
        let caret = location ?? (text as NSString).length
        return MarkdownListContinuation.edit(forNewlineAt: NSRange(location: caret, length: 0), in: text)
    }

    @Test func continuesUnorderedAndOrderedLists() {
        #expect(newline("- 甲") == MarkdownEdit(text: "- 甲\n- ", selection: NSRange(location: 6, length: 0)))
        #expect(newline("* 甲")?.text == "* 甲\n* ")
        #expect(newline("3. 甲")?.text == "3. 甲\n4. ")
        #expect(newline("  9) 甲")?.text == "  9) 甲\n  10) ")
        #expect(newline("> 引用")?.text == "> 引用\n> ")
    }

    @Test func emptyItemEndsTheList() {
        #expect(newline("- 甲\n- ") == MarkdownEdit(text: "- 甲\n", selection: NSRange(location: 4, length: 0)))
        #expect(newline("1. 甲\n2. \n后文", at: 8) == MarkdownEdit(text: "1. 甲\n\n后文", selection: NSRange(location: 5, length: 0)))
    }

    @Test func splittingAnItemCarriesTheRestToTheNewItem() {
        #expect(newline("- 甲乙", at: 3)?.text == "- 甲\n- 乙")
    }

    @Test func plainTextCodeBlocksAndCaretBeforeMarkerAreIgnored() {
        #expect(newline("普通文字") == nil)
        #expect(newline("```\n- 代码里") == nil)
        #expect(newline("- 甲", at: 0) == nil)
        #expect(newline("-无空格") == nil)
    }
}

struct MarkdownLinkEditorTests {
    @Test func findsLinkAroundCaret() {
        let text = "看 [官网](https://a.com) 吧"
        #expect(MarkdownLinkEditor.existingLink(around: NSRange(location: 4, length: 0), in: text)
            == .init(range: NSRange(location: 2, length: 19), name: "官网", url: "https://a.com"))
        #expect(MarkdownLinkEditor.existingLink(around: NSRange(location: 0, length: 0), in: text) == nil)
        #expect(MarkdownLinkEditor.existingLink(around: NSRange(location: 4, length: 0), in: "![图](u)") == nil)
    }

    @Test func insertsOrReplacesLink() {
        #expect(MarkdownLinkEditor.apply(name: " 官网 ", url: "https://a.com ", replacing: NSRange(location: 2, length: 0), in: "看 吧")
            == MarkdownEdit(text: "看 [官网](https://a.com)吧", selection: NSRange(location: 21, length: 0)))
        #expect(MarkdownLinkEditor.apply(name: "", url: "https://a.com", replacing: NSRange(location: 0, length: 2), in: "旧的")
            .text == "[https://a.com](https://a.com)")
    }
}
