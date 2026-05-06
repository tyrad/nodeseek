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
    @Test func startsWithSkeletonRowsEvenWhenInitialHeaderExists() async throws {
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
        await waitForDetailContent(in: viewController, expectedRowCount: 4)

        #expect(viewController.testRowCount(inSection: 0) == 4)
    }

    @Test func showsSkeletonRowsWhileInitialDetailIsLoading() async throws {
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
        await waitForDetailContent(in: viewController, expectedRowCount: 1)

        #expect(viewController.testRowCount(inSection: 0) == 1)
    }

    @Test func initialDetailKeepsSkeletonUntilBodyRenderCompletes() async throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)

        viewController.loadViewIfNeeded()
        viewController.showLoading()
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
        ))

        #expect(viewController.testRowCount(inSection: 0) == 5)

        await waitUntil {
            viewController.testRowCount(inSection: 0) == 3
                && viewController.headerRenderedContent != nil
                && viewController.renderedCommentIDs.contains("1")
        }

        #expect(viewController.testRowCount(inSection: 0) == 3)
    }

    @Test func detailWithPaginationShowsPageScrubberOverlayWithoutPagerRows() async throws {
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
        await waitForDetailContent(in: viewController, expectedRowCount: 4)

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

    @Test func selectingPageThroughDetailScrubberCallsPresenter() async throws {
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
        await waitForDetailContent(in: viewController)

        let scrubber = try #require(viewController.view.firstSubview(of: PageScrubberView.self))
        scrubber.frame = CGRect(x: 0, y: 0, width: 58, height: 220)
        scrubber.beginScrubbingForTesting(at: 110)
        scrubber.updateScrubbingForTesting(to: 215)
        scrubber.endScrubbingForTesting(at: 215)

        #expect(presenter.selectedPages == [2])
    }

    @Test func renderingOtherPageScrollsFirstCommentToTop() async throws {
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
        await waitForDetailContent(in: viewController)

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

    @Test func pageLoadingKeepsHeaderAndShowsCommentSkeletonRows() async throws {
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
        await waitForDetailContent(in: viewController)

        viewController.showPageLoading()

        #expect(viewController.testRowCount(inSection: 0) == 6)
        #expect(viewController.testHeaderContent()?.contentHTML == "<p>原帖正文</p>")
    }

    @Test func renderingOtherPagePreservesExistingHeaderContent() async throws {
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
        await waitForDetailContent(in: viewController)

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

    @Test func refreshingSamePageReusesRenderedContentWhenOnlyMetadataChanges() async throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)
        let detail = PostDetail(
            id: "703863",
            title: "详情标题",
            authorName: "ipv4",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>原帖正文</p>",
            comments: [
                Comment(id: "1", authorName: "a", avatarURL: nil, floorText: "#1", createdAtText: "1min ago", contentHTML: "<p>评论一</p>")
            ],
            page: 1
        )

        viewController.loadViewIfNeeded()
        viewController.render(detail: detail)
        await waitForDetailContent(in: viewController)
        let headerCache = [RenderedContentBlock.unsupported(reason: "cached-header")]
        let commentCache = [RenderedContentBlock.unsupported(reason: "cached-comment")]
        viewController.headerRenderedContent = headerCache
        viewController.commentRenderedCache["1"] = commentCache
        viewController.renderedCommentIDs.insert("1")

        viewController.render(detail: PostDetail(
            id: "703863",
            title: "详情标题",
            authorName: "ipv4",
            avatarURL: nil,
            metadataText: "1 分钟前",
            contentHTML: "<p>原帖正文</p>",
            comments: [
                Comment(id: "1", authorName: "a", avatarURL: nil, floorText: "#1", createdAtText: "2min ago", contentHTML: "<p>评论一</p>")
            ],
            page: 1
        ))

        #expect(viewController.headerRenderedContent?.testUnsupportedReasons() == ["cached-header"])
        #expect(viewController.commentRenderedCache["1"]?.testUnsupportedReasons() == ["cached-comment"])
        #expect(viewController.renderedCommentIDs.contains("1"))
    }

    @Test func updatingPostBodyWithReactionOnlyDoesNotTriggerHeaderReload() async throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)
        let detail = PostDetail(
            id: "703863",
            title: "详情标题",
            authorName: "ipv4",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>原帖正文</p>",
            favoriteCount: 1,
            isFavoriteCollected: false,
            comments: [],
            page: 1
        )

        viewController.loadViewIfNeeded()
        viewController.render(detail: detail)
        await waitForDetailContent(in: viewController, expectedRowCount: 1)

        let headerCache = [RenderedContentBlock.unsupported(reason: "cached-header")]
        viewController.headerRenderedContent = headerCache

        viewController.updatePostBody(detail: PostDetail(
            id: "703863",
            title: "详情标题",
            authorName: "ipv4",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>原帖正文</p>",
            favoriteCount: 2,
            isFavoriteCollected: true,
            comments: [],
            page: 1
        ))

        #expect(viewController.headerRenderedContent?.testUnsupportedReasons() == ["cached-header"])
        #expect(viewController.testHeaderContent()?.favoriteCount == 2)
        #expect(viewController.testHeaderContent()?.isFavoriteCollected == true)
    }

    @Test func renderingOtherPageKeepsPaginationWhenParserMissesPager() async throws {
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
        await waitForDetailContent(in: viewController)

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

    @Test func tappingPostChickenLegRequiresConfirmationBeforeSubmitting() throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)
        let header = PostDetailHeaderContent(
            postID: "710379",
            title: "带操作区的主题",
            authorName: "mist",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>正文</p>",
            chickenLegCount: 1
        )
        var confirmationContext: ChickenLegConfirmationContext?
        var confirmAction: (() -> Void)?
        viewController.chickenLegConfirmationPresenter = { _, context, onConfirm in
            confirmationContext = context
            confirmAction = onConfirm
        }

        viewController.handlePostChickenLegTap(header)

        #expect(confirmationContext == .post)
        #expect(presenter.didTapPostChickenLegCount == 0)

        let action = try #require(confirmAction)
        action()

        #expect(presenter.didTapPostChickenLegCount == 1)
    }

    @Test func tappingCommentChickenLegRequiresConfirmationBeforeSubmitting() throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)
        let comment = Comment(
            id: "9835758",
            authorName: "mist",
            avatarURL: nil,
            floorText: "#1",
            createdAtText: "刚刚",
            contentHTML: "<p>内容</p>",
            chickenLegCount: 1
        )
        var confirmationContext: ChickenLegConfirmationContext?
        var confirmAction: (() -> Void)?
        viewController.chickenLegConfirmationPresenter = { _, context, onConfirm in
            confirmationContext = context
            confirmAction = onConfirm
        }

        viewController.handleCommentChickenLegTap(comment)

        #expect(confirmationContext == .comment)
        #expect(presenter.chickenLeggedCommentIDs.isEmpty)

        let action = try #require(confirmAction)
        action()

        #expect(presenter.chickenLeggedCommentIDs == ["9835758"])
    }

    @Test func addsMoreMenuAndCanTriggerReload() throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)

        viewController.loadViewIfNeeded()

        let items = try #require(viewController.navigationItem.rightBarButtonItems)
        #expect(items.count == 2)
        let moreButton = try #require(items.first { $0.accessibilityLabel == "更多" })
        _ = try #require(moreButton.menu?.children.first { $0.title == "刷新" } as? UIAction)
        _ = try #require(moreButton.menu?.children.first { $0.title == "复制链接" } as? UIAction)
        viewController.refreshTapped()
        #expect(presenter.loadCount == 2)
    }

    @Test func navigationAuthorTitleUsesHeaderAuthorAndFollowsScrollThreshold() async throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)
        viewController.loadViewIfNeeded()

        viewController.render(detail: PostDetail(
            id: "703863",
            title: "详情标题",
            authorName: "ipv4",
            avatarURL: URL(string: "https://www.nodeseek.com/avatar/34378.png"),
            metadataText: "刚刚",
            contentHTML: "<p>正文</p>",
            comments: [],
        ))
        await waitForDetailContent(in: viewController, expectedRowCount: 1)

        #expect(viewController.title == nil)
        #expect(viewController.testNavigationAuthorName() == "ipv4")
        #expect(viewController.testNavigationAuthorTitleIsVisible == false)

        viewController.updateNavigationAuthorVisibility(contentOffsetY: 84)
        #expect(viewController.testNavigationAuthorTitleIsVisible)

        viewController.updateNavigationAuthorVisibility(contentOffsetY: 12)
        #expect(viewController.testNavigationAuthorTitleIsVisible == false)
    }

    @Test func copyCurrentPostLinkCopiesResolvedDetailURL() throws {
        let presenter = SpyPostDetailPresenter()
        let header = PostDetailHeaderContent(
            postID: "703863",
            title: "详情标题",
            authorName: "ipv4",
            avatarURL: nil,
            metadataText: "刚刚"
        )
        let viewController = PostDetailViewController(
            presenter: presenter,
            initialHeader: header,
            currentPage: 2
        )
        viewController.loadViewIfNeeded()
        UIPasteboard.general.string = nil

        viewController.copyCurrentPostLink()

        #expect(UIPasteboard.general.string == "https://www.nodeseek.com/post-703863-2")
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

    @Test func postBodyTitleShowsRequiredReadingLevelWithLockAttachment() throws {
        let header = PostDetailHeaderContent(
            postID: "710379",
            title: "闲置顶级亚太线路 成本价拼车",
            authorName: "mist",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>正文</p>",
            requiredReadingLevel: 1
        )
        let node = PostBodyCellNode(
            content: header,
            renderedContent: [],
            onImageTapped: { _, _ in },
            onTextLayoutInvalidated: {}
        )

        let title = try #require(node.debugTitleAttributedText)

        #expect(title.string.contains("闲置顶级亚太线路 成本价拼车"))
        #expect(title.string.contains("🔒"))
        #expect(title.string.contains("1"))
        #expect(title.foregroundColor(for: "1") == .systemRed)
    }

    @Test func postBodyCellShowsReactionAndFavoriteCountsWhenAvailable() {
        let header = PostDetailHeaderContent(
            postID: "710379",
            title: "带操作区的主题",
            authorName: "mist",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>正文</p>",
            likeCount: 0,
            chickenLegCount: 1,
            opposeCount: 0,
            favoriteCount: 2,
            isFavoriteCollected: true
        )
        var likeTapCount = 0
        var chickenLegTapCount = 0
        var opposeTapCount = 0
        var favoriteTapCount = 0
        var replyTapCount = 0
        var commentTapCount = 0
        let node = PostBodyCellNode(
            content: header,
            renderedContent: [],
            onImageTapped: { _, _ in },
            onLikeTapped: {
                likeTapCount += 1
            },
            onChickenLegTapped: {
                chickenLegTapCount += 1
            },
            onOpposeTapped: {
                opposeTapCount += 1
            },
            onFavoriteTapped: {
                favoriteTapCount += 1
            },
            onReplyTapped: {
                replyTapCount += 1
            },
            onCommentTapped: {
                commentTapCount += 1
            },
            onTextLayoutInvalidated: {}
        )
        _ = node.layoutThatFits(ASSizeRange(
            min: .zero,
            max: CGSize(width: 360, height: CGFloat.greatestFiniteMagnitude)
        ))
        node.debugTapLikeAction()
        node.debugTapChickenLegAction()
        node.debugTapOpposeAction()
        node.debugTapFavoriteAction()
        node.debugTapReplyAction()
        node.debugTapCommentAction()

        #expect(node.debugReactionActionTitles == [nil, "1", nil, "2"])
        #expect(node.debugFooterActionAccessibilityLabels == ["点赞", "加鸡腿 1", "反对", "收藏 2", "回复楼主", "评论帖子"])
        #expect(node.debugFavoriteActionColor == .systemYellow)
        #expect(likeTapCount == 1)
        #expect(chickenLegTapCount == 1)
        #expect(opposeTapCount == 1)
        #expect(favoriteTapCount == 1)
        #expect(replyTapCount == 1)
        #expect(commentTapCount == 1)
    }

    @Test func postBodyCellUpdatesLikeReactionInPlace() {
        let header = PostDetailHeaderContent(
            postID: "710379",
            title: "带操作区的主题",
            authorName: "mist",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>正文</p>",
            likeCount: 0
        )
        let node = PostBodyCellNode(
            content: header,
            renderedContent: [],
            onImageTapped: { _, _ in },
            onTextLayoutInvalidated: {}
        )

        node.updateLikeReaction(count: 1, isClicked: true)

        #expect(node.debugReactionActionTitles.first == "1")
        #expect(node.debugFooterActionAccessibilityLabels.first == "点赞 1")
        #expect(node.debugLikeActionColor == .systemRed)
    }

    @Test func postBodyCellUpdatesChickenLegReactionInPlace() {
        let header = PostDetailHeaderContent(
            postID: "710379",
            title: "带操作区的主题",
            authorName: "mist",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>正文</p>",
            chickenLegCount: 1
        )
        let node = PostBodyCellNode(
            content: header,
            renderedContent: [],
            onImageTapped: { _, _ in },
            onTextLayoutInvalidated: {}
        )

        node.updateChickenLegReaction(count: 2, isClicked: true)

        #expect(node.debugReactionActionTitles[1] == "2")
        #expect(node.debugFooterActionAccessibilityLabels[1] == "加鸡腿 2")
        #expect(node.debugChickenLegActionColor == .systemOrange)
    }

    @Test func postBodyCellUpdatesOpposeReactionInPlace() {
        let header = PostDetailHeaderContent(
            postID: "710379",
            title: "带操作区的主题",
            authorName: "mist",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>正文</p>",
            opposeCount: 0
        )
        let node = PostBodyCellNode(
            content: header,
            renderedContent: [],
            onImageTapped: { _, _ in },
            onTextLayoutInvalidated: {}
        )

        node.updateOpposeReaction(count: 1, isClicked: true)

        #expect(node.debugReactionActionTitles[2] == "1")
        #expect(node.debugFooterActionAccessibilityLabels[2] == "反对 1")
        #expect(node.debugOpposeActionColor == .systemRed)
    }

    @Test func postBodyCellCompactsLargeReactionCounts() {
        let header = PostDetailHeaderContent(
            postID: "710379",
            title: "带操作区的主题",
            authorName: "mist",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>正文</p>",
            likeCount: 12_345,
            chickenLegCount: 123_456,
            opposeCount: 100_000_000,
            favoriteCount: 2_000_000_000
        )
        let node = PostBodyCellNode(
            content: header,
            renderedContent: [],
            onImageTapped: { _, _ in },
            onTextLayoutInvalidated: {}
        )

        #expect(node.debugReactionActionTitles == ["1.2万", "12.3万", "1亿", "20亿"])
        #expect(node.debugFooterActionAccessibilityLabels == ["点赞 12345", "加鸡腿 123456", "反对 100000000", "收藏 2000000000", "回复楼主", "评论帖子"])
    }

    @Test func postBodyCellKeepsFavoriteIconStyleWhileSubmitting() {
        let header = PostDetailHeaderContent(
            postID: "710379",
            title: "带操作区的主题",
            authorName: "mist",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>正文</p>",
            favoriteCount: 2,
            isFavoriteCollected: true,
            isFavoriteSubmitting: true
        )
        let node = PostBodyCellNode(
            content: header,
            renderedContent: [],
            onImageTapped: { _, _ in },
            onTextLayoutInvalidated: {}
        )

        #expect(node.debugFavoriteActionColor == .systemYellow)
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

    @Test func commentCellShowsPosterBadgeBesideAuthorName() {
        let comment = Comment(
            id: "1",
            authorName: "大油桃",
            isPoster: true,
            avatarURL: nil,
            floorText: "#1",
            createdAtText: "刚刚",
            contentHTML: "<p>楼主回复</p>"
        )
        let node = CommentCellNode(
            comment: comment,
            renderedBody: [],
            onImageTapped: { _, _ in },
            onTextLayoutInvalidated: {}
        )

        #expect(node.debugPosterBadgeAttributedText?.string == "楼主")
    }

    @Test func commentCellShowsHotIconBeforeFloorNumber() {
        let comment = Comment(
            id: "326",
            authorName: "hostlocmjj",
            avatarURL: nil,
            floorText: "#326",
            createdAtText: "刚刚",
            contentHTML: "<p>热门评论</p>",
            isHot: true
        )
        let node = CommentCellNode(
            comment: comment,
            renderedBody: [],
            onImageTapped: { _, _ in },
            onTextLayoutInvalidated: {}
        )

        #expect(node.debugHotBadgeImage != nil)
    }

    @Test func commentCellDisplaysTimeOnSecondLineBelowCommentLabels() {
        let comment = Comment(
            id: "326",
            authorName: "hostlocmjj",
            isPoster: true,
            avatarURL: nil,
            authorBadgeTexts: ["已停用"],
            floorText: "#326",
            createdAtText: "34min ago",
            contentHTML: "<p>评论</p>",
            isHot: true
        )
        let node = CommentCellNode(
            comment: comment,
            renderedBody: [],
            onImageTapped: { _, _ in },
            onTextLayoutInvalidated: {}
        )

        _ = node.layoutThatFits(ASSizeRange(
            min: .zero,
            max: CGSize(width: 360, height: CGFloat.greatestFiniteMagnitude)
        ))

        #expect(node.debugHeaderTopLineText == "hostlocmjj 楼主 已停用 #326")
        #expect(node.debugHeaderTimeLineText == "34min ago")
        #expect(node.debugHeaderTimeIsOnSecondLine)
    }

    @Test func commentCellShowsDynamicAuthorBadgeText() {
        let comment = Comment(
            id: "326",
            authorName: "hostlocmjj",
            avatarURL: nil,
            authorBadgeTexts: ["已停用"],
            floorText: "#326",
            createdAtText: "刚刚",
            contentHTML: "<p>评论</p>"
        )
        let node = CommentCellNode(
            comment: comment,
            renderedBody: [],
            onImageTapped: { _, _ in },
            onTextLayoutInvalidated: {}
        )

        #expect(node.debugAuthorBadgeTexts == ["已停用"])
        #expect(node.debugAuthorBadgeBorderWidths == [1])
        #expect(node.debugAuthorBadgeTitleColors == [.label])
    }

    @Test func commentCellUsesIconOnlyFooterActions() {
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
        _ = node.layoutThatFits(ASSizeRange(
            min: .zero,
            max: CGSize(width: 360, height: CGFloat.greatestFiniteMagnitude)
        ))

        #expect(node.debugReplyActionTitle == nil)
        #expect(node.debugQuoteActionTitle == nil)
        #expect(node.debugReplyActionImage != nil)
        #expect(node.debugQuoteActionImage != nil)
        #expect(node.debugFooterActionAccessibilityLabels == ["点赞", "加鸡腿", "反对", "回复评论", "引用评论"])
        #expect(node.debugActionsAreDisplayedBelowBody)
    }

    @Test func commentCellShowsReactionCountsWhenAvailable() {
        let comment = Comment(
            id: "1",
            authorName: "ipv4",
            avatarURL: nil,
            floorText: "#1",
            createdAtText: "刚刚",
            contentHTML: "<p>评论</p>",
            likeCount: 0,
            chickenLegCount: 1,
            opposeCount: 0
        )
        let node = CommentCellNode(
            comment: comment,
            renderedBody: [],
            onImageTapped: { _, _ in },
            onTextLayoutInvalidated: {}
        )
        _ = node.layoutThatFits(ASSizeRange(
            min: .zero,
            max: CGSize(width: 360, height: CGFloat.greatestFiniteMagnitude)
        ))

        #expect(node.debugReactionActionTitles == [nil, "1", nil])
        #expect(node.debugFooterActionAccessibilityLabels.prefix(3) == ["点赞", "加鸡腿 1", "反对"])
    }

    @Test func commentCellUpdatesLikeReactionInPlace() {
        let comment = Comment(
            id: "1",
            authorName: "ipv4",
            avatarURL: nil,
            floorText: "#1",
            createdAtText: "刚刚",
            contentHTML: "<p>评论</p>",
            likeCount: 0
        )
        let node = CommentCellNode(
            comment: comment,
            renderedBody: [],
            onImageTapped: { _, _ in },
            onTextLayoutInvalidated: {}
        )

        node.updateLikeReaction(count: 1, isClicked: true)

        #expect(node.debugReactionActionTitles.first == "1")
        #expect(node.debugFooterActionAccessibilityLabels.first == "点赞 1")
        #expect(node.debugLikeActionColor == .systemRed)
    }

    @Test func commentCellUpdatesChickenLegReactionInPlace() {
        let comment = Comment(
            id: "1",
            authorName: "ipv4",
            avatarURL: nil,
            floorText: "#1",
            createdAtText: "刚刚",
            contentHTML: "<p>评论</p>",
            chickenLegCount: 1
        )
        let node = CommentCellNode(
            comment: comment,
            renderedBody: [],
            onImageTapped: { _, _ in },
            onTextLayoutInvalidated: {}
        )

        node.updateChickenLegReaction(count: 2, isClicked: true)

        #expect(node.debugReactionActionTitles[1] == "2")
        #expect(node.debugFooterActionAccessibilityLabels[1] == "加鸡腿 2")
        #expect(node.debugChickenLegActionColor == .systemOrange)
    }

    @Test func commentCellUpdatesOpposeReactionInPlace() {
        let comment = Comment(
            id: "1",
            authorName: "ipv4",
            avatarURL: nil,
            floorText: "#1",
            createdAtText: "刚刚",
            contentHTML: "<p>评论</p>",
            opposeCount: 0
        )
        let node = CommentCellNode(
            comment: comment,
            renderedBody: [],
            onImageTapped: { _, _ in },
            onTextLayoutInvalidated: {}
        )

        node.updateOpposeReaction(count: 1, isClicked: true)

        #expect(node.debugReactionActionTitles[2] == "1")
        #expect(node.debugFooterActionAccessibilityLabels[2] == "反对 1")
        #expect(node.debugOpposeActionColor == .systemRed)
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

    @Test func tableLayoutExpandsNarrowColumnsToFillViewportWidth() {
        let table = RenderedTableBlock(rows: [
            .init(cells: [
                .init(text: "功能", isHeader: true),
                .init(text: "说明", isHeader: true)
            ], isHeader: true),
            .init(cells: [
                .init(text: "验证", isHeader: false),
                .init(text: "本地题库", isHeader: false)
            ], isHeader: false)
        ])

        let naturalWidth = DetailTableLayout.columnWidths(for: table).reduce(0, +)
        let expandedWidth = DetailTableLayout.columnWidths(for: table, fittingWidth: 360).reduce(0, +)

        #expect(naturalWidth < 360)
        #expect(abs(expandedWidth - 360) < 0.5)
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
                .init(text: "第一行", isHeader: false)
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

    @Test func tableNodeWrapsLongChineseCellTextWithoutTailTruncation() {
        let table = RenderedTableBlock(rows: [
            .init(cells: [
                .init(text: "核心功能", isHeader: true),
                .init(text: "说明", isHeader: true)
            ], isHeader: true),
            .init(cells: [
                .init(text: "⚡ 0 延迟验证", isHeader: false),
                .init(
                    text: "采用本地精选常识题库。秒开秒验，彻底告别网络超时与接口报错，验证成功率 100%。",
                    isHeader: false
                )
            ], isHeader: false)
        ])
        let node = DetailTableNode(table: table, onImageTapped: { _, _ in })
        _ = node.layoutThatFits(ASSizeRange(
            min: .zero,
            max: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
        ))
        node.view.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
        node.view.setNeedsLayout()
        node.view.layoutIfNeeded()

        let cellLabels = node.view.allSubviews(of: UILabel.self)
        let longTextLabel = cellLabels.first { $0.text?.contains("秒开秒验") == true }

        #expect(longTextLabel?.numberOfLines == 0)
        #expect(longTextLabel?.lineBreakMode == .byCharWrapping)
        #expect(DetailTableLayout.rowHeights(
            for: table,
            columnWidths: DetailTableLayout.columnWidths(for: table)
        )[1] > 70)
    }

    @Test func tableNodeRoutesCellLinkTap() throws {
        let linkURL = try #require(URL(string: "https://www.nodeseek.com/go/aff"))
        let table = RenderedTableBlock(rows: [
            .init(cells: [
                .init(
                    text: "购买链接 > #AFF",
                    links: [
                        .init(location: 7, length: 4, url: linkURL)
                    ],
                    isHeader: false
                )
            ], isHeader: false)
        ])
        var tappedURL: URL?
        let node = DetailTableNode(
            table: table,
            onImageTapped: { _, _ in },
            onLinkTapped: { url in
                tappedURL = url
            }
        )
        _ = node.view

        node.debugTapFirstLink()

        #expect(tappedURL == linkURL)
    }

    @Test func tableNodeUsesUnifiedLinkColor() throws {
        let linkURL = try #require(URL(string: "https://www.nodeseek.com/go/aff"))
        let table = RenderedTableBlock(rows: [
            .init(cells: [
                .init(
                    text: "购买链接 > #AFF",
                    links: [
                        .init(location: 7, length: 4, url: linkURL)
                    ],
                    isHeader: false
                )
            ], isHeader: false)
        ])
        let node = DetailTableNode(table: table, onImageTapped: { _, _ in })
        _ = node.layoutThatFits(ASSizeRange(
            min: .zero,
            max: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
        ))
        node.view.frame = CGRect(x: 0, y: 0, width: 320, height: 120)
        node.view.setNeedsLayout()
        node.view.layoutIfNeeded()

        let label = try #require(node.view.allSubviews(of: UILabel.self).first {
            $0.attributedText?.string.contains("#AFF") == true
        })
        let color = try #require(label.attributedText?.foregroundColor(for: "#AFF"))

        #expect(color.isClose(to: NodeSeekLinkStyle.color))
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

    @Test func codeBlockHeightUsesFontLineHeightWithoutPerLineInflation() {
        let lineCount = 80
        let codeBlock = RenderedCodeBlock(
            text: Array(repeating: "line", count: lineCount).joined(separator: "\n")
        )
        let layout = DetailCodeBlockLayout.measure(
            codeBlock: codeBlock,
            constrainedSize: CGSize(width: 220, height: CGFloat.greatestFiniteMagnitude)
        )

        let expectedHeight = ceil(max(
            64,
            DetailCodeBlockLayout.chromeHeight
                + CGFloat(lineCount) * DetailCodeBlockLayout.codeFont.lineHeight
                + DetailCodeBlockLayout.bottomInset
        ))
        #expect(layout.height == expectedHeight)
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

    @Test func richTextNodeMeasureUsesLargerHeightForAttachmentContent() {
        let resolved = DetailRichTextNode.resolvedMeasuredHeight(
            dtCoreTextHeight: 80,
            boundingHeight: 82,
            usesBoundingHeightFallback: true
        )
        #expect(resolved == 82)

        let plainResolved = DetailRichTextNode.resolvedMeasuredHeight(
            dtCoreTextHeight: 80,
            boundingHeight: 82,
            usesBoundingHeightFallback: false
        )
        #expect(plainResolved == 80)
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

    @Test func resolvesNodeSeekPostLinksWithoutPageToNativeDetailPageOne() throws {
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let url = try #require(URL(string: "/post-704174", relativeTo: baseURL)?.absoluteURL)

        let destination = try #require(PostDetailLinkResolver.destination(for: url, baseURL: baseURL))

        guard case .nativePost(let postID, let page, let resolvedURL) = destination else {
            Issue.record("Expected native post destination")
            return
        }
        #expect(postID == "704174")
        #expect(page == 1)
        #expect(resolvedURL.absoluteString == "https://www.nodeseek.com/post-704174")
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

    @Test func currentPageAnchorOneTargetsFirstCommentInsteadOfHeader() async throws {
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
        await waitForDetailContent(in: viewController)

        #expect(viewController.testCurrentPageAnchorRow(for: "0") == 0)
        #expect(viewController.testCurrentPageAnchorRow(for: "1") == 2)
    }

    @Test func consumesInitialAnchorAfterFirstDetailRender() async throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter, initialAnchorID: "2")
        viewController.loadViewIfNeeded()

        viewController.render(detail: PostDetail(
            id: "703863",
            title: "详情标题",
            authorName: "ipv4",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>正文</p>",
            comments: [
                Comment(
                    id: "1",
                    authorName: "a",
                    avatarURL: nil,
                    floorText: "#1",
                    createdAtText: "1min ago",
                    contentHTML: "<p>一楼</p>"
                ),
                Comment(
                    id: "2",
                    authorName: "b",
                    avatarURL: nil,
                    floorText: "#2",
                    createdAtText: "2min ago",
                    contentHTML: "<p>二楼</p>"
                )
            ],
            page: 1,
            pagination: nil
        ))
        await waitForDetailContent(in: viewController)

        #expect(viewController.testPendingInitialAnchorID == nil)
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

    @Test func resolvesNodeSeekSpaceLinksToUserProfile() throws {
        let baseURL = try #require(URL(string: "https://www.nodeseek.com/post-704174-1"))
        let url = try #require(URL(string: "/space/1541", relativeTo: baseURL)?.absoluteURL)

        let destination = try #require(PostDetailLinkResolver.destination(for: url, baseURL: baseURL))

        guard case .userProfile(let resolvedURL) = destination else {
            Issue.record("Expected user profile destination")
            return
        }
        #expect(resolvedURL.absoluteString == "https://www.nodeseek.com/space/1541")
    }

    @Test func resolvesRelativeNodeSeekSpaceLinksToUserProfile() throws {
        let baseURL = try #require(URL(string: "https://www.nodeseek.com/post-704174-1"))
        let url = try #require(URL(string: "space/1541", relativeTo: baseURL))

        let destination = try #require(PostDetailLinkResolver.destination(for: url, baseURL: baseURL))

        guard case .userProfile(let resolvedURL) = destination else {
            Issue.record("Expected user profile destination")
            return
        }
        #expect(resolvedURL.absoluteString == "https://www.nodeseek.com/space/1541")
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

    @Test func resolvesNodeSeekJumpLinksToDecodedSafariTarget() throws {
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let url = try #require(URL(string: "/jump?to=https%3A%2F%2Fshop.023168.xyz%2F", relativeTo: baseURL)?.absoluteURL)

        let destination = try #require(PostDetailLinkResolver.destination(for: url, baseURL: baseURL))

        guard case .safari(let resolvedURL) = destination else {
            Issue.record("Expected NodeSeek jump link to open in Safari")
            return
        }
        #expect(resolvedURL.absoluteString == "https://shop.023168.xyz/")
    }

    @Test func resolvesNodeSeekJumpLinksToDecodedSafariTargetEvenWhenTargetIsNodeSeek() throws {
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let url = try #require(URL(string: "/jump?to=https%3A%2F%2Fwww.nodeseek.com%2Fpost-704174-1", relativeTo: baseURL)?.absoluteURL)

        let destination = try #require(PostDetailLinkResolver.destination(for: url, baseURL: baseURL))

        guard case .safari(let resolvedURL) = destination else {
            Issue.record("Expected NodeSeek jump link to open in Safari")
            return
        }
        #expect(resolvedURL.absoluteString == "https://www.nodeseek.com/post-704174-1")
    }

    @Test func richTextNodeUpdatesMeasuredHeightAfterNormalImageLoads() throws {
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
        let displaySize = DetailImageLayout.presentation(
            for: CGSize(width: 1200, height: 800),
            maxWidth: 320,
            kind: .normal
        ).size
        let didUpdate = node.updateAttachmentLayout(
            matching: imageURL,
            originalSize: CGSize(width: 1200, height: 800),
            displaySize: displaySize
        )
        let updatedHeight = node.layoutThatFits(constrainedSize).size.height

        #expect(didUpdate)
        #expect(updatedHeight > initialHeight)
    }

    @Test func richTextNodeUsesCachedAttachmentSizeBeforeImageReloads() throws {
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
        let constrainedSize = ASSizeRange(
            min: .zero,
            max: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
        )
        let uncachedNode = DetailRichTextNode(
            attributedText: attributedText,
            onImageTapped: { _, _ in },
            onLayoutInvalidated: {}
        )
        let cachedNode = DetailRichTextNode(
            attributedText: attributedText,
            imageSizeProvider: { url in
                url == imageURL ? CGSize(width: 1200, height: 800) : nil
            },
            onImageTapped: { _, _ in },
            onLayoutInvalidated: {}
        )

        let uncachedHeight = uncachedNode.layoutThatFits(constrainedSize).size.height
        let cachedHeight = cachedNode.layoutThatFits(constrainedSize).size.height

        #expect(cachedHeight > uncachedHeight)
    }

    @Test func rendererSplitsWideBlockImageBeforeFollowingText() throws {
        let imageURL = try #require(URL(string: "https://i.111666.best/image/wide.webp"))
        let blocks = DTCoreTextHTMLContentRenderer().render(
            fragment: """
            <p><img src="\(imageURL.absoluteString)" alt="image"><br>
            6，设置二步验证登录（可选）<br>
            7，原始邮箱改密及验证，关于 outlook 等不作赘述。</p>
            <p>本次刚好来自国际知名的瑞士匿名邮箱 protonmail。</p>
            """,
            baseURL: URL(string: "https://www.nodeseek.com")!,
            maxImageWidth: 320
        )
        guard case .image(let imageBlock) = blocks.first else {
            Issue.record("Expected leading block image to be rendered outside rich text")
            return
        }
        let textBlocks = blocks.dropFirst().compactMap { block -> NSAttributedString? in
            guard case .text(let text) = block else { return nil }
            return text
        }
        let attributedText = try #require(textBlocks.first)
        let combinedText = textBlocks.map(\.string).joined(separator: "\n")

        let imageLayout = DetailImageBlockLayout.measure(
            originalSize: CGSize(width: 1200, height: 180),
            constrainedSize: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
        )

        #expect(imageBlock.url == imageURL)
        #expect(imageLayout == CGSize(width: 320, height: 48))
        #expect(attributedText.string.contains("设置二步验证登录"))
        #expect(combinedText.contains("protonmail"))
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
        guard case .image(let imageBlock) = blocks.first else {
            Issue.record("Expected leading block image to be rendered outside rich text")
            return
        }
        let attributedText = try #require(blocks.dropFirst().compactMap { block -> NSAttributedString? in
            guard case .text(let text) = block else { return nil }
            return text
        }.first)
        #expect(attributedText.string.contains("上个月啥都没干"))
        #expect(imageBlock.url == imageURL)

        let node = DetailRichTextNode(
            attributedText: attributedText,
            onImageTapped: { _, _ in },
            onLayoutInvalidated: {}
        )
        let layout = node.layoutThatFits(ASSizeRange(
            min: .zero,
            max: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
        ))
        let layouter = try #require(DTCoreTextLayouter(attributedString: attributedText))
        let layoutFrame = try #require(layouter.layoutFrame(
            with: CGRect(x: 0, y: 0, width: 320, height: 16_777_215),
            range: NSRange(location: 0, length: 0)
        ))
        let expectedHeight = ceil(layoutFrame.frame.maxY)

        #expect(layout.size.height == expectedHeight)
    }

    @Test func richTextNodeMeasuresTrailingStickerLine() throws {
        let blocks = DTCoreTextHTMLContentRenderer().render(
            fragment: """
            <p>活动啥时候开始 <img class="sticker" src="/static/image/sticker/xhj/001.png" loading="lazy" alt="xhj001"></p>
            """,
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
        let layout = node.layoutThatFits(ASSizeRange(
            min: .zero,
            max: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
        ))
        let boundingHeight = ceil(attributedText.boundingRect(
            with: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).height)
        let layouter = try #require(DTCoreTextLayouter(attributedString: attributedText))
        let layoutFrame = try #require(layouter.layoutFrame(
            with: CGRect(x: 0, y: 0, width: 320, height: 16_777_215),
            range: NSRange(location: 0, length: 0)
        ))
        let expectedHeight = ceil(layoutFrame.frame.maxY)

        #expect(boundingHeight > expectedHeight)
        #expect(layout.size.height == expectedHeight)
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

    @Test func imageBlockUpdatesToRealAspectRatioHeightForNormalImages() {
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
        #expect(loadedLayout.width == 320)
        #expect(abs(loadedLayout.height - 214) < 0.01)
    }

    @Test func imageBlockUsesFullWidthPlaceholderForReportImages() {
        let layout = DetailImageBlockLayout.measure(
            originalSize: .zero,
            constrainedSize: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude),
            kind: .report
        )

        #expect(layout.width == 320)
        #expect(layout.height > 320)
    }

    @Test func imageBlockNodeUsesCachedImageSizeForInitialMeasurement() throws {
        let imageURL = try #require(URL(string: "https://i.111666.best/image/network.webp"))
        let node = DetailImageBlockNode(
            imageBlock: RenderedImageBlock(url: imageURL, altText: nil),
            imageURLs: [imageURL],
            imageIndex: 0,
            initialImageSize: CGSize(width: 1200, height: 800),
            onImageTapped: { _, _ in },
            onLayoutInvalidated: {}
        )

        let layout = node.layoutThatFits(ASSizeRange(
            min: .zero,
            max: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
        ))

        #expect(layout.size.width == 320)
        #expect(abs(layout.size.height - 214) < 0.01)
    }

    @Test func imageBlockNodeRequestsRowReloadWhenLoadedImageIsShorterThanPlaceholder() throws {
        let imageURL = try #require(URL(string: "https://i.111666.best/image/wide.webp"))
        var didRequestRowReload = false
        var didRequestGeneralRelayout = false
        let node = DetailImageBlockNode(
            imageBlock: RenderedImageBlock(url: imageURL, altText: nil),
            imageURLs: [imageURL],
            imageIndex: 0,
            onImageTapped: { _, _ in },
            onImageHeightReduced: {
                didRequestRowReload = true
            },
            onLayoutInvalidated: {
                didRequestGeneralRelayout = true
            }
        )

        _ = node.layoutThatFits(ASSizeRange(
            min: .zero,
            max: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
        ))
        node.updateLoadedImageSize(CGSize(width: 1200, height: 180))

        #expect(didRequestRowReload)
        #expect(didRequestGeneralRelayout == false)
    }

    @Test func imageBlockNodeCanSwitchToReportLayoutAfterSVGContentIsResolved() throws {
        let imageURL = try #require(URL(string: "https://example.com/report.svg"))
        var didRequestGeneralRelayout = false
        let node = DetailImageBlockNode(
            imageBlock: RenderedImageBlock(url: imageURL, altText: nil),
            imageURLs: [imageURL],
            imageIndex: 0,
            onImageTapped: { _, _ in },
            onLayoutInvalidated: {
                didRequestGeneralRelayout = true
            }
        )

        _ = node.layoutThatFits(ASSizeRange(
            min: .zero,
            max: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
        ))
        node.updateLoadedImageSize(CGSize(width: 300, height: 1000), resolvedKind: .report)

        #expect(didRequestGeneralRelayout)
    }

    @Test func contentBlockFactoryPassesReducedImageHeightCallbackToImageNodes() throws {
        let imageURL = try #require(URL(string: "https://i.111666.best/image/wide.webp"))
        var didRequestRowReload = false
        let nodes = DetailContentBlockNodeFactory.makeNodes(
            from: [.image(RenderedImageBlock(url: imageURL, altText: nil))],
            onImageTapped: { _, _ in },
            onLinkTapped: { _ in },
            onTextLayoutInvalidated: {},
            onImageHeightReduced: {
                didRequestRowReload = true
            }
        )
        let imageNode = try #require(nodes.first as? DetailImageBlockNode)

        _ = imageNode.layoutThatFits(ASSizeRange(
            min: .zero,
            max: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
        ))
        imageNode.updateLoadedImageSize(CGSize(width: 1200, height: 180))

        #expect(didRequestRowReload)
    }

    @Test func imageBlockUsesRealAspectRatioHeightForVeryWideImages() {
        let layout = DetailImageBlockLayout.measure(
            originalSize: CGSize(width: 1200, height: 180),
            constrainedSize: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
        )
        let imageFrame = DetailImageBlockLayout.imageFrame(
            originalSize: CGSize(width: 1200, height: 180),
            bounds: CGRect(x: 0, y: 0, width: 320, height: layout.height)
        )

        #expect(layout == CGSize(width: 320, height: 48))
        #expect(imageFrame == CGRect(x: 0, y: 0, width: 320, height: 48))
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
            boundingHeight: 300,
            usesBoundingHeightFallback: false
        )

        #expect(height == 120)
    }

    @Test func richTextNodeUsesDefaultWidthForUnboundedMeasurement() {
        let width = DetailRichTextNode.resolvedMeasureWidth(.infinity)

        #expect(width == 320)
    }
}

