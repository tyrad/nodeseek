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
            replyForm: nil
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
            replyForm: nil
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
            replyForm: nil,
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
            replyForm: nil,
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
            replyForm: nil,
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
            replyForm: nil,
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
            replyForm: nil,
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
            replyForm: nil,
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
            replyForm: nil,
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
            replyForm: nil,
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
            replyForm: nil,
            page: 2,
            pagination: nil
        ))

        #expect(viewController.testRowCount(inSection: 0) == 3)
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
            replyForm: nil,
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

    @Test func showsBottomCommentComposerAndSubmitsPlainText() throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)

        viewController.loadViewIfNeeded()

        let textView = try #require(viewController.view.firstTextView(accessibilityIdentifier: "post-detail-comment-input"))
        let sendButton = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-detail-comment-send-button"))
        let placeholderLabel = try #require(viewController.view.firstLabel(accessibilityIdentifier: "post-detail-comment-placeholder-label"))
        #expect(textView.text.isEmpty)
        #expect(textView.isScrollEnabled == false)
        #expect(textView.textContainerInset.top == 12)
        #expect(placeholderLabel.text == "写下你的评论...")
        #expect(placeholderLabel.isHidden == false)
        #expect(sendButton.isEnabled == false)
        #expect(sendButton.isHidden)

        textView.text = "bdbd"
        textView.delegate?.textViewDidChange?(textView)
        #expect(placeholderLabel.isHidden)
        viewController.simulateKeyboardVisibleForTesting()
        #expect(sendButton.isHidden == false)
        sendButton.sendActions(for: .touchUpInside)

        #expect(presenter.submittedComments == ["bdbd"])
    }

    @Test func commentComposerDefaultsToSingleLineHeightAndReducedTopPadding() throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)

        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.layoutIfNeeded()

        let textView = try #require(viewController.view.firstTextView(accessibilityIdentifier: "post-detail-comment-input"))
        let expectedHeight = (textView.font?.lineHeight ?? 0)
            + textView.textContainerInset.top
            + textView.textContainerInset.bottom

        #expect(abs(textView.bounds.height - expectedHeight) < 1)
        #expect(textView.textContainerInset.top == 12)
    }

    @Test func commentSendButtonVisibilityTracksKeyboardVisibility() throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)

        viewController.loadViewIfNeeded()
        let sendButton = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-detail-comment-send-button"))

        #expect(sendButton.isHidden)

        viewController.simulateKeyboardVisibleForTesting()
        #expect(sendButton.isHidden == false)

        viewController.simulateKeyboardHiddenForTesting()
        #expect(sendButton.isHidden)
    }

    @Test func commentComposerAddsNonCancellingDismissKeyboardTapGesture() throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)

        viewController.loadViewIfNeeded()

        let tapGesture = try #require(viewController.view.gestureRecognizers?.compactMap { $0 as? UITapGestureRecognizer }.first)
        #expect(tapGesture.cancelsTouchesInView == false)
    }

    @Test func clearCommentComposerResetsTextReplyTargetAndSendButton() throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)
        let comment = Comment(
            id: "1",
            anchorID: "10",
            authorName: "netcup",
            avatarURL: nil,
            floorText: "#10",
            createdAtText: "1min ago",
            createdAtTitleText: nil,
            contentHTML: "<p>第一段</p>"
        )

        viewController.loadViewIfNeeded()
        viewController.handleReply(to: comment)
        let textView = try #require(viewController.view.firstTextView(accessibilityIdentifier: "post-detail-comment-input"))
        let sendButton = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-detail-comment-send-button"))
        let targetLabel = try #require(viewController.view.firstLabel(accessibilityIdentifier: "post-detail-comment-target-label"))

        textView.text = "bdbd"
        textView.delegate?.textViewDidChange?(textView)
        viewController.simulateKeyboardVisibleForTesting()
        #expect(sendButton.isEnabled)
        #expect(targetLabel.isHidden == false)

        viewController.clearCommentComposer()

        #expect(textView.text.isEmpty)
        #expect(sendButton.isEnabled == false)
        #expect(sendButton.isHidden == false)
        #expect(targetLabel.isHidden)
    }

    @Test func commentSubmitLoadingStateShowsSpinnerOnSendButton() throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)

        viewController.loadViewIfNeeded()

        let textView = try #require(viewController.view.firstTextView(accessibilityIdentifier: "post-detail-comment-input"))
        let sendButton = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-detail-comment-send-button"))

        textView.text = "bdbd"
        textView.delegate?.textViewDidChange?(textView)
        viewController.simulateKeyboardVisibleForTesting()
        #expect(sendButton.isEnabled)

        viewController.setCommentComposerSubmitting(true)

        #expect(sendButton.isEnabled == false)
        #expect(sendButton.configuration?.showsActivityIndicator == true)
        #expect(sendButton.configuration?.image == nil)

        viewController.setCommentComposerSubmitting(false)

        #expect(sendButton.isEnabled)
        #expect(sendButton.configuration?.showsActivityIndicator == false)
        #expect(sendButton.configuration?.image != nil)
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
        viewController.handleReply(to: comment)
        let targetLabel = try #require(viewController.view.firstLabel(accessibilityIdentifier: "post-detail-comment-target-label"))
        #expect(targetLabel.text == "回复 @netcup #10")

        let cancelButton = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-detail-comment-target-cancel-button"))
        cancelButton.sendActions(for: .touchUpInside)
        #expect(targetLabel.isHidden)

        viewController.handleQuote(comment)
        let textView = try #require(viewController.view.firstTextView(accessibilityIdentifier: "post-detail-comment-input"))
        #expect(textView.text.contains("> @netcup [#10]"))
        #expect(textView.text.contains("第一段"))
        #expect(textView.text.contains("第二段") == false)
    }

    @Test func quotePrefillExpandsCommentComposerHeight() throws {
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
            contentHTML: "<p>这是一段用于测试输入框高度自适应的引用内容，会被预填到评论输入框里。</p>"
        )

        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.layoutIfNeeded()

        let textView = try #require(viewController.view.firstTextView(accessibilityIdentifier: "post-detail-comment-input"))
        let initialHeight = textView.bounds.height

        viewController.handleQuote(comment)
        viewController.view.layoutIfNeeded()

        #expect(textView.bounds.height > initialHeight)
        #expect(textView.isScrollEnabled == false)
    }

    @Test func longQuotePrefillCapsCommentComposerAtMaximumHeight() throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)
        let longParagraph = Array(repeating: "这是一段很长的引用内容，用于验证输入框最大高度。", count: 40).joined()
        let comment = Comment(
            id: "1",
            anchorID: "10",
            authorName: "netcup",
            avatarURL: nil,
            floorText: "#10",
            createdAtText: "1min ago",
            createdAtTitleText: "2026-04-29 13:58:43",
            contentHTML: "<p>\(longParagraph)</p>"
        )

        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.layoutIfNeeded()

        let textView = try #require(viewController.view.firstTextView(accessibilityIdentifier: "post-detail-comment-input"))
        let expectedMaximumHeight = (textView.font?.lineHeight ?? 0) * 6
            + textView.textContainerInset.top
            + textView.textContainerInset.bottom

        viewController.handleQuote(comment)
        viewController.view.layoutIfNeeded()

        #expect(abs(textView.bounds.height - expectedMaximumHeight) < 1)
        #expect(textView.isScrollEnabled)
    }

    @Test func quotePrefillRestoresScrollingWhenComposerAlreadyAtMaximumHeight() throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)
        let firstParagraph = Array(repeating: "第一段长引用内容，用于撑满输入框高度。", count: 40).joined()
        let secondParagraph = Array(repeating: "第二段长引用内容，再次预填时高度仍然应该封顶并允许滚动。", count: 40).joined()
        let firstComment = Comment(
            id: "1",
            anchorID: "10",
            authorName: "netcup",
            avatarURL: nil,
            floorText: "#10",
            createdAtText: "1min ago",
            createdAtTitleText: "2026-04-29 13:58:43",
            contentHTML: "<p>\(firstParagraph)</p>"
        )
        let secondComment = Comment(
            id: "2",
            anchorID: "11",
            authorName: "coldsword",
            avatarURL: nil,
            floorText: "#11",
            createdAtText: "2min ago",
            createdAtTitleText: "2026-04-29 14:00:00",
            contentHTML: "<p>\(secondParagraph)</p>"
        )

        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.layoutIfNeeded()

        let textView = try #require(viewController.view.firstTextView(accessibilityIdentifier: "post-detail-comment-input"))

        viewController.handleQuote(firstComment)
        viewController.view.layoutIfNeeded()
        #expect(textView.isScrollEnabled)

        textView.isScrollEnabled = false
        viewController.handleQuote(secondComment)
        viewController.view.layoutIfNeeded()

        #expect(textView.isScrollEnabled)
    }

    @Test func pastedLongCommentTextGetsDeferredHeightRecalibration() async throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)

        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.layoutIfNeeded()

        let textView = try #require(viewController.view.firstTextView(accessibilityIdentifier: "post-detail-comment-input"))
        textView.text = Array(repeating: "这是一段模拟粘贴进输入框的长文本，用于覆盖换行布局延迟稳定的情况。", count: 50).joined()
        textView.delegate?.textViewDidChange?(textView)

        textView.isScrollEnabled = false
        try await Task.sleep(nanoseconds: 180_000_000)

        #expect(textView.isScrollEnabled)
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
    private(set) var submittedComments: [String] = []

    func viewDidLoad() {
        loadCount += 1
    }

    func didTapLogin() {
        didTapLoginCount += 1
    }

    func didSelectPage(_ page: Int) {
        selectedPages.append(page)
    }

    func didSubmitComment(content: String) {
        submittedComments.append(content)
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
