//
//  PostDetailViewControllerTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/4/27.
//

import Foundation
import AsyncDisplayKit
import DTCoreText
import Testing
import UIKit
@testable import nodeseek

@MainActor
struct PostDetailViewControllerTests {
    @Test func startsWithSkeletonRowsEvenWhenInitialHeaderExists() throws {
        let post = PostSummary(
            id: "703863",
            title: "列表标题",
            url: URL(string: "https://www.nodeseek.com/post-703863-1")!,
            authorName: "ipv4",
            nodeName: "日常",
            replyCount: 2,
            lastActivityText: "刚刚",
            avatarURL: URL(string: "https://www.nodeseek.com/avatar/34378.png")
        )
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(
            presenter: presenter,
            initialHeader: PostDetailHeaderContent(post: post)
        )

        viewController.loadViewIfNeeded()

        let tableView = try #require(viewController.view.firstSubview(of: UITableView.self))
        #expect(tableView.tableHeaderView == nil)
        #expect(viewController.debugNumberOfRowsForTests() == 5)

        viewController.render(detail: PostDetail(
            id: "703863",
            title: "详情标题",
            authorName: "ipv4",
            avatarURL: URL(string: "https://www.nodeseek.com/avatar/34378.png"),
            metadataText: "36min ago · 日常",
            contentHTML: "<p>正文</p>",
            comments: [
                Comment(id: "1", authorName: "a", avatarURL: nil, floorText: "#1", createdAtText: "1min ago", contentHTML: "<p>评论一</p>"),
                Comment(id: "2", authorName: "b", avatarURL: nil, floorText: "#2", createdAtText: "2min ago", contentHTML: "<p>评论二</p>")
            ],
            replyForm: nil
        ))

        #expect(viewController.debugNumberOfRowsForTests() == 3)
    }