@MainActor
@Suite(.serialized)
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

    @Test func detailUsesOnlyFloatingReplyEntry() async throws {
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
        await waitForDetailContent(in: viewController, expectedRowCount: 1)

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

    @Test func replyAndQuoteActionsUpdateComposerState() async throws {
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
        await waitForDetailContent(in: viewController, expectedRowCount: 1)
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

    @Test func postHeaderReplyActionUsesPosterContext() async throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)
        let detail = PostDetail(
            id: "714386",
            title: "详情标题",
            authorName: "楼主",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>正文</p>",
            comments: []
        )

        viewController.loadViewIfNeeded()
        viewController.render(detail: detail)
        await waitForDetailContent(in: viewController, expectedRowCount: 1)
        viewController.handleReply(toPostHeader: PostDetailHeaderContent(detail: detail))

        let contextLabel = try #require(viewController.view.firstLabel(accessibilityIdentifier: "post-detail-reply-context-label"))
        #expect(contextLabel.text == "回复 楼主 #0")

        let replyTextView = try #require(viewController.view.firstTextView(accessibilityIdentifier: "post-detail-reply-text-view"))
        replyTextView.text = "收到"
        let sendButton = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-detail-reply-send-button"))
        sendButton.sendActions(for: .touchUpInside)
        #expect(presenter.sentReplyContent?.contains("@楼主 [#0]") == true)
        #expect(presenter.sentReplyContent?.contains("#0") == true)
        #expect(presenter.sentReplyContent?.contains("收到") == true)
    }

    @Test func inlineReplyEditorPlacesStickerButtonBelowSendButton() throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.showsReplyEntry = true
        viewController.displayMode = .content

        viewController.presentReplyEditor(mode: .plain)
        viewController.view.layoutIfNeeded()

        let sendButton = try #require(
            viewController.view.firstButton(accessibilityIdentifier: "post-detail-reply-send-button")
        )
        let stickerButton = try #require(
            viewController.view.firstButton(accessibilityIdentifier: "post-detail-reply-sticker-button")
        )
        #expect(stickerButton.frame.minY > sendButton.frame.maxY)
    }

    @Test func insertingStickerTokenUpdatesReplyTextAtSelection() throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)
        viewController.loadViewIfNeeded()
        viewController.replyTextView.text = "hello world"
        viewController.replyTextView.selectedRange = NSRange(location: 6, length: 5)

        viewController.insertStickerToken("xhj022")

        #expect(viewController.replyTextView.text == "hello :xhj022:")
        #expect(viewController.replyTextView.selectedRange.location == 14)
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
    private(set) var didTapFavoriteCount = 0
    private(set) var didTapPostLikeCount = 0
    private(set) var didTapPostChickenLegCount = 0
    private(set) var didTapPostOpposeCount = 0
    private(set) var likedCommentIDs: [String] = []
    private(set) var chickenLeggedCommentIDs: [String] = []
    private(set) var opposedCommentIDs: [String] = []

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

    func didTapFavorite() {
        didTapFavoriteCount += 1
    }

    func didTapPostLike() {
        didTapPostLikeCount += 1
    }

    func didTapPostChickenLeg() {
        didTapPostChickenLegCount += 1
    }

    func didTapPostOppose() {
        didTapPostOpposeCount += 1
    }

    func didTapCommentLike(_ comment: nodeseek.Comment) {
        likedCommentIDs.append(comment.id)
    }

    func didTapCommentChickenLeg(_ comment: nodeseek.Comment) {
        chickenLeggedCommentIDs.append(comment.id)
    }

    func didTapCommentOppose(_ comment: nodeseek.Comment) {
        opposedCommentIDs.append(comment.id)
    }
}

