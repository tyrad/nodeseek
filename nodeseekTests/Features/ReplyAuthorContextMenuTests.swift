//
//  ReplyAuthorContextMenuTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/5/24.
//

import AsyncDisplayKit
import Testing
import UIKit
@testable import nodeseek

@Suite(.serialized)
@MainActor
struct ReplyAuthorContextMenuTests {
    @Test func commentCopyTextUsesOnlyReplyBodyPlainText() {
        let comment = Comment(
            id: "9835758",
            authorName: "mist",
            avatarURL: nil,
            authorProfileURL: URL(string: "https://www.nodeseek.com/space/31037"),
            floorText: "#1",
            createdAtText: "刚刚",
            contentHTML: "<p>第一行<br>第二行</p><p><a href=\"/post-1-1\">链接文本</a></p>",
            signatureHTML: "<p>签名不应该出现</p>"
        )

        let text = CommentCopyTextFormatter.plainText(for: comment, baseURL: NodeSeekSite.baseURL)

        #expect(text == "第一行\n第二行\n链接文本")
    }

    @Test func postCopyTextUsesOnlyPostBodyPlainText() {
        let header = PostDetailHeaderContent(
            postID: "703863",
            title: "标题不应该出现",
            authorName: "mist",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>正文第一行<br>正文第二行</p>",
            signatureHTML: "<p>签名不应该出现</p>"
        )

        let text = CommentCopyTextFormatter.plainText(for: header, baseURL: NodeSeekSite.baseURL)

        #expect(text == "正文第一行\n正文第二行")
    }

    @Test func copySheetCopiesSelectedReplyTextAndDefaultsToAllText() throws {
        var copiedStrings: [String] = []
        let viewController = CommentCopySheetViewController(
            text: "第一行\n第二行",
            pasteboardStringWriter: { copiedStrings.append($0) }
        )

        viewController.loadViewIfNeeded()

        let textView = try #require(viewController.view.firstTextView(accessibilityIdentifier: "comment-copy-text-view"))
        #expect(textView.text == "第一行\n第二行")
        #expect(textView.selectedRange == NSRange(location: 0, length: (textView.text as NSString).length))

        textView.selectedRange = NSRange(location: 4, length: 3)
        viewController.copySelection()
        textView.selectedRange = NSRange(location: 0, length: 0)
        viewController.copySelection()

        #expect(copiedStrings == ["第二行", "第一行\n第二行"])
    }

    @Test func copySheetPrimaryButtonUsesDarkModeFriendlyColor() throws {
        let viewController = CommentCopySheetViewController(
            text: "回复内容",
            pasteboardStringWriter: { _ in }
        )
        viewController.overrideUserInterfaceStyle = .dark

        viewController.loadViewIfNeeded()

        let copyButton = try #require(viewController.view.firstButton(accessibilityIdentifier: "comment-copy-selected-button"))
        let backgroundColor = try #require(copyButton.configuration?.baseBackgroundColor)
        let foregroundColor = try #require(copyButton.configuration?.baseForegroundColor)
        let darkTrait = UITraitCollection(userInterfaceStyle: .dark)
        #expect(backgroundColor.resolvedColor(with: darkTrait).isSameColor(as: UIColor.systemBlue.resolvedColor(with: darkTrait)))
        #expect(foregroundColor.resolvedColor(with: darkTrait).isSameColor(as: UIColor.white))
    }

    @Test func avatarContextMenuOnlyShowsProfilePreviewAndBodyMenuOnlyShowsReplyActions() {
        let comment = Comment(
            id: "9835758",
            authorName: "mist",
            avatarURL: nil,
            authorProfileURL: URL(string: "https://www.nodeseek.com/space/31037"),
            floorText: "#1",
            createdAtText: "刚刚",
            contentHTML: "<p>回复内容</p>"
        )
        let node = CommentCellNode(
            comment: comment,
            renderedBody: [],
            onImageTapped: { _, _ in },
            onTextLayoutInvalidated: {}
        )

        #expect(node.debugAvatarContextMenuActionTitles == [])
        #expect(node.debugAvatarContextMenuHasPreview)
        #expect(node.debugBodyContextMenuActionTitles == ["复制", "投放鸡腿"])
        #expect(node.debugBodyContextMenuHasPreview == false)
    }

    @Test func postBodyContextMenuOnlyShowsCopyAction() {
        let header = PostDetailHeaderContent(
            postID: "703863",
            title: "帖子标题",
            authorName: "mist",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>帖子正文</p>"
        )
        let node = PostBodyCellNode(
            content: header,
            renderedContent: [],
            onImageTapped: { _, _ in },
            onTextLayoutInvalidated: {}
        )

        #expect(node.debugBodyContextMenuActionTitles == ["复制"])
        #expect(node.debugBodyContextMenuHasPreview == false)
    }
}

private extension UIView {
    func firstTextView(accessibilityIdentifier: String) -> UITextView? {
        if let textView = self as? UITextView, textView.accessibilityIdentifier == accessibilityIdentifier {
            return textView
        }

        for subview in subviews {
            if let matched = subview.firstTextView(accessibilityIdentifier: accessibilityIdentifier) {
                return matched
            }
        }

        return nil
    }

    func firstButton(accessibilityIdentifier: String) -> UIButton? {
        if let button = self as? UIButton, button.accessibilityIdentifier == accessibilityIdentifier {
            return button
        }

        for subview in subviews {
            if let matched = subview.firstButton(accessibilityIdentifier: accessibilityIdentifier) {
                return matched
            }
        }

        return nil
    }
}

private extension UIColor {
    func isSameColor(as other: UIColor) -> Bool {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        var otherRed: CGFloat = 0
        var otherGreen: CGFloat = 0
        var otherBlue: CGFloat = 0
        var otherAlpha: CGFloat = 0

        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        other.getRed(&otherRed, green: &otherGreen, blue: &otherBlue, alpha: &otherAlpha)

        return abs(red - otherRed) < 0.001
            && abs(green - otherGreen) < 0.001
            && abs(blue - otherBlue) < 0.001
            && abs(alpha - otherAlpha) < 0.001
    }
}