    @Test func showsSkeletonRowsWhileInitialDetailIsLoading() throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)

        viewController.loadViewIfNeeded()
        viewController.showLoading()

        _ = try #require(viewController.view.firstSubview(of: UITableView.self))
        #expect(viewController.debugNumberOfRowsForTests() == 5)

        viewController.render(detail: PostDetail(
            id: "703863",
            title: "详情标题",
            authorName: "ipv4",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>正文</p>",
            comments: [],
            replyForm: nil
        ))
        #expect(viewController.debugNumberOfRowsForTests() == 1)
    }

    @Test func addsRefreshButtonAndCanTriggerReload() throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)

        viewController.loadViewIfNeeded()

        let items = try #require(viewController.navigationItem.rightBarButtonItems)
        #expect(items.count == 2)
        let refreshButton = try #require(items.first { $0.accessibilityLabel == "刷新" })
        let action = try #require(refreshButton.action)
        _ = (refreshButton.target as AnyObject).perform(action)
        #expect(presenter.loadCount == 2)
    }

    @Test func detailTextureCellsCanBeConstructedOffMainThread() async throws {
        let header = PostDetailHeaderContent(
            postID: "703863",
            title: "标题",
            authorName: "ipv4",
            avatarURL: URL(string: "https://www.nodeseek.com/avatar/34378.png"),
            metadataText: "刚刚",
            contentHTML: "<p>正文</p>"
        )
        let comment = Comment(
            id: "1",
            authorName: "a",
            avatarURL: URL(string: "https://www.nodeseek.com/avatar/1.png"),
            floorText: "#1",
            createdAtText: "1min ago",
            contentHTML: "<p>评论</p>"
        )

        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let attributedText = NSAttributedString(string: "正文")
                let renderedContent: [RenderedContentBlock] = [.text(attributedText)]
                _ = PostBodyCellNode(
                    content: header,
                    renderedContent: renderedContent,
                    onImageTapped: { _, _ in },
                    onTextLayoutInvalidated: {}
                ).layoutThatFits(ASSizeRange(
                    min: .zero,
                    max: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
                ))
                _ = CommentCellNode(
                    comment: comment,
                    renderedBody: renderedContent,
                    onImageTapped: { _, _ in },
                    onTextLayoutInvalidated: {}
                ).layoutThatFits(ASSizeRange(
                    min: .zero,
                    max: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
                ))
                continuation.resume()
            }
        }
    }

    @Test func tableNodeKeepsViewportWidthAndMeasuresContentHeight() {
        let table = RenderedTableBlock(rows: [
            .init(cells: [
                .init(text: "Plan", isHeader: true),
                .init(text: "A very long column header", isHeader: true)
            ], isHeader: true),
            .init(cells: [
                .init(text: "Starter", isHeader: false),
                .init(text: "Enough content to require a real row height", isHeader: false)
            ], isHeader: false)
        ])
        let node = DetailTableNode(table: table, onImageTapped: { _, _ in })
        let layout = node.layoutThatFits(ASSizeRange(
            min: .zero,
            max: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
        ))

        #expect(layout.size.width == 320)
        #expect(layout.size.height > 0)
    }

    @Test func tableNodeAllocatesStableHeightForImageCells() throws {
        let imageURL = try #require(URL(string: "https://github.com/xykt/NetQuality/raw/main/res/v4_cn.png"))
        let table = RenderedTableBlock(rows: [
            .init(cells: [
                .init(text: "IPv4测试结果", isHeader: true)
            ], isHeader: true),
            .init(cells: [
                .init(text: "", imageURL: imageURL, isHeader: false)
            ], isHeader: false)
        ])
        let layout = DetailTableLayout.measure(
            table: table,
            constrainedSize: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
        )

        #expect(layout.width == 320)
        #expect(layout.height >= DetailTableLayout.imageHeight + 42)
    }

    @Test func tableNodeExpandsHeightForExplicitTextLines() {
        let singleLineTable = RenderedTableBlock(rows: [
            .init(cells: [
                .init(text: "第一行 第二行 第三行", isHeader: false)
            ], isHeader: false)
        ])
        let multiLineTable = RenderedTableBlock(rows: [
            .init(cells: [
                .init(text: "第一行\n第二行\n第三行", isHeader: false)
            ], isHeader: false)
        ])

        let singleLineHeight = DetailTableLayout.measure(
            table: singleLineTable,
            constrainedSize: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
        ).height
        let multiLineHeight = DetailTableLayout.measure(
            table: multiLineTable,
            constrainedSize: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
        ).height

        #expect(multiLineHeight > singleLineHeight)
    }

    @Test func codeBlockNodeKeepsViewportWidthForLongLines() {
        let codeBlock = RenderedCodeBlock(text: String(repeating: "A", count: 160))
        let layout = DetailCodeBlockLayout.measure(
            codeBlock: codeBlock,
            constrainedSize: CGSize(width: 180, height: CGFloat.greatestFiniteMagnitude)
        )

        #expect(layout.width == 180)
        #expect(DetailCodeBlockLayout.naturalCodeWidth(for: codeBlock.text) > layout.width)
    }

    @Test func codeBlockContentWidthDoesNotForceExtraScrollForShortLines() {
        let codeBlock = RenderedCodeBlock(text: "let value = 1")

        #expect(DetailCodeBlockLayout.contentWidth(for: codeBlock.text, viewportWidth: 180) == 180)
    }

    @Test func codeBlockCopyButtonCopiesFullText() throws {
        let codeBlock = RenderedCodeBlock(text: "line 1\nline 2")
        let view = DetailCodeBlockView(codeBlock: codeBlock)
        view.frame = CGRect(x: 0, y: 0, width: 240, height: 120)
        view.layoutIfNeeded()
        UIPasteboard.general.string = nil

        let button = try #require(view.firstButton(accessibilityIdentifier: "detail-code-copy-button"))
        button.sendActions(for: .touchUpInside)

        #expect(UIPasteboard.general.string == codeBlock.text)
    }

    @Test func resolvesNodeSeekPostLinksToNativeDetail() throws {
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let url = try #require(URL(string: "/post-704174-2#8", relativeTo: baseURL)?.absoluteURL)

        let destination = try #require(PostDetailLinkResolver.destination(for: url, baseURL: baseURL))

        guard case .nativePost(let postID, let page, let resolvedURL) = destination else {
            Issue.record("Expected native post destination")
            return
        }
        #expect(postID == "704174")
        #expect(page == 2)
        #expect(resolvedURL.absoluteString == "https://www.nodeseek.com/post-704174-2#8")
    }

    @Test func resolvesCurrentPageHashLinksToCurrentPageAnchor() throws {
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let url = try #require(URL(string: "#4", relativeTo: baseURL)?.absoluteURL)

        let destination = try #require(PostDetailLinkResolver.destination(
            for: url,
            baseURL: baseURL,
            currentPostID: "704174",
            currentPage: 1
        ))

        guard case .currentPageAnchor(let anchorID) = destination else {
            Issue.record("Expected current page anchor destination")
            return
        }
        #expect(anchorID == "4")
    }

    @Test func resolvesZeroHashLinksToOwnerAnchor() throws {
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let url = try #require(URL(string: "#0", relativeTo: baseURL)?.absoluteURL)

        let destination = try #require(PostDetailLinkResolver.destination(
            for: url,
            baseURL: baseURL,
            currentPostID: "704174",
            currentPage: 1
        ))

        guard case .currentPageAnchor(let anchorID) = destination else {
            Issue.record("Expected current page anchor destination")
            return
        }
        #expect(anchorID == "0")
    }

    @Test func resolvesCurrentPostSamePageFragmentLinksToCurrentPageAnchor() throws {
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let url = try #require(URL(string: "/post-704174-1#4", relativeTo: baseURL)?.absoluteURL)

        let destination = try #require(PostDetailLinkResolver.destination(
            for: url,
            baseURL: baseURL,
            currentPostID: "704174",
            currentPage: 1
        ))

        guard case .currentPageAnchor(let anchorID) = destination else {
            Issue.record("Expected current page anchor destination")
            return
        }
        #expect(anchorID == "4")
    }

    @Test func parsesCommentAnchorIDFromDetailFixture() throws {
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let html = try FixtureLoader.html(named: "post-703863-1")

        let detail = try KannaNodeSeekParser(baseURL: baseURL).parsePostDetail(
            html: html,
            url: URL(string: "https://www.nodeseek.com/post-703863-1")!
        )

        #expect(detail.comments.first?.anchorID == "4")
    }

    @Test func resolvesOtherNodeSeekLinksToWebView() throws {
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let url = try #require(URL(string: "/member?t=linda", relativeTo: baseURL)?.absoluteURL)

        let destination = try #require(PostDetailLinkResolver.destination(for: url, baseURL: baseURL))

        guard case .web(let resolvedURL) = destination else {
            Issue.record("Expected web destination")
            return
        }
        #expect(resolvedURL.absoluteString == "https://www.nodeseek.com/member?t=linda")
    }

    @Test func resolvesExternalLinksToSafari() throws {
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let url = try #require(URL(string: "https://example.com/path"))

        let destination = try #require(PostDetailLinkResolver.destination(for: url, baseURL: baseURL))

        guard case .safari(let resolvedURL) = destination else {
            Issue.record("Expected safari destination")
            return
        }
        #expect(resolvedURL.absoluteString == "https://example.com/path")
    }

    @Test func resolvesNodeSeekJumpExternalLinksToSafari() throws {
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let url = try #require(URL(string: "/jump?to=https%3A%2F%2Fshop.023168.xyz%2F", relativeTo: baseURL)?.absoluteURL)

        let destination = try #require(PostDetailLinkResolver.destination(for: url, baseURL: baseURL))

        guard case .safari(let resolvedURL) = destination else {
            Issue.record("Expected decoded jump destination to open in Safari")
            return
        }
        #expect(resolvedURL.absoluteString == "https://shop.023168.xyz/")
    }

    @Test func richTextNodeKeepsMeasuredHeightStableAfterNormalImageLoads() throws {
        let imageURL = try #require(URL(string: "https://i.111666.best/image/network.webp"))
        let blocks = DTCoreTextHTMLContentRenderer().render(
            fragment: "<p><img src=\"\(imageURL.absoluteString)\" alt=\"image\"></p><p>正文</p>",
            baseURL: URL(string: "https://www.nodeseek.com")!,
            maxImageWidth: 320
        )
        let attributedText = try #require(blocks.compactMap { block -> NSAttributedString? in
            guard case .text(let text) = block else { return nil }
            return text
        }.first)
        let node = DetailRichTextNode(
            attributedText: attributedText,
            onImageTapped: { _, _ in },
            onLayoutInvalidated: {}
        )
        let constrainedSize = ASSizeRange(
            min: .zero,
            max: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
        )

        let initialHeight = node.layoutThatFits(constrainedSize).size.height
        let didUpdate = node.updateAttachmentLayout(
            matching: imageURL,
            originalSize: CGSize(width: 1200, height: 800),
            displaySize: DetailImageLayout.fixedNormalImageSize(maxWidth: 320)
        )
        let updatedHeight = node.layoutThatFits(constrainedSize).size.height

        #expect(didUpdate)
        #expect(updatedHeight == initialHeight)
    }

    @Test func richTextNodeMeasuresTextAfterImageAndLineBreak() throws {
        let imageURL = try #require(URL(string: "https://cdn.nodeimage.com/i/E7rnyCXgl36hsqI97dJqQxtLPjZBruA1.webp"))
        let blocks = DTCoreTextHTMLContentRenderer().render(
            fragment: """
            <p><img src="\(imageURL.absoluteString)" alt="image" class=""><br>
            上个月啥都没干， ip就被送中，拉回来后，今天发现又被送中了 <img class="sticker" src="/static/image/sticker/yct/015.gif" loading="lazy" alt="yct015"></p>
            """,
            baseURL: URL(string: "https://www.nodeseek.com")!,
            maxImageWidth: 320
        )
        let attributedText = try #require(blocks.compactMap { block -> NSAttributedString? in
            guard case .text(let text) = block else { return nil }
            return text
        }.first)
        #expect(attributedText.string.contains("上个月啥都没干"))

        let node = DetailRichTextNode(
            attributedText: attributedText,
            onImageTapped: { _, _ in },
            onLayoutInvalidated: {}
        )
        let layout = node.layoutThatFits(ASSizeRange(
            min: .zero,
            max: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
        ))

        #expect(layout.size.height > DetailImageLayout.fixedNormalImageSize(maxWidth: 320).height + 40)
    }

    @Test func richTextViewUsesVideoStickerViewForVideoStickerAttachment() throws {
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let blocks = DTCoreTextHTMLContentRenderer().render(
            fragment: """
            <p><video class="sticker" width="100" height="100">
                <source src="/static/image/sticker/emoji/00.webm" type="video/webm">
                <source src="/static/image/sticker/emoji/00.mp4" type="video/mp4">
            </video></p>
            """,
            baseURL: baseURL,
            maxImageWidth: 320
        )
        let attributedText = try #require(blocks.compactMap { block -> NSAttributedString? in
            guard case .text(let text) = block else { return nil }
            return text
        }.first)
        var attachment: DTTextAttachment?
        attributedText.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributedText.length)
        ) { value, _, stop in
            guard let value = value as? DTTextAttachment else { return }
            attachment = value
            stop.pointee = true
        }

        let richTextView = DetailRichTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 120))
        let attachmentView = richTextView.attributedTextContentView(
            richTextView,
            viewFor: try #require(attachment),
            frame: CGRect(x: 0, y: 0, width: 65, height: 65)
        )

        #expect(String(describing: type(of: try #require(attachmentView))).contains("DetailInlineVideoStickerView"))
    }

    @Test func richTextNodeUsesDTCoreTextHeightForFixture() throws {
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let html = try FixtureLoader.html(named: "post-705039-1")
        let detail = try KannaNodeSeekParser(baseURL: baseURL).parsePostDetail(
            html: html,
            url: URL(string: "https://www.nodeseek.com/post-705039-1")!
        )
        let blocks = DTCoreTextHTMLContentRenderer().render(
            fragment: detail.contentHTML,
            baseURL: baseURL,
            maxImageWidth: 320
        )
        let attributed = try #require(blocks.compactMap { block -> NSAttributedString? in
            guard case .text(let text) = block else { return nil }
            return text
        }.first)
        let node = DetailRichTextNode(
            attributedText: attributed,
            onImageTapped: { _, _ in },
            onLayoutInvalidated: {}
        )
        let layout = node.layoutThatFits(ASSizeRange(
            min: .zero,
            max: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
        ))
        let layouter = try #require(DTCoreTextLayouter(attributedString: attributed))
        let layoutFrame = try #require(layouter.layoutFrame(
            with: CGRect(x: 0, y: 0, width: 320, height: 16_777_215),
            range: NSRange(location: 0, length: 0)
        ))
        let expectedHeight = ceil(layoutFrame.frame.maxY)

        #expect(layout.size.height == expectedHeight)
    }

    @Test func richTextNodePrefersDTCoreTextHeightWhenBoundingHeightIsLarger() {
        let height = DetailRichTextNode.resolvedMeasuredHeight(
            dtCoreTextHeight: 120,
            boundingHeight: 300
        )

        #expect(height == 120)
    }

    @Test func richTextNodeUsesDefaultWidthForUnboundedMeasurement() {
        let width = DetailRichTextNode.resolvedMeasureWidth(.infinity)

        #expect(width == 320)
    }

    @Test func richTextAttachmentViewFrameUsesAttachmentDisplaySize() {
        let proposedFrame = CGRect(x: 0, y: 8, width: 320, height: 70)
        let frame = DetailRichTextView.attachmentViewFrame(
            proposedFrame: proposedFrame,
            displaySize: CGSize(width: 65, height: 65)
        )

        #expect(frame.width == 65)
        #expect(frame.height == 65)
        #expect(frame.minX == proposedFrame.minX)
        #expect(frame.midY == proposedFrame.midY)
    }
}