private func deleteVideoAssetTestCookies(from storage: HTTPCookieStorage) {
    for cookie in storage.cookies ?? [] where cookie.name == "video_asset_test_cookie" {
        storage.deleteCookie(cookie)
    }
}

private extension NSAttributedString {
    var containsAttachment: Bool {
        var found = false
        enumerateAttribute(.attachment, in: NSRange(location: 0, length: length)) { value, _, stop in
            if value is NSTextAttachment {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    func foregroundColor(for substring: String) -> UIColor? {
        let range = (string as NSString).range(of: substring)
        guard range.location != NSNotFound else { return nil }
        return attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? UIColor
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

        let tolerance: CGFloat = 0.001
        return abs(red - otherRed) < tolerance
            && abs(green - otherGreen) < tolerance
            && abs(blue - otherBlue) < tolerance
            && abs(alpha - otherAlpha) < tolerance
    }
}

private extension Array where Element == RenderedContentBlock {
    func testUnsupportedReasons() -> [String] {
        compactMap { block in
            if case .unsupported(let reason) = block {
                return reason
            }
            return nil
        }
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

    func allSubviews<T: UIView>(of type: T.Type) -> [T] {
        var result: [T] = []
        if let matched = self as? T {
            result.append(matched)
        }

        for subview in subviews {
            result.append(contentsOf: subview.allSubviews(of: type))
        }

        return result
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

    var testNavigationAuthorTitleIsVisible: Bool {
        guard let titleView = navigationItem.titleView else { return false }
        return titleView.isHidden == false && titleView.alpha > 0.5
    }

    func testNavigationAuthorName() -> String? {
        navigationItem.titleView?.firstSubview(of: UILabel.self)?.text
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

@MainActor
private func waitForDetailContent(
    in viewController: PostDetailViewController,
    expectedRowCount: Int? = nil
) async {
    let didReveal = await waitUntil(timeout: 2) {
        guard viewController.hasRenderedDetailContent else { return false }
        guard let expectedRowCount else { return true }
        return viewController.testRowCount(inSection: 0) == expectedRowCount
    }
    #expect(didReveal)
}

@discardableResult
@MainActor
private func waitUntil(
    timeout: TimeInterval = 1,
    pollInterval: UInt64 = 20_000_000,
    condition: @MainActor () -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() {
            return true
        }
        try? await Task.sleep(nanoseconds: pollInterval)
    }
    return false
}
