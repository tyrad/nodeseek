//
//  PostSummaryCellNodeTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/4/28.
//

import Testing
import UIKit
@testable import nodeseek

@MainActor
struct PostSummaryCellNodeTests {
    @Test func metadataTextOmitsNodeNameAndWideSeparators() {
        let post = PostSummary(
            id: "1",
            title: "标题",
            url: URL(string: "https://www.nodeseek.com/post-1")!,
            authorName: "mist",
            nodeName: "NodeSeek",
            replyCount: 4,
            viewCount: 34,
            lastActivityText: "22s ago"
        )

        let text = PostSummaryCellNode.metadataAttributedText(for: post).string

        #expect(text.contains("mist"))
        #expect(text.contains("34"))
        #expect(text.contains("4"))
        #expect(text.contains("22s ago"))
        #expect(!text.contains("NodeSeek"))
        #expect(!text.contains(" · "))
    }

    @Test func metadataTextOmitsMissingAuthorFallback() {
        let post = PostSummary(
            id: "4",
            title: "缺少作者",
            url: URL(string: "https://www.nodeseek.com/post-4")!,
            authorName: "未知用户",
            nodeName: "NodeSeek",
            replyCount: 2,
            viewCount: 10,
            lastActivityText: "1min ago"
        )

        let text = PostSummaryCellNode.metadataAttributedText(for: post).string

        #expect(!text.contains("未知用户"))
        #expect(text.contains("10"))
        #expect(text.contains("2"))
        #expect(text.contains("1min ago"))
        #expect(!text.hasPrefix("  "))
    }

    @Test func postSummaryCellUsesDenseReadingListTypography() throws {
        let post = PostSummary(
            id: "2",
            title: "nodeimage.com 正式版发布！附带论坛内自动上传图片脚本",
            url: URL(string: "https://www.nodeseek.com/post-2")!,
            authorName: "shuai",
            nodeName: "NodeSeek",
            replyCount: 961,
            viewCount: 475454,
            lastActivityText: "6h 30min ago"
        )
        let titleText = PostSummaryCellNode.titleAttributedText(for: post)
        let metadataText = PostSummaryCellNode.metadataAttributedText(for: post)

        #expect(PostSummaryCellStyle.titleMaximumNumberOfLines == 2)
        #expect(titleText.string == post.title)
        #expect(titleText.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor == .label)
        #expect((titleText.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)?.pointSize == 19)
        #expect(PostSummaryCellStyle.metadataMaximumNumberOfLines == 1)
        #expect((metadataText.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)?.pointSize == 14)
        #expect(metadataText.string.contains("shuai"))
        #expect(metadataText.string.contains("475454"))
        #expect(metadataText.string.contains("961"))
        #expect(metadataText.string.contains("6h 30min ago"))
    }

    @Test func pinnedPostTitleShowsPinSymbolBeforeTitle() throws {
        let post = PostSummary(
            id: "1033",
            title: "[小白入门科普] 服务器行业黑话大全",
            url: URL(string: "https://www.nodeseek.com/post-1033")!,
            authorName: "斯巴达",
            nodeName: "日常",
            replyCount: 2403,
            viewCount: 169842,
            lastActivityText: "7h 32min ago",
            isPinned: true
        )

        let titleText = PostSummaryCellNode.titleAttributedText(for: post)
        let firstAttachment = titleText.attribute(
            NSAttributedString.Key.attachment,
            at: 0,
            effectiveRange: nil
        ) as? NSTextAttachment

        #expect(firstAttachment?.image != nil)
        #expect(titleText.string.dropFirst().hasPrefix(" "))
        #expect(titleText.string.contains(post.title))
    }

    @Test func cellRefreshAppearanceRebuildsAttributedText() {
        let post = PostSummary(
            id: "5",
            title: "主题切换测试",
            url: URL(string: "https://www.nodeseek.com/post-5")!,
            authorName: "mist",
            nodeName: "NodeSeek",
            replyCount: 8,
            viewCount: 88,
            lastActivityText: "just now",
            isPinned: true,
            isLocked: true
        )
        let node = PostSummaryCellNode(post: post)

        let initialTitle = node.debugTitleAttributedText
        let initialMetadata = node.debugMetadataAttributedText

        node.refreshAppearanceForCurrentTraits()

        #expect(node.debugTitleAttributedText !== initialTitle)
        #expect(node.debugMetadataAttributedText !== initialMetadata)
    }
}