@MainActor
struct PostDetailLoginViewControllerTests {
    @Test func loginRequiredStateShowsLoginButtonAndSendsTapToPresenter() throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)

        viewController.loadViewIfNeeded()
        viewController.renderLoginRequired(message: "本帖需要注册用户才能查看😭")

        let button = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-detail-login-button"))
        #expect(button.configuration?.title == "登录查看")
        #expect(button.configuration?.baseBackgroundColor == .label)
        #expect(button.configuration?.baseForegroundColor == .systemBackground)
        #expect(button.configuration?.cornerStyle == .capsule)
        #expect(button.isHidden == false)

        button.sendActions(for: .touchUpInside)

        #expect(presenter.didTapLoginCount == 1)
    }

    @Test func loginButtonIsHiddenBeforeLoginRequiredRender() throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)

        viewController.loadViewIfNeeded()

        let button = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-detail-login-button"))
        #expect(button.isHidden)
    }

    @Test func renderDetailHidesLoginButton() throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)

        viewController.loadViewIfNeeded()
        viewController.renderLoginRequired(message: "本帖需要注册用户才能查看😭")
        viewController.render(detail: PostDetail(
            id: "703863",
            title: "详情标题",
            authorName: "ipv4",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>正文</p>",
            comments: [],
            replyForm: nil
        ))

        let button = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-detail-login-button"))
        #expect(button.isHidden)
    }

    @Test func showLoadingHidesVisibleLoginButton() throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)

        viewController.loadViewIfNeeded()
        viewController.renderLoginRequired(message: "本帖需要注册用户才能查看😭")

        let button = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-detail-login-button"))
        #expect(button.isHidden == false)

        viewController.showLoading()

        #expect(button.isHidden)
    }
}

private final class SpyPostDetailPresenter: PostDetailPresenterProtocol {
    private(set) var loadCount = 0
    private(set) var didTapLoginCount = 0

    func viewDidLoad() {
        loadCount += 1
    }

    func didTapLogin() {
        didTapLoginCount += 1
    }
}

private extension UIView {
    func firstSubview<T: UIView>(of type: T.Type) -> T? {
        if let matched = self as? T {
            return matched
        }

        for subview in subviews {
            if let matched = subview.firstSubview(of: type) {
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
