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
        #expect(node.debugAuthorContextMenuHasPreview == false)
    }

    @Test func longPressOnPostAuthorAvatarAndNamePreviewsProfile() throws {
        let profileURL = try #require(URL(string: "https://www.nodeseek.com/space/31037"))
        var opened: [URL] = []
        let node = makePostBodyNode(profileURL: profileURL, onAuthorTapped: { opened.append($0) })
        let host = try display(node)

        let avatar = try #require(host.firstView(accessibilityIdentifier: "post-author-avatar"))
        let name = try #require(host.firstView(accessibilityIdentifier: "post-author-name"))

        #expect(try authorMenuIdentifier(from: node, on: avatar)?.hasSuffix("-author") == true)
        #expect(try authorMenuIdentifier(from: node, on: name)?.hasSuffix("-author") == true)
        #expect(node.makeAuthorPreviewViewController() is UserProfileViewController)
        #expect(opened.isEmpty)

        let interaction = try #require(avatar.interactions.compactMap { $0 as? UIContextMenuInteraction }.first)
        let configuration = try #require(node.contextMenuInteraction(interaction, configurationForMenuAtLocation: .zero))
        let animator = ContextMenuCommitAnimator()
        node.contextMenuInteraction(interaction, willPerformPreviewActionForMenuWith: configuration, animator: animator)
        animator.runCompletions()
        #expect(opened == [profileURL])
    }

    @Test func longPressOnCommentAuthorNamePreviewsProfile() throws {
        let profileURL = try #require(URL(string: "https://www.nodeseek.com/space/31037"))
        let comment = Comment(
            id: "9835758",
            authorName: "mist",
            avatarURL: nil,
            authorProfileURL: profileURL,
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
        let host = try display(node)

        let avatar = try #require(host.firstView(accessibilityIdentifier: "comment-author-avatar"))
        let name = try #require(host.firstView(accessibilityIdentifier: "comment-author-name"))
        #expect(try authorMenuIdentifier(from: node, on: avatar)?.hasSuffix("-avatar") == true)
        #expect(try authorMenuIdentifier(from: node, on: name)?.hasSuffix("-avatar") == true)
        #expect(node.makeAuthorPreviewViewController() is UserProfileViewController)
    }

    @Test func authorFilterMenuItemsAppendAfterExistingActions() {
        let comment = Comment(
            id: "9835758",
            authorName: "mist",
            avatarURL: nil,
            floorText: "#1",
            createdAtText: "刚刚",
            contentHTML: "<p>回复内容</p>"
        )
        var filteredCommentIDs: [String] = []
        let commentNode = CommentCellNode(
            comment: comment,
            renderedBody: [],
            onImageTapped: { _, _ in },
            authorFilterMenuTitle: "只看 TA",
            onAuthorFilterTapped: { filteredCommentIDs.append($0.id) },
            onTextLayoutInvalidated: {}
        )
        let header = PostDetailHeaderContent(
            postID: "703863",
            title: "帖子标题",
            authorName: "mist",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>帖子正文</p>"
        )
        let bodyNode = PostBodyCellNode(
            content: header,
            renderedContent: [],
            onImageTapped: { _, _ in },
            authorFilterMenuTitle: "只看楼主",
            onTextLayoutInvalidated: {}
        )

        #expect(commentNode.debugBodyContextMenuActionTitles == ["复制", "投放鸡腿", "只看 TA"])
        #expect(bodyNode.debugBodyContextMenuActionTitles == ["复制", "只看楼主"])
    }
}

@MainActor
private func makePostBodyNode(
    profileURL: URL?,
    onAuthorTapped: @escaping (URL) -> Void = { _ in }
) -> PostBodyCellNode {
    let header = PostDetailHeaderContent(
        postID: "703863",
        title: "帖子标题",
        authorName: "mist",
        avatarURL: URL(string: "https://www.nodeseek.com/avatar/31037.png"),
        authorProfileURL: profileURL,
        metadataText: "刚刚",
        contentHTML: "<p>帖子正文</p>"
    )
    return PostBodyCellNode(
        content: header,
        renderedContent: [],
        onImageTapped: { _, _ in },
        onAuthorTapped: onAuthorTapped,
        onTextLayoutInvalidated: {}
    )
}

@MainActor
private func display(_ node: ASDisplayNode) throws -> UIView {
    let size = node.layoutThatFits(ASSizeRange(
        min: .zero,
        max: CGSize(width: 390, height: 2_000)
    )).size
    node.frame = CGRect(origin: .zero, size: size)
    let host = UIView(frame: node.frame)
    host.addSubview(node.view)
    node.layoutIfNeeded()
    node.recursivelyEnsureDisplaySynchronously(true)
    return host
}

@MainActor
private func authorMenuIdentifier(
    from delegate: UIContextMenuInteractionDelegate,
    on view: UIView
) throws -> String? {
    let interaction = try #require(view.interactions.compactMap { $0 as? UIContextMenuInteraction }.first)
    let configuration = try #require(delegate.contextMenuInteraction(interaction, configurationForMenuAtLocation: .zero))
    return configuration.identifier as? String
}

private final class ContextMenuCommitAnimator: NSObject, UIContextMenuInteractionCommitAnimating {
    var preferredCommitStyle: UIContextMenuInteractionCommitStyle = .pop
    var previewViewController: UIViewController?
    private var completions: [() -> Void] = []

    func addAnimations(_ animations: @escaping () -> Void) {}

    func addCompletion(_ completion: @escaping () -> Void) {
        completions.append(completion)
    }

    func runCompletions() {
        completions.forEach { $0() }
    }
}

private extension UIView {
    func firstView(accessibilityIdentifier: String) -> UIView? {
        if self.accessibilityIdentifier == accessibilityIdentifier {
            return self
        }
        for subview in subviews {
            if let matched = subview.firstView(accessibilityIdentifier: accessibilityIdentifier) {
                return matched
            }
        }
        return nil
    }

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
