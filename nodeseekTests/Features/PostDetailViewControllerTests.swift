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
import WebKit
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
        let viewController = PostDetailViewController(
            presenter: presenter,
            accountRefresher: StubPostDetailAccountRefresher(isLoggedIn: true)
        )

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

    @Test func detailWithPaginationKeepsOnlyContentRows() async throws {
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
    }

    @Test func appendingCommentPageInsertsOnlyNewCommentRows() async throws {
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
                Comment(id: "1", authorName: "a", avatarURL: nil, floorText: "#1", createdAtText: "1min ago", contentHTML: "<p>第一页</p>")
            ],
            page: 1,
            pagination: PostDetailPagination(
                currentPage: 1,
                items: [
                    PostDetailPageItem(page: 1, url: nil, isCurrent: true),
                    PostDetailPageItem(page: 2, url: nil, isCurrent: false)
                ],
                previousPage: nil,
                nextPage: 2
            )
        ))
        await waitForDetailContent(in: viewController, expectedRowCount: 3)

        viewController.appendCommentPage(detail: PostDetail(
            id: "703863",
            title: "详情标题",
            authorName: "ipv4",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>第二页正文不应替换 header</p>",
            comments: [
                Comment(id: "2", authorName: "b", avatarURL: nil, floorText: "#2", createdAtText: "2min ago", contentHTML: "<p>第二页</p>")
            ],
            page: 2,
            pagination: PostDetailPagination(
                currentPage: 2,
                items: [
                    PostDetailPageItem(page: 1, url: nil, isCurrent: false),
                    PostDetailPageItem(page: 2, url: nil, isCurrent: true)
                ],
                previousPage: 1,
                nextPage: nil
            )
        ))

        #expect(viewController.testRowCount(inSection: 0) == 4)
        #expect(viewController.comments.map(\.id) == ["1", "2"])
        #expect(viewController.testHeaderContent()?.contentHTML == "<p>正文</p>")
    }

    @Test func footerRefreshButtonAppearsAtEndAndTapsPresenter() async throws {
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
                Comment(id: "1", authorName: "a", avatarURL: nil, floorText: "#1", createdAtText: "1min ago", contentHTML: "<p>第一页</p>")
            ],
            page: 1,
            pagination: PostDetailPagination(currentPage: 1, items: [PostDetailPageItem(page: 1, url: nil, isCurrent: true)], previousPage: nil, nextPage: nil)
        ))
        await waitForDetailContent(in: viewController, expectedRowCount: 3)

        let button = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-detail-refresh-comments-at-end-button"))
        #expect(button.isHidden == false)
        #expect(button.configuration?.title == "点击加载新评论")
        #expect(button.configuration?.image == nil)
        let footer = try #require(viewController.tableNode.view.tableFooterView)
        #expect(footer.subviews.contains { $0.backgroundColor == .separator })

        button.sendActions(for: .touchUpInside)
        #expect(presenter.didTapRefreshCommentsAtEndCount == 1)
    }

    @Test func refreshingCurrentCommentPageDiffsRowsWithoutReplacingHeader() async throws {
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
                Comment(id: "1", authorName: "a", avatarURL: nil, floorText: "#1", createdAtText: "1min ago", contentHTML: "<p>第一页</p>")
            ],
            page: 1,
            pagination: PostDetailPagination(
                currentPage: 1,
                items: [
                    PostDetailPageItem(page: 1, url: nil, isCurrent: true),
                    PostDetailPageItem(page: 2, url: nil, isCurrent: false)
                ],
                previousPage: nil,
                nextPage: 2
            )
        ))
        await waitForDetailContent(in: viewController, expectedRowCount: 3)
        viewController.appendCommentPage(detail: PostDetail(
            id: "703863",
            title: "详情标题",
            authorName: "ipv4",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>第二页正文不应替换 header</p>",
            comments: [
                Comment(id: "2", authorName: "b", avatarURL: nil, floorText: "#2", createdAtText: "2min ago", contentHTML: "<p>第二页旧评论</p>")
            ],
            page: 2,
            pagination: PostDetailPagination(
                currentPage: 2,
                items: [
                    PostDetailPageItem(page: 1, url: nil, isCurrent: false),
                    PostDetailPageItem(page: 2, url: nil, isCurrent: true)
                ],
                previousPage: 1,
                nextPage: nil
            )
        ))

        viewController.refreshCurrentCommentPage(detail: PostDetail(
            id: "703863",
            title: "详情标题",
            authorName: "ipv4",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>刷新不应替换 header</p>",
            comments: [
                Comment(id: "2", authorName: "b", avatarURL: nil, floorText: "#2", createdAtText: "2min ago", contentHTML: "<p>第二页新评论</p>"),
                Comment(id: "3", authorName: "c", avatarURL: nil, floorText: "#3", createdAtText: "刚刚", contentHTML: "<p>新增评论</p>")
            ],
            page: 2,
            pagination: PostDetailPagination(
                currentPage: 2,
                items: [
                    PostDetailPageItem(page: 1, url: nil, isCurrent: false),
                    PostDetailPageItem(page: 2, url: nil, isCurrent: true)
                ],
                previousPage: 1,
                nextPage: nil
            )
        ))

        #expect(viewController.testRowCount(inSection: 0) == 5)
        #expect(viewController.comments.map(\.id) == ["1", "2", "3"])
        #expect(viewController.comments.map(\.contentHTML) == ["<p>第一页</p>", "<p>第二页新评论</p>", "<p>新增评论</p>"])
        #expect(viewController.testHeaderContent()?.contentHTML == "<p>正文</p>")
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
        var confirmationContext: PostDetailActionConfirmationContext?
        var confirmAction: (() -> Void)?
        viewController.actionConfirmationPresenter = { _, context, onConfirm in
            confirmationContext = context
            confirmAction = onConfirm
        }

        viewController.handlePostChickenLegTap(header)

        #expect(confirmationContext == .postChickenLeg)
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
        var confirmationContext: PostDetailActionConfirmationContext?
        var confirmAction: (() -> Void)?
        viewController.actionConfirmationPresenter = { _, context, onConfirm in
            confirmationContext = context
            confirmAction = onConfirm
        }

        viewController.handleCommentChickenLegTap(comment)

        #expect(confirmationContext == .commentChickenLeg)
        #expect(presenter.chickenLeggedCommentIDs.isEmpty)

        let action = try #require(confirmAction)
        action()

        #expect(presenter.chickenLeggedCommentIDs == ["9835758"])
    }

    @Test func tappingPostLikeRequiresConfirmationBeforeSubmitting() throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)
        let header = PostDetailHeaderContent(
            postID: "710379",
            title: "带操作区的主题",
            authorName: "mist",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>正文</p>",
            likeCount: 1
        )
        var confirmationContext: PostDetailActionConfirmationContext?
        var confirmAction: (() -> Void)?
        viewController.actionConfirmationPresenter = { _, context, onConfirm in
            confirmationContext = context
            confirmAction = onConfirm
        }

        viewController.handlePostLikeTap(header)

        #expect(confirmationContext == .postLike)
        #expect(presenter.didTapPostLikeCount == 0)

        let action = try #require(confirmAction)
        action()

        #expect(presenter.didTapPostLikeCount == 1)
    }

    @Test func tappingCommentLikeRequiresConfirmationBeforeSubmitting() throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)
        let comment = Comment(
            id: "9835758",
            authorName: "mist",
            avatarURL: nil,
            floorText: "#1",
            createdAtText: "刚刚",
            contentHTML: "<p>内容</p>",
            likeCount: 1
        )
        var confirmationContext: PostDetailActionConfirmationContext?
        var confirmAction: (() -> Void)?
        viewController.actionConfirmationPresenter = { _, context, onConfirm in
            confirmationContext = context
            confirmAction = onConfirm
        }

        viewController.handleCommentLikeTap(comment)

        #expect(confirmationContext == .commentLike)
        #expect(presenter.likedCommentIDs.isEmpty)

        let action = try #require(confirmAction)
        action()

        #expect(presenter.likedCommentIDs == ["9835758"])
    }

    @Test func tappingPostOpposeRequiresConfirmationBeforeSubmitting() throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)
        let header = PostDetailHeaderContent(
            postID: "710379",
            title: "带操作区的主题",
            authorName: "mist",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>正文</p>",
            opposeCount: 1
        )
        var confirmationContext: PostDetailActionConfirmationContext?
        var confirmAction: (() -> Void)?
        viewController.actionConfirmationPresenter = { _, context, onConfirm in
            confirmationContext = context
            confirmAction = onConfirm
        }

        viewController.handlePostOpposeTap(header)

        #expect(confirmationContext == .postOppose)
        #expect(presenter.didTapPostOpposeCount == 0)

        let action = try #require(confirmAction)
        action()

        #expect(presenter.didTapPostOpposeCount == 1)
    }

    @Test func tappingCommentOpposeRequiresConfirmationBeforeSubmitting() throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)
        let comment = Comment(
            id: "9835758",
            authorName: "mist",
            avatarURL: nil,
            floorText: "#1",
            createdAtText: "刚刚",
            contentHTML: "<p>内容</p>",
            opposeCount: 1
        )
        var confirmationContext: PostDetailActionConfirmationContext?
        var confirmAction: (() -> Void)?
        viewController.actionConfirmationPresenter = { _, context, onConfirm in
            confirmationContext = context
            confirmAction = onConfirm
        }

        viewController.handleCommentOpposeTap(comment)

        #expect(confirmationContext == .commentOppose)
        #expect(presenter.opposedCommentIDs.isEmpty)

        let action = try #require(confirmAction)
        action()

        #expect(presenter.opposedCommentIDs == ["9835758"])
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
        var copiedString: String?
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
            currentPage: 2,
            pasteboardStringWriter: { copiedString = $0 }
        )
        viewController.loadViewIfNeeded()

        viewController.copyCurrentPostLink()

        #expect(copiedString == "https://www.nodeseek.com/post-703863-2")
    }

    @Test func copyCurrentPostLinkKeepsInitialPageAfterLoadingMore() async throws {
        let presenter = SpyPostDetailPresenter()
        var copiedString: String?
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
            currentPage: 2,
            pasteboardStringWriter: { copiedString = $0 }
        )
        viewController.loadViewIfNeeded()
        viewController.render(detail: PostDetail(
            id: "703863",
            title: "详情标题",
            authorName: "ipv4",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>正文</p>",
            comments: [
                Comment(id: "1", authorName: "a", avatarURL: nil, floorText: "#1", createdAtText: nil, contentHTML: "<p>第二页</p>")
            ],
            page: 2
        ))
        await waitForDetailContent(in: viewController, expectedRowCount: 4)
        viewController.appendCommentPage(detail: PostDetail(
            id: "703863",
            title: "详情标题",
            authorName: "ipv4",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>正文</p>",
            comments: [
                Comment(id: "2", authorName: "b", avatarURL: nil, floorText: "#2", createdAtText: nil, contentHTML: "<p>第三页</p>")
            ],
            page: 3
        ))

        viewController.copyCurrentPostLink()

        #expect(copiedString == "https://www.nodeseek.com/post-703863-2")
    }

    @Test func openInBrowserKeepsInitialPageAfterLoadingMore() async throws {
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
        let navigationController = UINavigationController(rootViewController: viewController)
        viewController.loadViewIfNeeded()
        viewController.render(detail: PostDetail(
            id: "703863",
            title: "详情标题",
            authorName: "ipv4",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>正文</p>",
            comments: [
                Comment(id: "1", authorName: "a", avatarURL: nil, floorText: "#1", createdAtText: nil, contentHTML: "<p>第二页</p>")
            ],
            page: 2
        ))
        await waitForDetailContent(in: viewController, expectedRowCount: 4)
        viewController.appendCommentPage(detail: PostDetail(
            id: "703863",
            title: "详情标题",
            authorName: "ipv4",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>正文</p>",
            comments: [
                Comment(id: "2", authorName: "b", avatarURL: nil, floorText: "#2", createdAtText: nil, contentHTML: "<p>第三页</p>")
            ],
            page: 3
        ))

        viewController.openInBrowserTapped()

        let webViewController = try #require(navigationController.topViewController as? NodeSeekWebViewController)
        #expect(webViewController.testInitialURL.absoluteString == "https://www.nodeseek.com/post-703863-2")
    }

    @Test func enteringNonFirstPageShowsEntryHintRow() async throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter, currentPage: 6)
        viewController.loadViewIfNeeded()

        viewController.render(detail: PostDetail(
            id: "717963",
            title: "详情标题",
            authorName: "ipv4",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>正文</p>",
            comments: [
                Comment(id: "1", authorName: "a", avatarURL: nil, floorText: "#1", createdAtText: nil, contentHTML: "<p>第六页</p>")
            ],
            page: 6
        ))
        await waitForDetailContent(in: viewController)

        // 预期：header + entryHint + divider + 1 comment
        #expect(viewController.testRowCount() == 4)
        #expect(viewController.testDetailRowKinds() == ["header", "entryHint", "postRepliesDivider", "comment"])
    }

    @Test func entryHintCellRefreshesAppearanceWhenThemeChanges() {
        let node = PostDetailEntryHintCellNode(page: 6, onOpenFullPost: {})
        node.layoutIfNeeded()

        let didRefresh = node.refreshAppearanceForCurrentTraits()

        #expect(didRefresh)
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

    @Test func mergedRendererIncludesPostSignatureWithoutChangingSourceContent() throws {
        let bodyHTML = "<p>正文</p>"
        let signatureHTML = "<p>签名</p>"
        let rendered = try #require(PostDetailViewController.makeRenderedContent(
            html: bodyHTML,
            signatureHTML: signatureHTML,
            baseURL: URL(string: "https://www.nodeseek.com")!,
            maxImageWidth: 320
        ))
        let text = rendered.compactMap { block -> String? in
            if case .text(let attributedText) = block {
                return attributedText.string
            }
            return nil
        }.joined(separator: "\n")

        #expect(text.contains("正文"))
        #expect(text.contains("签名"))
        #expect(bodyHTML == "<p>正文</p>")
        #expect(signatureHTML == "<p>签名</p>")
    }

    @Test func mergedRendererOmitsSignatureWhenDisplaySettingIsDisabled() throws {
        let rendered = try #require(PostDetailViewController.makeRenderedContent(
            html: "<p>正文</p>",
            signatureHTML: "<p>签名</p>",
            baseURL: URL(string: "https://www.nodeseek.com")!,
            maxImageWidth: 320,
            showsSignature: false
        ))
        let text = rendered.compactMap { block -> String? in
            if case .text(let attributedText) = block {
                return attributedText.string
            }
            return nil
        }.joined(separator: "\n")

        #expect(text.contains("正文"))
        #expect(text.contains("签名") == false)
    }

    @Test func mergedRendererAllowsMultipleSignatureLines() throws {
        let rendered = try #require(PostDetailViewController.makeRenderedContent(
            html: "<p>正文</p>",
            signatureHTML: "<p>第一行签名内容<br>第二行签名内容<br>第三行签名内容</p>",
            baseURL: URL(string: "https://www.nodeseek.com")!,
            maxImageWidth: 120
        ))
        let text = try #require(rendered.compactMap { block -> NSAttributedString? in
            if case .text(let attributedText) = block {
                return attributedText
            }
            return nil
        }.first)
        let richTextNode = DetailRichTextNode(
            attributedText: text,
            onImageTapped: { _, _ in },
            onLayoutInvalidated: {}
        )

        let layout = richTextNode.layoutThatFits(ASSizeRange(
            min: .zero,
            max: CGSize(width: 120, height: CGFloat.greatestFiniteMagnitude)
        ))

        #expect(layout.size.height > 60)
    }

    @Test func mergedRendererKeepsSingleLineSignatureCompact() throws {
        let rendered = try #require(PostDetailViewController.makeRenderedContent(
            html: "<p>各位大佬可以带自己的 AFF 哈</p>",
            signatureHTML: "<p>人生未定，步履即章</p>",
            baseURL: URL(string: "https://www.nodeseek.com")!,
            maxImageWidth: 320
        ))
        let attributedText = try #require(rendered.compactMap { block -> NSAttributedString? in
            if case .text(let attributedText) = block {
                return attributedText
            }
            return nil
        }.first)
        let richTextNode = DetailRichTextNode(
            attributedText: attributedText,
            onImageTapped: { _, _ in },
            onLayoutInvalidated: {}
        )

        let layout = richTextNode.layoutThatFits(ASSizeRange(
            min: .zero,
            max: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
        ))

        #expect(attributedText.string.contains("哈\n\n人生") == false)
        #expect(layout.size.height < 70)
    }

    @Test func mergedRendererUsesMutedTextAndLinkColorsForSignatureOnly() throws {
        let rendered = try #require(PostDetailViewController.makeRenderedContent(
            html: "<p>正文</p>",
            signatureHTML: "<p>签名 <a href=\"https://example.com\">链接</a></p>",
            baseURL: URL(string: "https://www.nodeseek.com")!,
            maxImageWidth: 320
        ))
        let attributedText = try #require(rendered.compactMap { block -> NSAttributedString? in
            if case .text(let text) = block {
                return text
            }
            return nil
        }.first)
        let bodyRange = (attributedText.string as NSString).range(of: "正文")
        let signatureRange = (attributedText.string as NSString).range(of: "签名")
        let linkRange = (attributedText.string as NSString).range(of: "链接")
        #expect(bodyRange.location != NSNotFound)
        #expect(signatureRange.location != NSNotFound)
        #expect(linkRange.location != NSNotFound)
        let bodyColor = try #require(
            attributedText.attribute(.foregroundColor, at: bodyRange.location, effectiveRange: nil) as? UIColor
        )
        let signatureColor = try #require(
            attributedText.attribute(.foregroundColor, at: signatureRange.location, effectiveRange: nil) as? UIColor
        )
        let linkColor = try #require(
            attributedText.attribute(.foregroundColor, at: linkRange.location, effectiveRange: nil) as? UIColor
        )

        #expect(bodyColor != NodeSeekSignatureStyle.textColor)
        #expect(signatureColor == NodeSeekSignatureStyle.textColor)
        #expect(linkColor == NodeSeekSignatureStyle.linkColor)
        #expect(linkColor.isClose(to: UIColor(red: 111 / 255, green: 163 / 255, blue: 143 / 255, alpha: 0.76)))
        #expect(linkColor != NodeSeekLinkStyle.color)
    }

    @Test func mergedRendererNormalizesHeadingSignatureTypography() throws {
        let rendered = try #require(PostDetailViewController.makeRenderedContent(
            html: "<p>正文</p>",
            signatureHTML: "<h2>标题签名</h2>",
            baseURL: URL(string: "https://www.nodeseek.com")!,
            maxImageWidth: 320
        ))
        let attributedText = try #require(rendered.compactMap { block -> NSAttributedString? in
            if case .text(let text) = block {
                return text
            }
            return nil
        }.first)
        let signatureRange = (attributedText.string as NSString).range(of: "标题签名")
        #expect(signatureRange.location != NSNotFound)
        let font = try #require(
            attributedText.attribute(.font, at: signatureRange.location, effectiveRange: nil) as? UIFont
        )
        let paragraphStyle = try #require(
            attributedText.attribute(.paragraphStyle, at: signatureRange.location, effectiveRange: nil) as? NSParagraphStyle
        )

        #expect(font.pointSize == AppTypography.signatureFont().pointSize)
        #expect(font.fontDescriptor.symbolicTraits.contains(.traitBold) == false)
        #expect(paragraphStyle.paragraphSpacing == 0)
        #expect(paragraphStyle.paragraphSpacingBefore == 6)
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
        #expect(node.debugReactionActionPreferredWidths.allSatisfy { $0 > PostDetailContentLayout.reactionActionMinWidth })
    }

    @Test func postBodyCellUsesDynamicWidthForTwoDigitFavoriteCount() {
        let header = PostDetailHeaderContent(
            postID: "710379",
            title: "带操作区的主题",
            authorName: "mist",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>正文</p>",
            favoriteCount: 10
        )
        let node = PostBodyCellNode(
            content: header,
            renderedContent: [],
            onImageTapped: { _, _ in },
            onTextLayoutInvalidated: {}
        )

        #expect(node.debugReactionActionTitles[3] == "10")
        #expect(node.debugReactionActionPreferredWidths[3] > PostDetailContentLayout.reactionActionMinWidth)
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
        #expect((node.debugAuthorAttributedTitle?.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)?.pointSize == AppTextSizeSettings.adjustedPointSize(basePointSize: 17))
        #expect((node.debugAuthorAttributedTitle?.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
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
        var copiedString: String?
        let view = DetailCodeBlockView(
            codeBlock: codeBlock,
            pasteboardStringWriter: { copiedString = $0 }
        )
        view.frame = CGRect(x: 0, y: 0, width: 240, height: 120)
        view.layoutIfNeeded()

        let button = try #require(view.firstButton(accessibilityIdentifier: "detail-code-copy-button"))
        button.sendActions(for: .touchUpInside)

        #expect(copiedString == codeBlock.text)
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

    @Test func loadedOffscreenFloorLinkPresentsCommentPreview() async throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let comments = (1...40).map { index in
            Comment(
                id: "comment-\(index)",
                anchorID: index == 40 ? nil : "\(index)",
                authorName: "author-\(index)",
                avatarURL: nil,
                floorText: index == 40 ? "#326" : "#\(index)",
                createdAtText: "\(index)min ago",
                contentHTML: "<p>第 \(index) 楼内容</p>"
            )
        }

        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.render(detail: PostDetail(
            id: "703863",
            title: "详情标题",
            authorName: "ipv4",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>正文</p>",
            comments: comments,
            page: 1,
            pagination: nil
        ))
        await waitForDetailContent(in: viewController)
        viewController.testVisibleAnchorIDs = []

        let url = try #require(URL(string: "#326", relativeTo: baseURL)?.absoluteURL)
        viewController.handleContentLinkTap(url)

        #expect(viewController.testPresentedLoadedCommentID() == "comment-40")
        #expect(viewController.testPresentedPreviewUsesCommentCellRendering())
        #expect((viewController.testPresentedPreviewPreferredHeight() ?? 0) < viewController.view.bounds.height)
        #expect(viewController.testPresentedPreviewKeepsCloseButtonOutsideContent())
        #expect(viewController.testPresentedPreviewUsesBottomSheet())
        #expect(viewController.testPresentedPreviewShowsFullPostButton() == false)
        #expect(viewController.testHighlightedAnchorID() == nil)
        await tearDownPostDetailTextureViewController(viewController)
    }

    @Test func loadedCommentPreviewFollowsDarkInterfaceStyleAndUsesSystemColors() async throws {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.overrideUserInterfaceStyle = .dark
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let comments = (1...40).map { index in
            Comment(
                id: "comment-\(index)",
                anchorID: index == 40 ? nil : "\(index)",
                authorName: "author-\(index)",
                avatarURL: nil,
                floorText: index == 40 ? "#326" : "#\(index)",
                createdAtText: "\(index)min ago",
                contentHTML: "<p>第 \(index) 楼内容</p>"
            )
        }

        window.rootViewController = viewController
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
        }
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.render(detail: PostDetail(
            id: "703863",
            title: "详情标题",
            authorName: "ipv4",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>正文</p>",
            comments: comments,
            page: 1,
            pagination: nil
        ))
        await waitForDetailContent(in: viewController)
        viewController.testVisibleAnchorIDs = []

        let url = try #require(URL(string: "#326", relativeTo: baseURL)?.absoluteURL)
        viewController.handleContentLinkTap(url)

        let didPresentPreview = await waitUntil {
            viewController.presentedViewController != nil
        }
        #expect(didPresentPreview)
        let previewController = try #require(viewController.presentedViewController)
        previewController.loadViewIfNeeded()

        #expect(previewController.overrideUserInterfaceStyle == .dark)
        #expect(previewController.view.backgroundColor == .systemBackground)
        #expect(previewController.view.firstSubview(of: UITableView.self)?.backgroundColor == .systemBackground)
        #expect(previewController.view.allSubviews(of: UIView.self).contains { $0.backgroundColor == .separator })
        let revealButton = try #require(
            previewController.view.allSubviews(of: UIButton.self).first { $0.configuration?.title == "查看原楼" }
        )
        #expect(revealButton.configuration?.baseBackgroundColor == .secondarySystemBackground)
        #expect(revealButton.configuration?.baseForegroundColor == .label)
        await tearDownPostDetailTextureViewController(viewController, window: window)
    }

    @Test func fullPostPreviewActionOpensPostFromBeginning() async throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(
            presenter: presenter,
            currentPage: 3,
            initialAnchorID: "326"
        )

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
                    id: "target-comment",
                    anchorID: "326",
                    authorName: "a",
                    avatarURL: nil,
                    floorText: "#326",
                    createdAtText: "1min ago",
                    contentHTML: "<p>目标楼层</p>"
                )
            ],
            page: 3,
            pagination: nil
        ))
        await waitForDetailContent(in: viewController)

        viewController.testOpenFullPostFromFloorPreview()

        #expect(viewController.testOpenedFullPostPage() == 1)
        #expect(viewController.testOpenedFullPostAnchorWasNil())
        await tearDownPostDetailTextureViewController(viewController)
    }

    @Test func floorPreviewShowsFullPostActionOnlyForInitialAnchorDetail() async throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(
            presenter: presenter,
            currentPage: 3,
            initialAnchorID: "326"
        )
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))

        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.render(detail: PostDetail(
            id: "703863",
            title: "详情标题",
            authorName: "ipv4",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>正文</p>",
            comments: [
                Comment(
                    id: "target-comment",
                    anchorID: "326",
                    authorName: "a",
                    avatarURL: nil,
                    floorText: "#326",
                    createdAtText: "1min ago",
                    contentHTML: "<p>目标楼层</p>"
                )
            ],
            page: 3,
            pagination: nil
        ))
        await waitForDetailContent(in: viewController)
        viewController.testVisibleAnchorIDs = []

        let url = try #require(URL(string: "#326", relativeTo: baseURL)?.absoluteURL)
        viewController.handleContentLinkTap(url)

        #expect(viewController.testPresentedPreviewShowsFullPostButton())
        await tearDownPostDetailTextureViewController(viewController)
    }

    @Test func loadedVisibleFloorLinkUsesExistingHighlightInsteadOfPreview() async throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))

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
                    id: "visible-comment",
                    anchorID: nil,
                    authorName: "a",
                    avatarURL: nil,
                    floorText: "#326",
                    createdAtText: "1min ago",
                    contentHTML: "<p>可见楼层</p>"
                )
            ],
            page: 1,
            pagination: nil
        ))
        await waitForDetailContent(in: viewController)
        viewController.testVisibleAnchorIDs = ["326"]

        let url = try #require(URL(string: "#326", relativeTo: baseURL)?.absoluteURL)
        viewController.handleContentLinkTap(url)

        #expect(viewController.testHighlightedAnchorID() == "326")
        #expect(viewController.testPresentedLoadedCommentID() == nil)
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

    @Test func resolvesExternalAppSchemesOutsideSafari() throws {
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let url = try #require(URL(string: "clash://install-config?url=https%3A%2F%2Fexample.com%2Fsub.yaml"))

        let destination = try #require(PostDetailLinkResolver.destination(for: url, baseURL: baseURL))

        guard case .externalApp(let resolvedURL) = destination else {
            Issue.record("Expected non-http external links to open outside Safari")
            return
        }
        #expect(resolvedURL.absoluteString == "clash://install-config?url=https%3A%2F%2Fexample.com%2Fsub.yaml")
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

    @Test func richTextViewDoesNotRelayoutWhenLoadedStickerKeepsCachedDisplaySize() async throws {
        let baseURL = try #require(URL(string: "https://www.nodeseek.com"))
        let stickerURL = try #require(URL(string: "https://www.nodeseek.com/static/image/sticker/xhj/003.png"))
        let cache = StickerAspectRatioCache(storageURL: nil)
        cache.recordLoadedSize(CGSize(width: 80, height: 160), for: stickerURL)
        let blocks = DTCoreTextHTMLContentRenderer(stickerAspectRatioProvider: cache).render(
            fragment: "<p><img src=\"/static/image/sticker/xhj/003.png\"></p>",
            baseURL: baseURL,
            maxImageWidth: 320
        )
        let attributedText = try #require(blocks.compactMap { block -> NSAttributedString? in
            guard case .text(let text) = block else { return nil }
            return text
        }.first)
        var didInvalidateLayout = false
        let richTextView = DetailRichTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 120))
        richTextView.configure(
            attributedText,
            onImageTapped: nil,
            onLinkTapped: nil,
            onLayoutInvalidated: {
                didInvalidateLayout = true
            }
        )

        richTextView.debugHandleLoadedImage(stickerURL, imageSize: CGSize(width: 80, height: 160))
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(didInvalidateLayout == false)
    }

    @Test func quoteBlockNodeKeepsBorderVertical() throws {
        let textNode = ASTextNode()
        textNode.maximumNumberOfLines = 0
        textNode.attributedText = NSAttributedString(
            string: "引用内容\n第二行",
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .body),
                .foregroundColor: UIColor.label
            ]
        )
        let quoteNode = DetailQuoteBlockNode(children: [textNode])
        let layout = quoteNode.layoutThatFits(ASSizeRange(
            min: .zero,
            max: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
        ))
        let borderLayout = try #require(layout.firstLayoutElement(identicalTo: quoteNode.debugBorderNode))

        #expect(borderLayout.position.x == 0)
        #expect(borderLayout.position.y == 0)
        #expect(borderLayout.size.width == 3)
        #expect(borderLayout.size.height > borderLayout.size.width)
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
        if #available(iOS 16.0, *) {
            #expect(options[AVURLAssetHTTPUserAgentKey] as? String == WebRequestFingerprint.userAgent)
        }
    }

    @Test func imageBlockCapsLargeNormalImagesAtHalfWidthHeight() {
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
        #expect(loadedLayout.height == 160)
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
        #expect(layout.size.height == 160)
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

    @Test func contentBlockFactoryCreatesFullWidthIframeLinkNode() throws {
        let openURL = try #require(URL(string: "https://player.bilibili.com/player.html?bvid=BV1GUdgBdESz"))
        let nodes = DetailContentBlockNodeFactory.makeNodes(
            from: [
                .iframeLink(RenderedIFrameLinkBlock(
                    source: "//player.bilibili.com/player.html?bvid=BV1GUdgBdESz",
                    displayDomain: "player.bilibili.com",
                    openURL: openURL
                ))
            ],
            onImageTapped: { _, _ in },
            onLinkTapped: { _ in },
            onTextLayoutInvalidated: {}
        )
        let node = try #require(nodes.first)
        #expect(String(describing: type(of: node)).contains("DetailIFrameLinkNode"))

        let layout = node.layoutThatFits(ASSizeRange(
            min: .zero,
            max: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
        ))
        #expect(layout.size.width == 320)
        #expect(layout.size.height > 0)
    }

    @Test func iframeLinkTitleIncludesClickToViewHint() {
        let title = DetailIFrameLinkLayout.titleText(displayDomain: "player.bilibili.com")

        #expect(title == "嵌入内容 · player.bilibili.com · 点击查看")
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
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
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
        viewController.view.layoutIfNeeded()

        #expect(viewController.view.firstTextView(accessibilityIdentifier: "post-detail-comment-input") == nil)
        #expect(viewController.view.firstButton(accessibilityIdentifier: "post-detail-comment-send-button") == nil)
        #expect(viewController.view.firstLabel(accessibilityIdentifier: "post-detail-comment-placeholder-label") == nil)

        let floatingReplyButton = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-detail-reply-button"))
        #expect(floatingReplyButton.isHidden == false)
        let floatingContainer = try #require(
            viewController.view.firstView(accessibilityIdentifier: "post-detail-floating-reply-button") as? FloatingControlContainerView
        )
        let panGesture = try #require(floatingReplyButton.gestureRecognizers?.first { $0 is UIPanGestureRecognizer })
        let replyButtonFrame = floatingReplyButton.convert(floatingReplyButton.bounds, to: viewController.view)

        #expect(panGesture.view === floatingReplyButton)
        #expect(panGesture.cancelsTouchesInView)
        #expect(floatingReplyButton.superview === floatingContainer)
        #expect(floatingReplyButton.configuration?.baseForegroundColor == .systemBackground)
        #expect(floatingReplyButton.backgroundColor == .label)
        #expect(floatingReplyButton.alpha == 0.48)
        #expect(floatingReplyButton.layer.borderWidth == 0.5)
        #expect(abs(replyButtonFrame.maxY - (viewController.view.safeAreaLayoutGuide.layoutFrame.maxY - PostDetailViewController.Layout.replyButtonBottomInset)) < 1)

        floatingContainer.frame.origin.x = 0
        floatingContainer.floatingViewDidEndDragging(panGestureRecognizer: UIPanGestureRecognizer())
        #expect(floatingReplyButton.layer.maskedCorners == [.layerMaxXMinYCorner, .layerMaxXMaxYCorner])
    }

    @Test func detailReplyButtonRestoresLastDraggedPosition() async throws {
        let positionStore = InMemoryFloatingControlPositionStore()

        let firstViewController = PostDetailViewController(
            presenter: SpyPostDetailPresenter(),
            floatingPositionStore: positionStore
        )
        firstViewController.loadViewIfNeeded()
        firstViewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        firstViewController.render(detail: PostDetail(
            id: "703863",
            title: "详情标题",
            authorName: "ipv4",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>正文</p>",
            comments: []
        ))
        await waitForDetailContent(in: firstViewController, expectedRowCount: 1)
        firstViewController.view.layoutIfNeeded()

        let firstContainer = try #require(
            firstViewController.view.firstView(accessibilityIdentifier: "post-detail-floating-reply-button") as? FloatingControlContainerView
        )
        firstContainer.frame.origin.x = 0
        firstContainer.frame.origin.y = 128
        firstContainer.floatingViewDidEndDragging(panGestureRecognizer: UIPanGestureRecognizer())

        let secondViewController = PostDetailViewController(
            presenter: SpyPostDetailPresenter(),
            floatingPositionStore: positionStore
        )
        secondViewController.loadViewIfNeeded()
        secondViewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        secondViewController.render(detail: PostDetail(
            id: "703863",
            title: "详情标题",
            authorName: "ipv4",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>正文</p>",
            comments: []
        ))
        await waitForDetailContent(in: secondViewController, expectedRowCount: 1)
        secondViewController.view.layoutIfNeeded()

        let restoredContainer = try #require(
            secondViewController.view.firstView(accessibilityIdentifier: "post-detail-floating-reply-button") as? FloatingControlContainerView
        )
        let restoredButton = try #require(secondViewController.view.firstButton(accessibilityIdentifier: "post-detail-reply-button"))

        #expect(abs(restoredContainer.frame.minX) < 0.5)
        #expect(abs(restoredContainer.frame.minY - firstContainer.frame.minY) < 1)
        #expect(restoredButton.layer.maskedCorners == [.layerMaxXMinYCorner, .layerMaxXMaxYCorner])
    }

    @Test func restrictedDetailHidesReplyEntry() async throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)
        let html = """
        <html data-server-rendered="true">
        <head><title>NodeSeek</title></head>
        <body>
            <section id="nsk-frame">
                <div id="nsk-body" class="nsk-container">
                    <div id="nsk-body-left">
                        <div style="min-height:300px;display:flex;align-items:center;justify-content:center;font-size:2rem;">
                            <div style="line-height: 1.25;">本帖已经被用户设为私有，您没有阅读权限</div>
                        </div>
                    </div>
                </div>
            </section>
        </body>
        </html>
        """
        let detail = try KannaNodeSeekParser(baseURL: URL(string: "https://www.nodeseek.com")!).parsePostDetail(
            html: html,
            url: URL(string: "https://www.nodeseek.com/post-704286-1")!
        )

        viewController.loadViewIfNeeded()
        viewController.render(detail: detail)
        await waitForDetailContent(in: viewController, expectedRowCount: 1)

        let floatingReplyButton = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-detail-reply-button"))
        #expect(floatingReplyButton.isHidden)
    }

    @Test func commentComposerAddsNonCancellingDismissKeyboardTapGesture() throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)

        viewController.loadViewIfNeeded()

        let tapGesture = try #require(viewController.view.gestureRecognizers?.compactMap { $0 as? UITapGestureRecognizer }.first)
        #expect(tapGesture.cancelsTouchesInView == false)
    }

    @Test func dismissingReplyEditorKeepsContextForLaterAdditionalTargets() async throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(
            presenter: presenter,
            accountRefresher: StubPostDetailAccountRefresher(isLoggedIn: true)
        )
        let comment = Comment(
            id: "1",
            anchorID: "10",
            authorName: "netcup",
            avatarURL: nil,
            floorText: "#10",
            createdAtText: "1min ago",
            contentHTML: "<p>第一段</p>"
        )
        let second = Comment(
            id: "2",
            anchorID: "11",
            authorName: "alice",
            avatarURL: nil,
            floorText: "#11",
            createdAtText: "2min ago",
            contentHTML: "<p>第二段</p>"
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

        viewController.handleQuote(comment)
        await Task.yield()
        viewController.dismissReplyEditor()

        #expect(viewController.replyEditorContainer.isHidden)

        viewController.handleQuote(second)
        await Task.yield()

        #expect(viewController.replyContextStackView.arrangedSubviews.count == 2)
        let contextLabel = try #require(viewController.view.firstLabel(accessibilityIdentifier: "post-detail-reply-context-label"))
        let secondContextLabel = try #require(
            viewController.view.firstLabel(accessibilityIdentifier: "post-detail-reply-context-label-1")
        )
        #expect(contextLabel.text == "引用 netcup #10")
        #expect(secondContextLabel.text == "引用 alice #11")
    }

    @Test func replyButtonShowsEditorWithoutWaitingForFreshAccountWhenCachedLoginExists() async throws {
        let presenter = SpyPostDetailPresenter()
        let accountRefresher = DelayedPostDetailAccountRefresher(isLoggedIn: true)
        let viewController = PostDetailViewController(
            presenter: presenter,
            accountRefresher: accountRefresher
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

        viewController.replyButtonTapped()
        await Task.yield()

        #expect(viewController.replyEditorContainer.isHidden == false)
    }

    @Test func replyAndQuoteActionsUpdateComposerState() async throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(
            presenter: presenter,
            accountRefresher: StubPostDetailAccountRefresher(isLoggedIn: true)
        )
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
        await Task.yield()
        let contextLabel = try #require(viewController.view.firstLabel(accessibilityIdentifier: "post-detail-reply-context-label"))
        #expect(contextLabel.text == "回复 netcup #10")

        let cancelButton = try #require(viewController.view.firstButton(accessibilityLabel: "取消引用"))
        cancelButton.sendActions(for: .touchUpInside)
        #expect(viewController.replyContextBar.isHidden)
        #expect(viewController.view.firstLabel(accessibilityIdentifier: "post-detail-reply-context-label") == nil)

        viewController.handleQuote(comment)
        await Task.yield()
        let replyTextView = try #require(viewController.view.firstTextView(accessibilityIdentifier: "post-detail-reply-text-view"))
        replyTextView.text = "正文"
        let sendButton = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-detail-reply-send-button"))
        sendButton.sendActions(for: .touchUpInside)
        await Task.yield()
        #expect(presenter.sentReplyContent?.contains("> @netcup [#10]") == true)
        #expect(presenter.sentReplyContent?.contains("第一段") == true)
        #expect(presenter.sentReplyContent?.contains("第二段") == false)
    }

    @Test func hiddenReplyContextCanCollapseWithoutRequiredPaddingConflict() throws {
        let viewController = PostDetailViewController(
            presenter: SpyPostDetailPresenter(),
            accountRefresher: StubPostDetailAccountRefresher(isLoggedIn: true)
        )

        viewController.loadViewIfNeeded()

        let verticalPaddingConstraints = viewController.replyContextBar.constraints.filter { constraint in
            let firstMatches = constraint.firstItem === viewController.replyContextScrollView
            let secondMatches = constraint.secondItem === viewController.replyContextBar
            return firstMatches
                && secondMatches
                && (constraint.firstAttribute == .top || constraint.firstAttribute == .bottom)
        }

        #expect(viewController.replyContextBarHeightConstraint?.constant == 0)
        #expect(verticalPaddingConstraints.count == 2)
        #expect(verticalPaddingConstraints.allSatisfy { $0.priority < .required })
    }

    @Test func replyActionAppendsMultipleTargetsWhileEditorIsOpen() async throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(
            presenter: presenter,
            accountRefresher: StubPostDetailAccountRefresher(isLoggedIn: true)
        )
        let first = Comment(
            id: "1",
            anchorID: "10",
            authorName: "netcup",
            avatarURL: nil,
            floorText: "#10",
            createdAtText: "1min ago",
            contentHTML: "<p>第一段</p>"
        )
        let second = Comment(
            id: "2",
            anchorID: "11",
            authorName: "alice",
            avatarURL: nil,
            floorText: "#11",
            createdAtText: "2min ago",
            contentHTML: "<p>第二段</p>"
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

        viewController.handleReply(to: first)
        await Task.yield()
        viewController.handleReply(to: second)
        await Task.yield()

        let contextLabel = try #require(viewController.view.firstLabel(accessibilityIdentifier: "post-detail-reply-context-label"))
        #expect(contextLabel.text == "回复 netcup #10")
        let secondContextLabel = try #require(
            viewController.view.firstLabel(accessibilityIdentifier: "post-detail-reply-context-label-1")
        )
        #expect(secondContextLabel.text == "回复 alice #11")
        #expect(viewController.replyContextStackView.arrangedSubviews.count == 2)
        let removeButtons = viewController.view.allSubviews(of: UIButton.self).filter {
            $0.accessibilityIdentifier?.hasPrefix("post-detail-reply-context-remove-button-") == true
        }
        #expect(removeButtons.count == 2)
        #expect((viewController.replyContextBarHeightConstraint?.constant ?? 0) > 32)

        removeButtons[1].sendActions(for: .touchUpInside)
        await Task.yield()

        #expect(viewController.replyContextStackView.arrangedSubviews.count == 1)

        let replyTextView = try #require(viewController.view.firstTextView(accessibilityIdentifier: "post-detail-reply-text-view"))
        replyTextView.text = "正文"
        let sendButton = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-detail-reply-send-button"))
        sendButton.sendActions(for: .touchUpInside)
        await Task.yield()

        #expect(presenter.sentReplyContent == """
        @netcup [#10](https://www.nodeseek.com/post-703863-1#10) 正文
        """)
    }

    @Test func quoteActionAppendsMultipleTargetsWhileEditorIsOpen() async throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(
            presenter: presenter,
            accountRefresher: StubPostDetailAccountRefresher(isLoggedIn: true)
        )
        let first = Comment(
            id: "1",
            anchorID: "10",
            authorName: "netcup",
            avatarURL: nil,
            floorText: "#10",
            createdAtText: "1min ago",
            createdAtTitleText: "2026-04-29 13:58:43",
            contentHTML: "<p>第一段</p>"
        )
        let second = Comment(
            id: "2",
            anchorID: "11",
            authorName: "alice",
            avatarURL: nil,
            floorText: "#11",
            createdAtText: "2min ago",
            createdAtTitleText: "2026-04-29 14:00:00",
            contentHTML: "<p>第二段</p>"
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

        viewController.handleQuote(first)
        await Task.yield()
        viewController.handleQuote(second)
        await Task.yield()

        let contextLabel = try #require(viewController.view.firstLabel(accessibilityIdentifier: "post-detail-reply-context-label"))
        #expect(contextLabel.text == "引用 netcup #10")
        let secondContextLabel = try #require(
            viewController.view.firstLabel(accessibilityIdentifier: "post-detail-reply-context-label-1")
        )
        #expect(secondContextLabel.text == "引用 alice #11")
        #expect(viewController.replyContextStackView.arrangedSubviews.count == 2)
        let removeButtons = viewController.view.allSubviews(of: UIButton.self).filter {
            $0.accessibilityIdentifier?.hasPrefix("post-detail-reply-context-remove-button-") == true
        }
        #expect(removeButtons.count == 2)
        #expect((viewController.replyContextBarHeightConstraint?.constant ?? 0) > 32)

        removeButtons[1].sendActions(for: .touchUpInside)
        await Task.yield()

        #expect(viewController.replyContextStackView.arrangedSubviews.count == 1)

        let replyTextView = try #require(viewController.view.firstTextView(accessibilityIdentifier: "post-detail-reply-text-view"))
        replyTextView.text = "正文"
        let sendButton = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-detail-reply-send-button"))
        sendButton.sendActions(for: .touchUpInside)
        await Task.yield()

        #expect(presenter.sentReplyContent == """
        > @netcup [#10](https://www.nodeseek.com/post-703863-1#10) 发布于2026-04-29 13:58:43
        > 第一段

        正文
        """)
    }

    @Test func replyAndQuoteContextsCanCoexist() async throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(
            presenter: presenter,
            accountRefresher: StubPostDetailAccountRefresher(isLoggedIn: true)
        )
        let reply = Comment(
            id: "1",
            anchorID: "10",
            authorName: "netcup",
            avatarURL: nil,
            floorText: "#10",
            createdAtText: "1min ago",
            contentHTML: "<p>第一段</p>"
        )
        let quote = Comment(
            id: "2",
            anchorID: "11",
            authorName: "alice",
            avatarURL: nil,
            floorText: "#11",
            createdAtText: "2min ago",
            createdAtTitleText: "2026-04-29 14:00:00",
            contentHTML: "<p>引用段落</p>"
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

        viewController.handleReply(to: reply)
        await Task.yield()
        viewController.handleQuote(quote)
        await Task.yield()

        #expect(viewController.replyContextStackView.arrangedSubviews.count == 2)
        #expect(viewController.view.firstLabel(accessibilityIdentifier: "post-detail-reply-context-label")?.text == "回复 netcup #10")
        #expect(viewController.view.firstLabel(accessibilityIdentifier: "post-detail-reply-context-label-1")?.text == "引用 alice #11")

        let replyTextView = try #require(viewController.view.firstTextView(accessibilityIdentifier: "post-detail-reply-text-view"))
        replyTextView.text = "正文"
        let sendButton = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-detail-reply-send-button"))
        sendButton.sendActions(for: .touchUpInside)
        await Task.yield()

        #expect(presenter.sentReplyContent == """
        > @alice [#11](https://www.nodeseek.com/post-703863-1#11) 发布于2026-04-29 14:00:00
        > 引用段落

        @netcup [#10](https://www.nodeseek.com/post-703863-1#10) 正文
        """)
    }

    @Test func contextBarScrollsWhenTargetsOverflowVisibleRows() async throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(
            presenter: presenter,
            accountRefresher: StubPostDetailAccountRefresher(isLoggedIn: true)
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

        for index in 1...4 {
            viewController.handleQuote(Comment(
                id: "\(index)",
                anchorID: "\(index)",
                authorName: "user\(index)",
                avatarURL: nil,
                floorText: "#\(index)",
                createdAtText: "\(index)min ago",
                contentHTML: "<p>第 \(index) 段</p>"
            ))
            await Task.yield()
        }

        #expect(viewController.replyContextStackView.arrangedSubviews.count == 4)
        #expect(viewController.replyContextScrollView.isScrollEnabled)
        #expect(viewController.replyContextBarHeightConstraint?.constant == viewController.replyContextBarMaximumHeight)
    }

    @Test func commentButtonKeepsExistingReplyContext() async throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(
            presenter: presenter,
            accountRefresher: StubPostDetailAccountRefresher(isLoggedIn: true)
        )
        let quote = Comment(
            id: "1",
            anchorID: "10",
            authorName: "netcup",
            avatarURL: nil,
            floorText: "#10",
            createdAtText: "1min ago",
            createdAtTitleText: "2026-04-29 13:58:43",
            contentHTML: "<p>引用段落</p>"
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

        viewController.handleQuote(quote)
        await Task.yield()
        viewController.dismissReplyEditor()
        viewController.replyButtonTapped()
        await Task.yield()

        #expect(viewController.replyContextStackView.arrangedSubviews.count == 1)
        #expect(viewController.view.firstLabel(accessibilityIdentifier: "post-detail-reply-context-label")?.text == "引用 netcup #10")
    }

    @Test func postHeaderReplyActionUsesPosterContext() async throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(
            presenter: presenter,
            accountRefresher: StubPostDetailAccountRefresher(isLoggedIn: true)
        )
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
        await Task.yield()

        let contextLabel = try #require(viewController.view.firstLabel(accessibilityIdentifier: "post-detail-reply-context-label"))
        #expect(contextLabel.text == "回复 楼主 #0")

        let replyTextView = try #require(viewController.view.firstTextView(accessibilityIdentifier: "post-detail-reply-text-view"))
        replyTextView.text = "收到"
        let sendButton = try #require(viewController.view.firstButton(accessibilityIdentifier: "post-detail-reply-send-button"))
        sendButton.sendActions(for: .touchUpInside)
        await Task.yield()
        #expect(presenter.sentReplyContent?.contains("@楼主 [#0]") == true)
        #expect(presenter.sentReplyContent?.contains("#0") == true)
        #expect(presenter.sentReplyContent?.contains("收到") == true)
    }

    @Test func inlineReplyEditorPlacesActionsInToolbarAboveTextInput() throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.showsReplyEntry = true
        viewController.displayMode = .content

        viewController.presentReplyEditor(mode: .plain)
        viewController.replyEditorContainer.frame = CGRect(x: 12, y: 600, width: 366, height: 180)
        viewController.replyEditorContainer.layoutIfNeeded()

        let sendButton = try #require(
            viewController.view.firstButton(accessibilityIdentifier: "post-detail-reply-send-button")
        )
        let stickerButton = try #require(
            viewController.view.firstButton(accessibilityIdentifier: "post-detail-reply-sticker-button")
        )
        let uploadButton = try #require(
            viewController.view.firstButton(accessibilityIdentifier: "post-detail-reply-image-upload-button")
        )
        let replyTextView = try #require(
            viewController.view.firstTextView(accessibilityIdentifier: "post-detail-reply-text-view")
        )

        #expect(uploadButton.frame.maxY <= replyTextView.frame.minY)
        #expect(stickerButton.frame.maxY <= replyTextView.frame.minY)
        #expect(sendButton.frame.maxY <= replyTextView.frame.minY)
        #expect(abs(uploadButton.frame.midY - stickerButton.frame.midY) < 1)
        #expect(abs(stickerButton.frame.midY - sendButton.frame.midY) < 1)
    }

    @Test func inlineReplyEditorShowsOnlyTextSendButtonWithoutPreview() throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.showsReplyEntry = true
        viewController.displayMode = .content

        viewController.presentReplyEditor(mode: .plain)
        viewController.replyEditorContainer.frame = CGRect(x: 12, y: 600, width: 366, height: 180)
        viewController.replyEditorContainer.layoutIfNeeded()

        let sendButton = try #require(
            viewController.view.firstButton(accessibilityIdentifier: "post-detail-reply-send-button")
        )
        let replyTextView = try #require(
            viewController.view.firstTextView(accessibilityIdentifier: "post-detail-reply-text-view")
        )

        #expect(sendButton.frame.maxY <= replyTextView.frame.minY)
        #expect(sendButton.configuration?.title == "发送")
        #expect(sendButton.configuration?.image == nil)
        #expect(sendButton.titleLabel?.font.pointSize == 13)
        #expect(sendButton.configuration?.background.backgroundColor == .label)
        #expect(viewController.view.firstButton(accessibilityIdentifier: "post-detail-reply-preview-button") == nil)
    }

    @Test func inlineReplySendButtonKeepsHighContrastLoadingAppearance() throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)
        viewController.loadViewIfNeeded()

        let sendButton = try #require(
            viewController.view.firstButton(accessibilityIdentifier: "post-detail-reply-send-button")
        )

        viewController.setReplySubmitting(true)

        #expect(sendButton.isEnabled)
        #expect(sendButton.isUserInteractionEnabled == false)
        #expect(sendButton.configuration?.showsActivityIndicator == true)
        #expect(sendButton.configuration?.title == nil)
        #expect(sendButton.configuration?.baseForegroundColor == .systemBackground)
        #expect(sendButton.configuration?.background.backgroundColor == .label)

        viewController.setReplySubmitting(false)

        #expect(sendButton.isEnabled)
        #expect(sendButton.isUserInteractionEnabled)
        #expect(sendButton.configuration?.showsActivityIndicator == false)
        #expect(sendButton.configuration?.title == "发送")
    }

    @Test func insertingStickerTokenUpdatesReplyTextAtSelection() throws {
        let presenter = SpyPostDetailPresenter()
        let viewController = PostDetailViewController(presenter: presenter)
        viewController.loadViewIfNeeded()
        viewController.replyTextView.text = "hello world"
        viewController.replyTextView.selectedRange = NSRange(location: 6, length: 5)

        viewController.insertStickerToken("xhj022")

        #expect(viewController.replyTextView.text == "hello :xhj022: ")
        #expect(viewController.replyTextView.selectedRange.location == 15)
    }

    @Test func nodeImageUploadParserUsesReturnedMarkdownWhenAvailable() throws {
        let data = try #require("""
        {
          "success": true,
          "data": {
            "url": "https://cdn.nodeimage.com/demo.jpg",
            "markdown": "![demo](https://cdn.nodeimage.com/demo.jpg)"
          }
        }
        """.data(using: .utf8))

        let result = try #require(NodeImageUploadResponseParser.uploadResult(from: data))

        #expect(result.imageURL.absoluteString == "https://cdn.nodeimage.com/demo.jpg")
        #expect(result.markdownText == "![demo](https://cdn.nodeimage.com/demo.jpg)")
    }

    @Test func nodeImageUploadParserBuildsMarkdownFromNestedURL() throws {
        let data = try #require("""
        {
          "image": {
            "links": {
              "direct": "https://cdn.nodeimage.com/demo.webp"
            }
          }
        }
        """.data(using: .utf8))

        let result = try #require(NodeImageUploadResponseParser.uploadResult(from: data))

        #expect(result.markdownText == "![](https://cdn.nodeimage.com/demo.webp)")
    }

    @Test func nodeImageAPIKeyNormalizerAcceptsPastedHeaderLine() {
        #expect(NodeImageAPIKeyNormalizer.normalized("X-API-Key: nodeimage-demo-key") == "nodeimage-demo-key")
        #expect(NodeImageAPIKeyNormalizer.normalized("Bearer nodeimage-demo-key") == "nodeimage-demo-key")
        #expect(NodeImageAPIKeyNormalizer.normalized("  nodeimage-demo-key  ") == "nodeimage-demo-key")
    }

    @Test func nodeImageAuthorizationMessageExtractsAPIKeyFromNestedPayload() {
        let body: [String: Any] = [
            "type": "auth-success",
            "data": [
                "api_key": " X-API-Key: nodeimage-message-key "
            ]
        ]

        #expect(NodeImageAuthorizationMessage.apiKey(from: body) == "nodeimage-message-key")
    }

    @Test func nodeImageAuthorizationMessageExtractsAPIKeyFromUserStatusResponse() {
        let body: [String: Any] = [
            "success": true,
            "user": [
                "api_key": "Bearer nodeimage-status-key"
            ]
        ]

        #expect(NodeImageAuthorizationMessage.apiKey(from: body) == "nodeimage-status-key")
    }

    @Test func nodeImageAuthorizationWebViewDisablesScrollBounce() throws {
        let viewController = NodeImageAuthViewController { _ in }

        viewController.loadViewIfNeeded()

        let webView = try #require(viewController.view.firstSubview(of: WKWebView.self))
        #expect(webView.scrollView.bounces == false)
        #expect(webView.scrollView.alwaysBounceVertical == false)
        #expect(webView.scrollView.alwaysBounceHorizontal == false)
    }

    @Test func nodeImageUploadCompressorKeepsLargeImagesUnderOneMegabyte() throws {
        let sourceData = try Self.makeNoisyJPEGData(width: 1400, height: 1400, quality: 0.98)
        #expect(sourceData.count > NodeImageUploadImageCompressor.maxUploadByteCount)

        let payload = NodeImageUploadImageCompressor.compressedPayload(
            data: sourceData,
            fileName: "large-source.png",
            mimeType: "image/png"
        )

        #expect(payload.data.count <= NodeImageUploadImageCompressor.maxUploadByteCount)
        #expect(payload.mimeType == "image/jpeg")
        #expect(payload.fileName == "large-source.jpg")
    }

    @Test func nodeImageUploadSourceOptionsIncludeCameraOnlyWhenAvailable() {
        #expect(ReplyImageSourceOption.available(isCameraAvailable: true) == [.camera, .photoLibrary])
        #expect(ReplyImageSourceOption.available(isCameraAvailable: false) == [.photoLibrary])
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

    private static func makeNoisyJPEGData(width: Int, height: Int, quality: CGFloat) throws -> Data {
        var seed: UInt64 = 0x1234_5678_9abc_def0
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for index in stride(from: 0, to: bytes.count, by: 4) {
            seed = seed &* 6364136223846793005 &+ 1
            bytes[index] = UInt8((seed >> 16) & 0xff)
            bytes[index + 1] = UInt8((seed >> 24) & 0xff)
            bytes[index + 2] = UInt8((seed >> 32) & 0xff)
            bytes[index + 3] = 255
        }
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        let image = try #require(CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
        return try #require(UIImage(cgImage: image).jpegData(compressionQuality: quality))
    }

}

private final class InMemoryFloatingControlPositionStore: FloatingControlPositionStoring {
    private var positions: [String: FloatingControlPosition] = [:]

    func position(forKey key: String) -> FloatingControlPosition? {
        positions[key]
    }

    func save(_ position: FloatingControlPosition, forKey key: String) {
        positions[key] = position
    }
}

private final class SpyPostDetailPresenter: PostDetailPresenterProtocol {
    private(set) var loadCount = 0
    private(set) var didTapLoginCount = 0
    private(set) var didApproachCommentEndCount = 0
    private(set) var didTapRefreshCommentsAtEndCount = 0
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

    func refreshInitialPage() {
        loadCount += 1
    }

    func didTapLogin() {
        didTapLoginCount += 1
    }

    func didApproachCommentEnd() {
        didApproachCommentEndCount += 1
    }

    func didTapRefreshCommentsAtEnd() {
        didTapRefreshCommentsAtEndCount += 1
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

    func testPresentedLoadedCommentID() -> String? {
        Mirror(reflecting: self).children.first { $0.label == "testPresentedLoadedCommentID" }?.value as? String
    }

    func testHighlightedAnchorID() -> String? {
        Mirror(reflecting: self).children.first { $0.label == "testHighlightedAnchorID" }?.value as? String
    }

    func testPresentedPreviewUsesCommentCellRendering() -> Bool {
        Mirror(reflecting: self).children.first { $0.label == "testPresentedPreviewUsesCommentCellRendering" }?.value as? Bool ?? false
    }

    func testPresentedPreviewPreferredHeight() -> CGFloat? {
        Mirror(reflecting: self).children.first { $0.label == "testPresentedPreviewPreferredHeight" }?.value as? CGFloat
    }

    func testPresentedPreviewKeepsCloseButtonOutsideContent() -> Bool {
        Mirror(reflecting: self).children.first { $0.label == "testPresentedPreviewKeepsCloseButtonOutsideContent" }?.value as? Bool ?? false
    }

    func testPresentedPreviewUsesBottomSheet() -> Bool {
        Mirror(reflecting: self).children.first { $0.label == "testPresentedPreviewUsesBottomSheet" }?.value as? Bool ?? false
    }

    func testPresentedPreviewShowsFullPostButton() -> Bool {
        Mirror(reflecting: self).children.first { $0.label == "testPresentedPreviewShowsFullPostButton" }?.value as? Bool ?? false
    }

    func testOpenedFullPostPage() -> Int? {
        Mirror(reflecting: self).children.first { $0.label == "testOpenedFullPostPage" }?.value as? Int
    }

    func testOpenedFullPostAnchorWasNil() -> Bool {
        Mirror(reflecting: self).children.first { $0.label == "testOpenedFullPostAnchorWasNil" }?.value as? Bool ?? false
    }

    func testDetailRowKinds() -> [String] {
        detailRows.map { row in
            let text = String(describing: row)
            if text.hasPrefix("header") { return "header" }
            if text.hasPrefix("postRepliesDivider") { return "postRepliesDivider" }
            if text.hasPrefix("entryHint") { return "entryHint" }
            if text.hasPrefix("comment") { return "comment" }
            if text.hasPrefix("skeletonComment") { return "skeletonComment" }
            return text
        }
    }
}

private struct StubPostDetailAccountRefresher: CurrentAccountRefreshing {
    let isLoggedIn: Bool

    func cachedAccount() async -> AccountResponse? {
        account
    }

    func refreshIfNeeded(force: Bool, maxAge: TimeInterval) async -> AccountResponse? {
        account
    }

    private var account: AccountResponse {
        AccountResponse(
            displayName: isLoggedIn ? "mist" : "",
            isLoggedIn: isLoggedIn,
            avatarURL: nil,
            profileURL: nil,
            stats: []
        )
    }
}

private struct DelayedPostDetailAccountRefresher: CurrentAccountRefreshing {
    let isLoggedIn: Bool

    func cachedAccount() async -> AccountResponse? {
        account
    }

    func refreshIfNeeded(force: Bool, maxAge: TimeInterval) async -> AccountResponse? {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        return account
    }

    private var account: AccountResponse {
        return AccountResponse(
            displayName: isLoggedIn ? "mist" : "",
            isLoggedIn: isLoggedIn,
            avatarURL: nil,
            profileURL: nil,
            stats: []
        )
    }
}

private extension ASLayout {
    func firstLayoutElement(identicalTo target: ASLayoutElement) -> ASLayout? {
        if (layoutElement as AnyObject) === (target as AnyObject) {
            return self
        }
        for sublayout in sublayouts {
            if let match = sublayout.firstLayoutElement(identicalTo: target) {
                return match
            }
        }
        return nil
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

@MainActor
private func tearDownPostDetailTextureViewController(
    _ viewController: PostDetailViewController,
    window: UIWindow? = nil
) async {
    viewController.dismiss(animated: false)
    viewController.presentedViewController?.dismiss(animated: false)
    viewController.tableNode.view.removeFromSuperview()
    window?.rootViewController = nil
    window?.isHidden = true
    await Task.yield()
}
