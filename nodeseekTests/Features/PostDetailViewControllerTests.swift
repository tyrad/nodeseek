//
//  PostDetailViewControllerTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/4/27.
//

import Foundation
import AVFoundation
import AsyncDisplayKit
import DTCoreText
import Testing
import UIKit
@testable import nodeseek

@Suite(.serialized)
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
        #expect(viewController.testRowCount(inSection: 0) == 5)

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
        ))

        #expect(viewController.testRowCount(inSection: 0) == 4)
    }

    @Test func showsSkeletonRowsWhileInitialDetailIsLoading() throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)

        viewController.loadViewIfNeeded()
        viewController.showLoading()

        _ = try #require(viewController.view.firstSubview(of: UITableView.self))
        #expect(viewController.testRowCount(inSection: 0) == 5)

        viewController.render(detail: PostDetail(
            id: "703863",
            title: "详情标题",
            authorName: "ipv4",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>正文</p>",
            comments: [],
        ))
        #expect(viewController.testRowCount(inSection: 0) == 1)
    }

    @Test func detailWithPaginationShowsPageScrubberOverlayWithoutPagerRows() throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)

        viewController.loadViewIfNeeded()
        viewController.render(detail: PostDetail(
            id: "703863",
            title: "详情标题",
            authorName: "ipv4",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>正文</p>",
            comments: [
                Comment(id: "1", authorName: "a", avatarURL: nil, floorText: "#1", createdAtText: "1min ago", contentHTML: "<p>评论一</p>"),
                Comment(id: "2", authorName: "b", avatarURL: nil, floorText: "#2", createdAtText: "2min ago", contentHTML: "<p>评论二</p>")
            ],
            page: 1,
            pagination: PostDetailPagination(
                currentPage: 1,
                items: [
                    PostDetailPageItem(page: 1, url: URL(string: "https://www.nodeseek.com/post-703863-1"), isCurrent: true),
                    PostDetailPageItem(page: 2, url: URL(string: "https://www.nodeseek.com/post-703863-2"), isCurrent: false)
                ],
                previousPage: nil,
                nextPage: 2
            )
        ))

        _ = try #require(viewController.view.firstSubview(of: UITableView.self))
        #expect(viewController.testRowCount(inSection: 0) == 4)
        let scrubber = try #require(viewController.view.firstSubview(of: PageScrubberView.self))
        #expect(scrubber.isHidden == false)
    }

    @Test func pageScrubberDragToBottomSelectsLastPage() throws {
        var selectedPages: [Int] = []
        let view = PageScrubberView()
        view.onPageSelected = { selectedPages.append($0) }
        view.configure(currentPage: 1, totalPages: 100, isLoading: false)
        view.frame = CGRect(x: 0, y: 0, width: 58, height: 220)

        view.beginScrubbingForTesting(at: 110)
        view.updateScrubbingForTesting(to: 215)
        view.endScrubbingForTesting(at: 215)

        #expect(selectedPages == [100])
    }

    @Test func pageScrubberShowsCurrentTotalText() throws {
        let view = PageScrubberView()
        view.configure(currentPage: 2, totalPages: 5, isLoading: false)

        let toggle = try #require(view.firstButton(accessibilityIdentifier: "page-scrubber-toggle-button"))
        #expect(toggle.configuration?.title == "2/5")
    }

    @Test func pageScrubberUsesCompactAlphaAndExpandsOpacityWhileDragging() throws {
        let view = PageScrubberView()
        view.configure(currentPage: 2, totalPages: 5, isLoading: false)
        view.frame = CGRect(x: 0, y: 0, width: 58, height: 220)

        #expect(abs(view.alpha - 0.62) < 0.001)

        view.beginScrubbingForTesting(at: 110)

        #expect(view.alpha == 1)
    }

    @Test func pageScrubberUsesAdaptiveSingleLineWidthForLongPageText() throws {
        let view = PageScrubberView()
        view.configure(currentPage: 100, totalPages: 100, isLoading: false)
        view.layoutIfNeeded()

        let toggle = try #require(view.firstButton(accessibilityIdentifier: "page-scrubber-toggle-button"))
        #expect(toggle.titleLabel?.numberOfLines == 1)
        #expect(view.testWidthConstant() > 58)
    }

    @Test func pageScrubberShowsSpinnerWhileLoading() throws {
        let view = PageScrubberView()
        view.configure(currentPage: 2, totalPages: 5, isLoading: true)

        let indicator = try #require(view.firstSubview(of: UIActivityIndicatorView.self))
        #expect(indicator.isAnimating)
    }

    @Test func pageScrubberSmallDragSelectsNearbyPage() throws {
        var selectedPages: [Int] = []
        let view = PageScrubberView()
        view.onPageSelected = { selectedPages.append($0) }
        view.configure(currentPage: 50, totalPages: 100, isLoading: false)
        view.frame = CGRect(x: 0, y: 0, width: 58, height: 220)

        view.beginScrubbingForTesting(at: 110)
        view.updateScrubbingForTesting(to: 118)
        view.endScrubbingForTesting(at: 118)

        #expect(selectedPages == [51])
    }

    @Test func pageScrubberDoesNotSelectWhileLoading() throws {
        var selectedPages: [Int] = []
        let view = PageScrubberView()
        view.onPageSelected = { selectedPages.append($0) }
        view.configure(currentPage: 1, totalPages: 100, isLoading: true)
        view.frame = CGRect(x: 0, y: 0, width: 58, height: 220)

        view.beginScrubbingForTesting(at: 110)
        view.updateScrubbingForTesting(to: 215)
        view.endScrubbingForTesting(at: 215)

        #expect(selectedPages.isEmpty)
    }

    @Test func pageScrubberEdgeTapOutsideVisibleBarOnlyShowsHUD() throws {
        var selectedPages: [Int] = []
        let view = PageScrubberView()
        view.onPageSelected = { selectedPages.append($0) }
        view.configure(currentPage: 50, totalPages: 100, isLoading: false)
        view.frame = CGRect(x: 0, y: 0, width: 58, height: 640)
        view.layoutIfNeeded()

        view.beginScrubbingForTesting(at: 24)
        view.endScrubbingForTesting(at: 24)

        #expect(selectedPages.isEmpty)
        #expect(view.alpha == 1)
    }

    @Test func pageScrubberOnlyHandlesTouchesNearVisibleControlWhenCollapsed() throws {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 640))
        let view = PageScrubberView()
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: 12),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        view.configure(currentPage: 50, totalPages: 100, isLoading: false)
        container.layoutIfNeeded()

        #expect(view.point(inside: CGPoint(x: 57, y: 24), with: nil) == false)
        #expect(view.point(inside: CGPoint(x: 57, y: 320), with: nil) == true)
    }

    @Test func selectingPageThroughDetailScrubberCallsPresenter() throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)

        viewController.loadViewIfNeeded()
        viewController.render(detail: PostDetail(
            id: "703863",
            title: "详情标题",
            authorName: "ipv4",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>正文</p>",
            comments: [
                Comment(id: "1", authorName: "a", avatarURL: nil, floorText: "#1", createdAtText: "1min ago", contentHTML: "<p>评论一</p>")
            ],
            page: 1,
            pagination: PostDetailPagination(
                currentPage: 1,
                items: [
                    PostDetailPageItem(page: 1, url: URL(string: "https://www.nodeseek.com/post-703863-1"), isCurrent: true),
                    PostDetailPageItem(page: 2, url: URL(string: "https://www.nodeseek.com/post-703863-2"), isCurrent: false)
                ],
                previousPage: nil,
                nextPage: 2
            )
        ))

        let scrubber = try #require(viewController.view.firstSubview(of: PageScrubberView.self))
        scrubber.frame = CGRect(x: 0, y: 0, width: 58, height: 220)
        scrubber.beginScrubbingForTesting(at: 110)
        scrubber.updateScrubbingForTesting(to: 215)
        scrubber.endScrubbingForTesting(at: 215)

        #expect(presenter.selectedPages == [2])
    }

    @Test func renderingOtherPageScrollsFirstCommentToTop() throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)

        viewController.loadViewIfNeeded()
        viewController.render(detail: PostDetail(
            id: "703863",
            title: "详情标题",
            authorName: "ipv4",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>原帖正文</p>",
            comments: [
                Comment(id: "1", authorName: "a", avatarURL: nil, floorText: "#1", createdAtText: "1min ago", contentHTML: "<p>评论一</p>")
            ],
            page: 1,
            pagination: PostDetailPagination(
                currentPage: 1,
                items: [
                    PostDetailPageItem(page: 1, url: URL(string: "https://www.nodeseek.com/post-703863-1"), isCurrent: true),
                    PostDetailPageItem(page: 2, url: URL(string: "https://www.nodeseek.com/post-703863-2"), isCurrent: false)
                ],
                previousPage: nil,
                nextPage: 2
            )
        ))

        viewController.render(detail: PostDetail(
            id: "703863",
            title: "详情标题",
            authorName: "ipv4",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "",
            comments: [
                Comment(id: "11", authorName: "b", avatarURL: nil, floorText: "#11", createdAtText: "刚刚", contentHTML: "<p>第二页评论</p>")
            ],
            page: 2,
            pagination: PostDetailPagination(
                currentPage: 2,
                items: [
                    PostDetailPageItem(page: 1, url: URL(string: "https://www.nodeseek.com/post-703863-1"), isCurrent: false),
                    PostDetailPageItem(page: 2, url: URL(string: "https://www.nodeseek.com/post-703863-2"), isCurrent: true)
                ],
                previousPage: 1,
                nextPage: nil
            )
        ))

        #expect(viewController.testPendingScrollRow() == 2)
    }

    @Test func pageLoadingKeepsHeaderAndShowsCommentSkeletonRows() throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)

        viewController.loadViewIfNeeded()
        viewController.render(detail: PostDetail(
            id: "703863",
            title: "详情标题",
            authorName: "ipv4",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>原帖正文</p>",
            comments: [
                Comment(id: "1", authorName: "a", avatarURL: nil, floorText: "#1", createdAtText: "1min ago", contentHTML: "<p>评论一</p>"),
                Comment(id: "2", authorName: "b", avatarURL: nil, floorText: "#2", createdAtText: "2min ago", contentHTML: "<p>评论二</p>")
            ],
            page: 1,
            pagination: PostDetailPagination(
                currentPage: 1,
                items: [
                    PostDetailPageItem(page: 1, url: URL(string: "https://www.nodeseek.com/post-703863-1"), isCurrent: true),
                    PostDetailPageItem(page: 2, url: URL(string: "https://www.nodeseek.com/post-703863-2"), isCurrent: false)
                ],
                previousPage: nil,
                nextPage: 2
            )
        ))

        viewController.showPageLoading()

        #expect(viewController.testRowCount(inSection: 0) == 6)
        #expect(viewController.testHeaderContent()?.contentHTML == "<p>原帖正文</p>")
    }

    @Test func renderingOtherPagePreservesExistingHeaderContent() throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)

        viewController.loadViewIfNeeded()
        viewController.render(detail: PostDetail(
            id: "703863",
            title: "详情标题",
            authorName: "ipv4",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>原帖正文</p>",
            comments: [
                Comment(id: "1", authorName: "a", avatarURL: nil, floorText: "#1", createdAtText: "1min ago", contentHTML: "<p>评论一</p>")
            ],
            page: 1,
            pagination: PostDetailPagination(
                currentPage: 1,
                items: [
                    PostDetailPageItem(page: 1, url: URL(string: "https://www.nodeseek.com/post-703863-1"), isCurrent: true),
                    PostDetailPageItem(page: 2, url: URL(string: "https://www.nodeseek.com/post-703863-2"), isCurrent: false)
                ],
                previousPage: nil,
                nextPage: 2
            )
        ))

        viewController.render(detail: PostDetail(
            id: "703863",
            title: "详情标题",
            authorName: "ipv4",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>第2页第一个回复</p>",
            comments: [
                Comment(id: "11", authorName: "c", avatarURL: nil, floorText: "#11", createdAtText: "刚刚", contentHTML: "<p>第二页评论</p>")
            ],
            page: 2,
            pagination: PostDetailPagination(
                currentPage: 2,
                items: [
                    PostDetailPageItem(page: 1, url: URL(string: "https://www.nodeseek.com/post-703863-1"), isCurrent: false),
                    PostDetailPageItem(page: 2, url: URL(string: "https://www.nodeseek.com/post-703863-2"), isCurrent: true)
                ],
                previousPage: 1,
                nextPage: nil
            )
        ))

        #expect(viewController.testRowCount(inSection: 0) == 3)
        #expect(viewController.testHeaderContent()?.contentHTML == "<p>原帖正文</p>")
    }

    @Test func renderingOtherPageKeepsPaginationWhenParserMissesPager() throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)

        viewController.loadViewIfNeeded()
        viewController.render(detail: PostDetail(
            id: "703863",
            title: "详情标题",
            authorName: "ipv4",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>原帖正文</p>",
            comments: [
                Comment(id: "1", authorName: "a", avatarURL: nil, floorText: "#1", createdAtText: "1min ago", contentHTML: "<p>评论一</p>")
            ],
            page: 1,
            pagination: PostDetailPagination(
                currentPage: 1,
                items: [
                    PostDetailPageItem(page: 1, url: URL(string: "https://www.nodeseek.com/post-703863-1"), isCurrent: true),
                    PostDetailPageItem(page: 2, url: URL(string: "https://www.nodeseek.com/post-703863-2"), isCurrent: false)
                ],
                previousPage: nil,
                nextPage: 2
            )
        ))

        viewController.render(detail: PostDetail(
            id: "703863",
            title: "详情标题",
            authorName: "ipv4",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>第2页第一个回复</p>",
            comments: [
                Comment(id: "11", authorName: "c", avatarURL: nil, floorText: "#11", createdAtText: "刚刚", contentHTML: "<p>第二页评论</p>")
            ],
            page: 2,
            pagination: nil
        ))

        #expect(viewController.testRowCount(inSection: 0) == 3)
    }

    @Test func addsMoreMenuAndCanTriggerReload() throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)

        viewController.loadViewIfNeeded()

        let items = try #require(viewController.navigationItem.rightBarButtonItems)
        #expect(items.count == 2)
        let moreButton = try #require(items.first { $0.accessibilityLabel == "更多" })
        _ = try #require(moreButton.menu?.children.first { $0.title == "刷新" } as? UIAction)
        viewController.refreshTapped()
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

    @Test func postBodyCellRefreshAppearanceRebuildsHeaderTitleText() {
        let header = PostDetailHeaderContent(
            postID: "703863",
            title: "主题切换标题",
            authorName: "ipv4",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>正文</p>"
        )
        let node = PostBodyCellNode(
            content: header,
            renderedContent: [],
            onImageTapped: { _, _ in },
            onTextLayoutInvalidated: {}
        )

        let didRefresh = node.refreshAppearanceForCurrentTraits()

        #expect(didRefresh)
        #expect(node.debugTitleAttributedText?.string == "主题切换标题")
    }

    @Test func commentCellRefreshAppearanceRebuildsAuthorNameText() {
        let comment = Comment(
            id: "1",
            authorName: "ipv4",
            avatarURL: nil,
            floorText: "#1",
            createdAtText: "刚刚",
            contentHTML: "<p>评论</p>"
        )
        let node = CommentCellNode(
            comment: comment,
            renderedBody: [],
            onImageTapped: { _, _ in },
            onTextLayoutInvalidated: {}
        )

        let didRefresh = node.refreshAppearanceForCurrentTraits()

        #expect(didRefresh)
        #expect(node.debugAuthorAttributedTitle?.string == "ipv4")
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

    @Test func unsupportedContentNodeUsesSafariIcon() throws {
        let nodes = DetailContentBlockNodeFactory.makeNodes(
            from: [.unsupported(reason: DTCoreTextHTMLContentRenderer.unsupportedXtermContentNotice)],
            onImageTapped: { _, _ in },
            onLinkTapped: { _ in },
            onTextLayoutInvalidated: {}
        )

        let node = try #require(nodes.first as? DetailUnsupportedContentNode)
        #expect(node.reason == DTCoreTextHTMLContentRenderer.unsupportedXtermContentNotice)
        #expect(node.iconSymbolName == "safari")
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

    @Test func currentPageAnchorOneTargetsFirstCommentInsteadOfHeader() throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)
        viewController.loadViewIfNeeded()
        viewController.render(detail: PostDetail(
            id: "703863",
            title: "详情标题",
            authorName: "ipv4",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>正文</p>",
            comments: [
                Comment(id: "1", authorName: "a", avatarURL: nil, floorText: "#1", createdAtText: "1min ago", contentHTML: "<p>一楼</p>"),
                Comment(id: "2", authorName: "b", avatarURL: nil, floorText: "#2", createdAtText: "2min ago", contentHTML: "<p>二楼</p>")
            ],
            page: 1,
            pagination: nil
        ))

        #expect(viewController.testCurrentPageAnchorRow(for: "0") == 0)
        #expect(viewController.testCurrentPageAnchorRow(for: "1") == 2)
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
            fragment: "<p>配图<img src=\"\(imageURL.absoluteString)\" alt=\"image\">正文</p>",
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

    @Test func richTextViewUsesVideoStickerViewForStickerClassVideoAttachment() throws {
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let blocks = DTCoreTextHTMLContentRenderer().render(
            fragment: """
            <p><video class="sticker" width="100" height="100">
                <source src="/static/image/emoji/00.mp4" type="video/mp4">
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

    @Test func richTextViewRefreshAppearanceRebuildsAttributedString() throws {
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let blocks = DTCoreTextHTMLContentRenderer().render(
            fragment: "<blockquote><p>引用内容</p></blockquote>",
            baseURL: baseURL,
            maxImageWidth: 320
        )
        let attributedText = try #require(blocks.compactMap { block -> NSAttributedString? in
            guard case .text(let text) = block else { return nil }
            return text
        }.first)

        let richTextView = DetailRichTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 120))
        richTextView.configure(
            attributedText,
            onImageTapped: nil,
            onLinkTapped: nil,
            onLayoutInvalidated: nil
        )

        let initialAttributedText = richTextView.debugAttributedString

        richTextView.refreshAppearanceForCurrentTraits()

        #expect(richTextView.debugAttributedString !== initialAttributedText)
    }

    @Test func videoStickerViewKeepsPlayerLayerHiddenUntilTapped() throws {
        let url = try #require(URL(string: "https://www.nodeseek.com/static/image/sticker/emoji/00.mp4"))
        let view = DetailInlineVideoStickerView(
            frame: CGRect(x: 0, y: 0, width: 65, height: 65),
            videoURL: url
        )
        view.layoutIfNeeded()

        let playerLayer = try #require(view.layer.sublayers?.compactMap { $0 as? AVPlayerLayer }.first)
        let playButton = try #require(view.firstSubview(of: UIButton.self))

        #expect(view.backgroundColor == .clear)
        #expect(view.isOpaque == false)
        #expect(playerLayer.isHidden)
        #expect(playButton.isUserInteractionEnabled == false)
    }

    @Test func videoAssetRequestCarriesBrowserContextForNodeSeekAssets() throws {
        let url = try #require(URL(string: "https://www.nodeseek.com/static/image/sticker/emoji/00.mp4"))
        let storage = HTTPCookieStorage.shared
        deleteVideoAssetTestCookies(from: storage)
        defer { deleteVideoAssetTestCookies(from: storage) }
        let cookie = try #require(HTTPCookie(properties: [
            .domain: ".nodeseek.com",
            .path: "/",
            .name: "video_asset_test_cookie",
            .value: "token",
            .secure: "TRUE",
            .expires: Date(timeIntervalSinceNow: 3600)
        ]))
        storage.setCookie(cookie)

        let options = DetailVideoAssetRequest.assetOptions(for: url, cookieStorage: storage)
        let cookies = try #require(options[AVURLAssetHTTPCookiesKey] as? [HTTPCookie])

        #expect(cookies.contains { $0.name == "video_asset_test_cookie" && $0.value == "token" })
        #expect(options[AVURLAssetHTTPUserAgentKey] as? String == WebRequestFingerprint.userAgent)
    }

    @Test func imageBlockUsesStablePlaceholderHeightForNormalImages() {
        let initialLayout = DetailImageBlockLayout.measure(
            originalSize: .zero,
            constrainedSize: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
        )
        let loadedLayout = DetailImageBlockLayout.measure(
            originalSize: CGSize(width: 1200, height: 800),
            constrainedSize: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
        )

        #expect(initialLayout.width == 320)
        #expect(initialLayout.height == 160)
        #expect(loadedLayout == initialLayout)
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

    @Test func detailUsesOnlyFloatingReplyEntry() throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)

        viewController.loadViewIfNeeded()
        viewController.render(detail: PostDetail(
            id: "703863",
            title: "详情标题",
            authorName: "ipv4",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>正文</p>",
            comments: []
        ))

        #expect(viewController.view.firstTextView(accessibilityIdentifier: "post-detail-comment-input") == nil)
        #expect(viewController.view.firstButton(accessibilityIdentifier: "post-detail-comment-send-button") == nil)
        #expect(viewController.view.firstLabel(accessibilityIdentifier: "post-detail-comment-placeholder-label") == nil)

        let floatingReplyButton = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-detail-reply-button"))
        #expect(floatingReplyButton.isHidden == false)
    }

    @Test func commentComposerAddsNonCancellingDismissKeyboardTapGesture() throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)

        viewController.loadViewIfNeeded()

        let tapGesture = try #require(viewController.view.gestureRecognizers?.compactMap { $0 as? UITapGestureRecognizer }.first)
        #expect(tapGesture.cancelsTouchesInView == false)
    }

    @Test func replyAndQuoteActionsUpdateComposerState() throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)
        let comment = Comment(
            id: "1",
            anchorID: "10",
            authorName: "netcup",
            avatarURL: nil,
            floorText: "#10",
            createdAtText: "1min ago",
            createdAtTitleText: "2026-04-29 13:58:43",
            contentHTML: "<p>第一段</p><p>第二段</p>"
        )

        viewController.loadViewIfNeeded()
        viewController.render(detail: PostDetail(
            id: "703863",
            title: "详情标题",
            authorName: "ipv4",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>正文</p>",
            comments: [],
        ))
        viewController.handleReply(to: comment)
        let contextLabel = try #require(viewController.view.firstLabel(accessibilityIdentifier: "post-detail-reply-context-label"))
        #expect(contextLabel.text == "回复 netcup #10")

        let cancelButton = try #require(viewController.view.firstButton(accessibilityLabel: "取消引用"))
        cancelButton.sendActions(for: .touchUpInside)
        #expect(contextLabel.text == nil)

        viewController.handleQuote(comment)
        let replyTextView = try #require(viewController.view.firstTextView(accessibilityIdentifier: "post-detail-reply-text-view"))
        replyTextView.text = "正文"
        let sendButton = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-detail-reply-send-button"))
        sendButton.sendActions(for: .touchUpInside)
        #expect(presenter.sentReplyContent?.contains("> @netcup [#10]") == true)
        #expect(presenter.sentReplyContent?.contains("第一段") == true)
        #expect(presenter.sentReplyContent?.contains("第二段") == false)
    }

    @Test func renderShowsToastMessage() throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)

        viewController.loadViewIfNeeded()
        viewController.showToast(message: "评论已发布，可到最后一页查看")

        let label = try #require(viewController.view.firstLabel(accessibilityIdentifier: "post-detail-toast-label"))
        #expect(label.text == "评论已发布，可到最后一页查看")
        #expect(label.isHidden == false)
    }
}

private final class SpyPostDetailPresenter: PostDetailPresenterProtocol {
    private(set) var loadCount = 0
    private(set) var didTapLoginCount = 0
    private(set) var selectedPages: [Int] = []
    private(set) var sentReplyContent: String?

    func viewDidLoad() {
        loadCount += 1
    }

    func didTapLogin() {
        didTapLoginCount += 1
    }

    func didSelectPage(_ page: Int) {
        selectedPages.append(page)
    }

    func didTapSendReply(content: String) {
        sentReplyContent = content
    }
}

private func deleteVideoAssetTestCookies(from storage: HTTPCookieStorage) {
    for cookie in storage.cookies ?? [] where cookie.name == "video_asset_test_cookie" {
        storage.deleteCookie(cookie)
    }
}

private extension UIView {
    func firstButton(accessibilityLabel: String) -> UIButton? {
        if let button = self as? UIButton, button.accessibilityLabel == accessibilityLabel {
            return button
        }
        for subview in subviews {
            if let matched = subview.firstButton(accessibilityLabel: accessibilityLabel) {
                return matched
            }
        }
        return nil
    }

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

    func firstLabel(accessibilityIdentifier: String) -> UILabel? {
        if let label = self as? UILabel, label.accessibilityIdentifier == accessibilityIdentifier {
            return label
        }

        for subview in subviews {
            if let matched = subview.firstLabel(accessibilityIdentifier: accessibilityIdentifier) {
                return matched
            }
        }

        return nil
    }
}

private extension PageScrubberView {
    func testWidthConstant() -> CGFloat {
        constraints.first { $0.firstAttribute == .width }?.constant ?? 0
    }
}

private extension PostDetailViewController {
    func testRowCount(inSection section: Int) -> Int {
        tableNode(ASTableNode(style: .plain), numberOfRowsInSection: section)
    }

    func testHeaderContent() -> PostDetailHeaderContent? {
        let value = Mirror(reflecting: self).children.first { $0.label == "currentHeaderContent" }?.value
        if let header = value as? PostDetailHeaderContent {
            return header
        }

        guard let value else { return nil }
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return nil }
        return mirror.children.first?.value as? PostDetailHeaderContent
    }

    func testPendingScrollRow() -> Int? {
        Mirror(reflecting: self).children.first { $0.label == "pendingScrollToRow" }?.value as? Int
    }
}
