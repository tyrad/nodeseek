//
//  PostDetailUXAuditTests.swift
//  nodeseekTests
//
//  UX 走查（2026-11-18）详情页展示与操作区问题的 RED 测试。
//  每个测试描述修复后应成立的行为，当前代码下应因断言失败。
//

import AsyncDisplayKit
import JXPhotoBrowser
import UIKit
import XCTest
@testable import nodeseek

@MainActor
final class PostDetailUXAuditTests: XCTestCase {
    private var windows: [UIWindow] = []

    override func tearDown() async throws {
        for window in windows {
            window.rootViewController?.dismiss(animated: false)
            window.rootViewController = nil
            window.isHidden = true
        }
        windows.removeAll()
        try await super.tearDown()
    }

    // MARK: - U01

    // 预期：评论正文最后一行的链接中心点被点中时，命中正文链接，而不是下方签名链接扩大后的点击区。
    func test_U01_bodyLastLineLinkCenterTapResolvesToBodyURL() throws {
        let bodyURLString = "https://www.nodeseek.com/post-1016685-1#0"
        let signatureURLString = "https://www.nodeseek.com/post-717963-1"
        let rendered = try XCTUnwrap(PostDetailViewController.makeRenderedContent(
            html: "<p><a href=\"/space/1\">@缭雾</a> <a href=\"\(bodyURLString)\">#0</a> reply op test</p>",
            signatureHTML: "<p><a href=\"\(signatureURLString)\">超好用的Nodeseek开源客户端</a></p>",
            baseURL: NodeSeekSite.baseURL,
            maxImageWidth: 308,
            showsSignature: true
        ))
        let attributedText = try XCTUnwrap(rendered.compactMap { block -> NSAttributedString? in
            if case .text(let text) = block { return text }
            return nil
        }.first)
        let bodyLinkRange = (attributedText.string as NSString).range(of: "#0")
        let signatureLinkRange = (attributedText.string as NSString).range(of: "超好用的Nodeseek开源客户端")
        XCTAssertNotEqual(bodyLinkRange.location, NSNotFound)
        XCTAssertNotEqual(signatureLinkRange.location, NSNotFound)

        let richTextView = DetailRichTextView(frame: CGRect(x: 0, y: 0, width: 308, height: 400))
        richTextView.configure(attributedText, onImageTapped: nil, onLinkTapped: nil, onLayoutInvalidated: nil)
        richTextView.setNeedsLayout()
        richTextView.layoutIfNeeded()

        let linkButtons = richTextView.subviews.compactMap { $0 as? UIButton }
        let bodyButton = try XCTUnwrap(
            linkButtons.first { NSLocationInRange($0.tag, bodyLinkRange) },
            "没有找到正文 #0 链接的点击视图，subviews=\(richTextView.subviews)"
        )
        XCTAssertNotNil(linkButtons.first { NSLocationInRange($0.tag, signatureLinkRange) }, "没有找到签名链接的点击视图")

        let bodyCenter = CGPoint(x: bodyButton.frame.midX, y: bodyButton.frame.midY)
        let hitView = richTextView.hitTest(bodyCenter, with: nil)
        let hitTag = hitView?.tag ?? -1
        XCTAssertTrue(
            hitView === bodyButton,
            "点正文链接 #0 中心 \(bodyCenter) 命中的是 tag=\(hitTag)（签名链接起点=\(signatureLinkRange.location)）的视图，签名链接扩大后的点击区抢走了正文最后一行链接"
        )
    }

    // 预期：点正文最后一行的普通文字不会落到签名链接；签名链接下方的扩大点击区仍然有效。
    func test_U01_signatureHitAreaDoesNotCoverBodyLastLinePlainText() throws {
        let signatureURLString = "https://www.nodeseek.com/post-717963-1"
        let rendered = try XCTUnwrap(PostDetailViewController.makeRenderedContent(
            html: "<p><a href=\"https://www.nodeseek.com/post-1016685-1#0\">#0</a> reply op test</p>",
            signatureHTML: "<p><a href=\"\(signatureURLString)\">超好用的Nodeseek开源客户端</a></p>",
            baseURL: NodeSeekSite.baseURL,
            maxImageWidth: 308,
            showsSignature: true
        ))
        let attributedText = try XCTUnwrap(rendered.compactMap { block -> NSAttributedString? in
            if case .text(let text) = block { return text }
            return nil
        }.first)
        let bodyLinkRange = (attributedText.string as NSString).range(of: "#0")
        let signatureLinkRange = (attributedText.string as NSString).range(of: "超好用的Nodeseek开源客户端")

        let richTextView = DetailRichTextView(frame: CGRect(x: 0, y: 0, width: 308, height: 400))
        richTextView.configure(attributedText, onImageTapped: nil, onLinkTapped: nil, onLayoutInvalidated: nil)
        richTextView.setNeedsLayout()
        richTextView.layoutIfNeeded()

        let linkButtons = richTextView.subviews.compactMap { $0 as? UIButton }
        let bodyButton = try XCTUnwrap(linkButtons.first { NSLocationInRange($0.tag, bodyLinkRange) })
        let signatureButton = try XCTUnwrap(linkButtons.first { NSLocationInRange($0.tag, signatureLinkRange) })

        // 「reply op test」所在位置：正文链接右侧同一行，横向仍落在签名链接范围内。
        let plainTextPoint = CGPoint(x: bodyButton.frame.maxX + 30, y: bodyButton.frame.midY)
        XCTAssertLessThan(plainTextPoint.x, signatureButton.frame.maxX, "前置条件：该点横向应位于签名链接范围内")
        let plainTextHit = richTextView.hitTest(plainTextPoint, with: nil)
        XCTAssertFalse(
            plainTextHit === signatureButton,
            "点正文最后一行普通文字 \(plainTextPoint) 命中了签名链接，签名扩大点击区越过了正文"
        )

        let belowSignaturePoint = CGPoint(x: signatureButton.frame.midX, y: signatureButton.frame.maxY + 8)
        XCTAssertTrue(
            richTextView.hitTest(belowSignaturePoint, with: nil) === signatureButton,
            "签名链接下方 \(belowSignaturePoint) 的扩大点击区应仍然有效"
        )
    }

    // MARK: - U04

    // 预期：浮动「评论」按钮默认位置与评论行尾部操作按钮（回复 / 引用 / 编辑）所在列不重叠。
    func test_U04_floatingReplyButtonDoesNotCoverCommentActionColumn() async throws {
        let viewController = PostDetailViewController(
            presenter: UXAuditSpyPostDetailPresenter(),
            floatingPositionStore: UXAuditInMemoryFloatingPositionStore()
        )
        let window = makeWindow(rootViewController: viewController)
        viewController.render(detail: PostDetail(
            id: "1017330",
            title: "测试",
            authorName: "mist",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>正文</p>",
            comments: (1...3).map { index in
                Comment(
                    id: "\(index)",
                    authorName: "mist",
                    avatarURL: nil,
                    floorText: "#\(index)",
                    createdAtText: "刚刚",
                    contentHTML: "<p>评论 \(index)</p>",
                    isOwnComment: true
                )
            }
        ))
        await waitForDetailContent(in: viewController)

        let actionLabels: Set<String> = ["回复评论", "引用评论", "编辑评论"]
        var actionViews: [UIView] = []
        let didFindActions = await waitUntil(timeout: 3) {
            window.layoutIfNeeded()
            actionViews = viewController.view.uxAuditAllSubviews().filter { view in
                guard let label = view.accessibilityLabel else { return false }
                return actionLabels.contains(label) && view.window != nil && view.bounds.width > 0
            }
            return actionViews.isEmpty == false
        }
        XCTAssertTrue(didFindActions, "评论行没有渲染出回复 / 引用 / 编辑按钮")

        let floatingContainer = try XCTUnwrap(
            viewController.view.uxAuditAllSubviews().first {
                $0.accessibilityIdentifier == "post-detail-floating-reply-button"
            }
        )
        let floatingFrame = floatingContainer.convert(floatingContainer.bounds, to: viewController.view)
        let overlapping = actionViews.filter { view in
            let frame = view.convert(view.bounds, to: viewController.view)
            return frame.minX < floatingFrame.maxX && frame.maxX > floatingFrame.minX
        }
        let descriptions = overlapping.map { view -> String in
            let frame = view.convert(view.bounds, to: viewController.view)
            return "\(view.accessibilityLabel ?? "?")@x=\(Int(frame.minX))..\(Int(frame.maxX))"
        }
        XCTAssertTrue(
            overlapping.isEmpty,
            "浮动评论按钮 x=\(Int(floatingFrame.minX))..\(Int(floatingFrame.maxX)) 与评论操作按钮列重叠：\(Set(descriptions).sorted())，滚动时会盖住编辑 / 引用按钮"
        )
        withExtendedLifetime(window) {}
    }

    // MARK: - U08

    // 预期：评论模型保存绝对发布时间（Date），界面可以按当前时间重新计算相对时间。
    func test_U08_commentCarriesAbsoluteCreatedDate() {
        let comment = Comment(
            id: "1",
            authorName: "mist",
            avatarURL: nil,
            floorText: "#4",
            createdAtText: "1s ago",
            createdAtTitleText: "2026-11-18 10:00:00",
            contentHTML: "<p>评论</p>"
        )
        let properties = Mirror(reflecting: comment).children.map { child in
            "\(child.label ?? "?"): \(type(of: child.value))"
        }
        let hasDateProperty = Mirror(reflecting: comment).children.contains { child in
            child.value is Date || type(of: child.value) == Optional<Date>.self
        }
        XCTAssertTrue(
            hasDateProperty,
            "Comment 只保存了相对时间文本，没有 Date 类型的发布时间，'1s ago' 永远不会刷新。现有字段：\(properties.filter { $0.contains("createdAt") })"
        )
    }

    // MARK: - U09

    // 预期：大图预览是黑底，浅色模式下状态栏也要用浅色文字。
    func test_U09_photoBrowserUsesLightStatusBarInLightMode() {
        let browser = DetailPhotoBrowserController()
        browser.overrideUserInterfaceStyle = .light
        browser.loadViewIfNeeded()

        XCTAssertEqual(
            browser.preferredStatusBarStyle,
            .lightContent,
            "大图预览 preferredStatusBarStyle=\(browser.preferredStatusBarStyle.rawValue)，浅色模式下黑底上的状态栏文字是深色的，看不见"
        )
    }

    // MARK: - U18

    // 预期：「更多评论加载失败」这类错误提示不能走带绿色成功勾的 showToast。
    func test_U18_loadMoreFailureDoesNotUseSuccessToast() {
        let interactor = UXAuditSpyPostDetailInteractor()
        let view = UXAuditSpyPostDetailView()
        let presenter = PostDetailPresenter(interactor: interactor, router: UXAuditSpyPostDetailRouter(), initialPage: 1)
        presenter.setView(view)
        presenter.didLoadPostDetail(PostDetailResponse(detail: PostDetail(
            id: "706958",
            title: "标题",
            authorName: "mist",
            avatarURL: nil,
            metadataText: nil,
            contentHTML: "<p>正文</p>",
            comments: [
                Comment(id: "1", authorName: "a", avatarURL: nil, floorText: "#1", createdAtText: nil, contentHTML: "<p>第一页</p>")
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
        )))

        presenter.didApproachCommentEnd()
        XCTAssertEqual(interactor.loadedPages, [2])
        presenter.didFailLoadPostDetail(error: "网络错误")

        XCTAssertFalse(
            view.successToastMessages.contains("更多评论加载失败"),
            "加载更多失败走了 showToast（带绿色成功勾）：successToasts=\(view.successToastMessages)"
        )
    }

    // MARK: - U19

    // 预期：自己的评论和自己的帖子不显示（或禁用）点赞 / 鸡腿 / 反对按钮，避免点了才报“不能给自己点赞”。
    func test_U19_ownContentHidesSelfVoteButtons() {
        let ownComment = Comment(
            id: "1",
            authorName: "mist",
            avatarURL: nil,
            floorText: "#2",
            createdAtText: "刚刚",
            contentHTML: "<p>我的评论</p>",
            likeCount: 0,
            chickenLegCount: 0,
            opposeCount: 0,
            isOwnComment: true
        )
        let commentNode = CommentCellNode(
            comment: ownComment,
            renderedBody: [],
            onImageTapped: { _, _ in },
            onEditTapped: { _ in },
            onTextLayoutInvalidated: {}
        )
        let commentLayout = commentNode.layoutThatFits(ASSizeRange(
            min: .zero,
            max: CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude)
        ))
        let usableCommentVotes: [String] = ["likeButtonNode", "chickenLegButtonNode", "opposeButtonNode"].filter { name in
            isUsableButton(named: name, in: commentNode, layout: commentLayout)
        }

        let ownHeader = PostDetailHeaderContent(
            postID: "1017330",
            title: "测试",
            authorName: "mist",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>正文</p>",
            likeCount: 0,
            chickenLegCount: 0,
            opposeCount: 0,
            favoriteCount: 0,
            isOwnPost: true
        )
        let postNode = PostBodyCellNode(
            content: ownHeader,
            renderedContent: [],
            onImageTapped: { _, _ in },
            onEditTapped: {},
            onTextLayoutInvalidated: {}
        )
        let postLayout = postNode.layoutThatFits(ASSizeRange(
            min: .zero,
            max: CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude)
        ))
        let usablePostVotes: [String] = ["likeButtonNode", "chickenLegButtonNode", "opposeButtonNode"].filter { name in
            isUsableButton(named: name, in: postNode, layout: postLayout)
        }

        XCTAssertEqual(usableCommentVotes, [], "自己的评论仍显示可点的投票按钮：\(usableCommentVotes)")
        XCTAssertEqual(usablePostVotes, [], "自己的帖子仍显示可点的投票按钮：\(usablePostVotes)")
    }

    // MARK: - U25

    // 预期：跳到第 2 页后，「在浏览器打开」打开当前查看的第 2 页，而不是进入时的第 1 页。
    func test_U25_openInBrowserUsesCurrentlyViewedPage() async throws {
        let presenter = UXAuditSpyPostDetailPresenter()
        let header = PostDetailHeaderContent(
            postID: "703863",
            title: "详情标题",
            authorName: "ipv4",
            avatarURL: nil,
            metadataText: "刚刚"
        )
        let viewController = PostDetailViewController(presenter: presenter, initialHeader: header, currentPage: 1)
        let navigationController = UINavigationController(rootViewController: viewController)
        viewController.loadViewIfNeeded()
        viewController.render(detail: makePagedDetail(page: 1))
        await waitForDetailContent(in: viewController)

        viewController.jumpToCommentPage(2)
        XCTAssertEqual(presenter.selectedCommentPages, [2])
        viewController.render(detail: makePagedDetail(page: 2))
        await waitForDetailContent(in: viewController)

        viewController.openInBrowserTapped()

        let webViewController = try XCTUnwrap(navigationController.topViewController as? NodeSeekWebViewController)
        XCTAssertEqual(
            webViewController.testInitialURL.absoluteString,
            "https://www.nodeseek.com/post-703863-2",
            "正在看第 2 页，「在浏览器打开」却打开了 \(webViewController.testInitialURL.absoluteString)"
        )
    }

    // MARK: - U26

    // 预期：深色模式下全屏大图不再叠加“图片变暗”遮罩，显示原始亮度。
    func test_U26_photoPreviewIsNotDimmedInDarkMode() throws {
        let settings = DetailImageDimmingSettings.shared
        let wasEnabled = settings.isEnabled
        settings.setEnabled(true)
        defer { settings.setEnabled(wasEnabled) }

        let url = try XCTUnwrap(URL(string: "https://example.invalid/ux-audit-u26.png"))
        let presenter = DetailPhotoBrowserPresenter(imageURLs: [url])
        let browser = DetailPhotoBrowserController()
        let cell = JXZoomImageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        cell.overrideUserInterfaceStyle = .dark

        presenter.photoBrowser(browser, willDisplay: cell, at: 0)

        let darkTrait = UITraitCollection(userInterfaceStyle: .dark)
        let activeOverlays = cell.imageView.subviews.compactMap { $0 as? DetailImageDimmingView }.filter { overlay in
            let alpha = overlay.backgroundColor?.resolvedColor(with: darkTrait).cgColor.alpha ?? 0
            return overlay.isHidden == false && overlay.alpha > 0 && alpha > 0
        }
        let opacities = activeOverlays.map { $0.backgroundColor?.resolvedColor(with: darkTrait).cgColor.alpha ?? 0 }
        XCTAssertTrue(
            activeOverlays.isEmpty,
            "深色模式大图预览仍装有生效的变暗遮罩，遮罩不透明度=\(opacities)"
        )
    }

    // MARK: - U29

    // 预期：有热门评论时，热评区和正常楼层之间有分区标题行（如「热门评论」），不会被看成楼层乱序。
    func test_U29_hotCommentsHaveSectionHeaderRow() async {
        let viewController = PostDetailViewController(presenter: UXAuditSpyPostDetailPresenter())
        viewController.loadViewIfNeeded()
        let hot = [13, 26].map { floor in
            Comment(id: "hot-\(floor)", authorName: "u\(floor)", avatarURL: nil, floorText: "#\(floor)",
                    createdAtText: "刚刚", contentHTML: "<p>热评 \(floor)</p>", isHot: true)
        }
        let normal = (1...3).map { floor in
            Comment(id: "\(floor)", authorName: "u\(floor)", avatarURL: nil, floorText: "#\(floor)",
                    createdAtText: "刚刚", contentHTML: "<p>楼层 \(floor)</p>")
        }
        viewController.render(detail: PostDetail(
            id: "1017330",
            title: "多页帖子",
            authorName: "mist",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>正文</p>",
            comments: hot + normal,
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
        await waitForDetailContent(in: viewController)

        let kinds = viewController.detailRows.map { String(describing: $0) }
        // 热评前和热评/正常楼层之间应各有一个非评论的分区行；当前只有通用的“回复”分隔行。
        let firstHotRow = kinds.firstIndex { $0.hasPrefix("comment") }
        let commentRows = kinds.enumerated().filter { $0.element.hasPrefix("comment") }.map(\.offset)
        let firstNormalRow = commentRows.count > hot.count ? commentRows[hot.count] : nil
        let hasSeparatorBetween: Bool = {
            guard let firstHotRow, let firstNormalRow else { return false }
            return kinds[firstHotRow..<firstNormalRow].contains { $0.hasPrefix("comment") == false }
        }()
        XCTAssertTrue(
            hasSeparatorBetween,
            "热评和正常楼层之间没有分区标题行：detailRows=\(kinds)"
        )
    }

    // MARK: - U30

    // 预期：0 条评论的帖子在正文下方显示空状态（如“暂无评论”），而不是一片空白。
    func test_U30_postWithoutCommentsShowsEmptyStateRow() async {
        let viewController = PostDetailViewController(presenter: UXAuditSpyPostDetailPresenter())
        viewController.loadViewIfNeeded()
        viewController.render(detail: PostDetail(
            id: "1017330",
            title: "没人回复的帖子",
            authorName: "mist",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>正文</p>",
            comments: [],
            page: 1,
            isLastPage: true
        ))
        await waitForDetailContent(in: viewController)

        let kinds = viewController.detailRows.map { String(describing: $0) }
        XCTAssertGreaterThan(
            kinds.count,
            1,
            "0 条评论时正文下方没有任何空状态行：detailRows=\(kinds)"
        )
    }

    // MARK: - U32

    // 预期：自己评论的长按菜单不出现「投放鸡腿」。
    func test_U32_ownCommentContextMenuHasNoChickenLeg() {
        let comment = Comment(
            id: "9835758",
            authorName: "mist",
            avatarURL: nil,
            authorProfileURL: URL(string: "https://www.nodeseek.com/space/31037"),
            floorText: "#2",
            createdAtText: "刚刚",
            contentHTML: "<p>我的评论</p>",
            isOwnComment: true
        )
        let node = CommentCellNode(
            comment: comment,
            renderedBody: [],
            onImageTapped: { _, _ in },
            onEditTapped: { _ in },
            onTextLayoutInvalidated: {}
        )

        XCTAssertFalse(
            node.debugBodyContextMenuActionTitles.contains("投放鸡腿"),
            "自己评论的长按菜单包含「投放鸡腿」：\(node.debugBodyContextMenuActionTitles)"
        )
    }

    // MARK: - U39

    // 预期：收藏数从 0 变 1 时，帖子操作栏其他按钮位置不变（不整体左移）。
    func test_U39_postActionRowStaysStableWhenFavoriteCountAppears() throws {
        let header = PostDetailHeaderContent(
            postID: "1017330",
            title: "测试",
            authorName: "mist",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>正文</p>",
            likeCount: 0,
            chickenLegCount: 0,
            opposeCount: 0,
            favoriteCount: 0,
            isFavoriteCollected: false
        )
        let node = PostBodyCellNode(
            content: header,
            renderedContent: [],
            onImageTapped: { _, _ in },
            onTextLayoutInvalidated: {}
        )
        let names = ["likeButtonNode", "chickenLegButtonNode", "opposeButtonNode", "favoriteButtonNode", "replyButtonNode", "commentButtonNode"]
        func actionXPositions() throws -> [String: CGFloat] {
            let layout = node.layoutThatFits(ASSizeRange(
                min: .zero,
                max: CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude)
            ))
            var result: [String: CGFloat] = [:]
            for name in names {
                let button = try XCTUnwrap(uxAuditStoredNode(named: name, in: node), "找不到 \(name)")
                result[name] = try XCTUnwrap(layout.uxAuditAbsoluteOrigin(of: button), "\(name) 不在布局中").x
            }
            return result
        }

        let before = try actionXPositions()
        // 模拟收藏成功：收藏数 0 → 1，原地更新操作栏。
        node.updateFavoriteReaction(count: 1, isCollected: true)
        let after = try actionXPositions()

        let moved = names.filter { abs((before[$0] ?? 0) - (after[$0] ?? 0)) > 0.5 }.map { name in
            "\(name): \(before[name] ?? -1) → \(after[name] ?? -1)"
        }
        XCTAssertEqual(moved, [], "收藏数 0→1 后帖子操作栏按钮发生位移：\(moved)")
    }

    // MARK: - U40

    // 预期：复制面板的主按钮跟随黑白主题（.label 反色），不用系统蓝。
    func test_U40_copySheetPrimaryButtonIsNotSystemBlue() throws {
        let viewController = CommentCopySheetViewController(text: "回复内容", pasteboardStringWriter: { _ in })
        viewController.overrideUserInterfaceStyle = .light
        viewController.loadViewIfNeeded()

        let copyButton = try XCTUnwrap(
            viewController.view.uxAuditAllSubviews().compactMap { $0 as? UIButton }.first {
                $0.accessibilityIdentifier == "comment-copy-selected-button"
            }
        )
        let lightTrait = UITraitCollection(userInterfaceStyle: .light)
        let background = copyButton.configuration?.baseBackgroundColor ?? copyButton.backgroundColor ?? copyButton.tintColor
        let resolved = try XCTUnwrap(background).resolvedColor(with: lightTrait)
        XCTAssertFalse(
            resolved.uxAuditIsSameColor(as: UIColor.systemBlue.resolvedColor(with: lightTrait)),
            "复制面板「复制」按钮背景是系统蓝 \(resolved)，与黑白主题不一致"
        )
    }

    // MARK: - Helpers

    private func makeWindow(rootViewController: UIViewController) -> UIWindow {
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        } else {
            window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        }
        window.rootViewController = rootViewController
        window.makeKeyAndVisible()
        rootViewController.view.layoutIfNeeded()
        windows.append(window)
        return window
    }

    private func makePagedDetail(page: Int) -> PostDetail {
        PostDetail(
            id: "703863",
            title: "详情标题",
            authorName: "ipv4",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>正文</p>",
            comments: [
                Comment(id: "p\(page)", authorName: "a", avatarURL: nil, floorText: "#\(page * 10)",
                        createdAtText: nil, contentHTML: "<p>第 \(page) 页</p>")
            ],
            page: page,
            pagination: PostDetailPagination(
                currentPage: page,
                items: (1...3).map { PostDetailPageItem(page: $0, url: nil, isCurrent: $0 == page) },
                previousPage: page > 1 ? page - 1 : nil,
                nextPage: page < 3 ? page + 1 : nil
            )
        )
    }

    /// 按钮在布局里、未隐藏、可交互，才算对用户“可用”。
    private func isUsableButton(named name: String, in node: ASDisplayNode, layout: ASLayout) -> Bool {
        guard let button = uxAuditStoredNode(named: name, in: node) as? ASControlNode else { return false }
        guard layout.uxAuditAbsoluteOrigin(of: button) != nil else { return false }
        return button.isHidden == false && button.alpha > 0.01 && button.isEnabled && button.isUserInteractionEnabled
    }

    private func waitForDetailContent(in viewController: PostDetailViewController) async {
        let didReveal = await waitUntil(timeout: 3) { viewController.hasRenderedDetailContent }
        XCTAssertTrue(didReveal, "详情内容没有在超时前渲染完成")
    }

    @discardableResult
    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }
}

// MARK: - Test doubles

private final class UXAuditInMemoryFloatingPositionStore: FloatingControlPositionStoring {
    private var positions: [String: FloatingControlPosition] = [:]

    func position(forKey key: String) -> FloatingControlPosition? {
        positions[key]
    }

    func save(_ position: FloatingControlPosition, forKey key: String) {
        positions[key] = position
    }
}

private final class UXAuditSpyPostDetailPresenter: PostDetailPresenterProtocol {
    private(set) var selectedCommentPages: [Int] = []

    func viewDidLoad() {}
    func refreshInitialPage() {}
    func didSelectCommentPage(_ page: Int) { selectedCommentPages.append(page) }
    func didTapLogin() {}
    func didApproachCommentEnd() {}
    func didTapRefreshCommentsAtEnd() {}
    func didTapSendReply(content: String) {}
    func didTapFavorite() {}
    func didTapPostLike() {}
    func didTapPostChickenLeg() {}
    func didTapPostOppose() {}
    func didTapCommentLike(_ comment: nodeseek.Comment) {}
    func didTapCommentChickenLeg(_ comment: nodeseek.Comment) {}
    func didTapCommentOppose(_ comment: nodeseek.Comment) {}
    func didTapEditPost() {}
    func didTapEditComment(_ comment: nodeseek.Comment) {}
}

private final class UXAuditSpyPostDetailInteractor: PostDetailInteractorInput {
    private(set) var loadedPages: [Int] = []

    func loadPostDetail() { loadPostDetail(page: 1) }
    func loadPostDetail(page: Int) { loadedPages.append(page) }
    func submitReply(content: String) {}
    func addFavorite() {}
    func removeFavorite() {}
    func addPostLike() {}
    func addCommentLike(commentID: String) {}
    func addPostChickenLeg() {}
    func addCommentChickenLeg(commentID: String) {}
    func addPostOppose() {}
    func addCommentOppose(commentID: String) {}
}

private final class UXAuditSpyPostDetailRouter: PostDetailRouterProtocol {
    func navigateToLogin(onClose: @escaping @MainActor () -> Void) {}
    func presentEditPost(_ editable: EditableDiscussion, onSaved: @escaping () -> Void) {}
    func presentEditComment(_ editable: EditableComment, onSaved: @escaping () -> Void) {}
}

private final class UXAuditSpyPostDetailView: PostDetailViewProtocol {
    /// 通过 showToast 显示的提示，带绿色成功勾。
    private(set) var successToastMessages: [String] = []
    private(set) var progressToastMessages: [String] = []
    private(set) var errorMessages: [String] = []

    func showLoading() {}
    func showLoadingMoreComments() {}
    func hideLoadingMoreComments() {}
    func hideLoading() {}
    func showError(message: String) { errorMessages.append(message) }
    func showToast(message: String) { successToastMessages.append(message) }
    func showProgressToast(message: String) { progressToastMessages.append(message) }
    func setReplySubmitting(_ isSubmitting: Bool) {}
    func setFavoriteSubmitting(_ isSubmitting: Bool) {}
    func finishReplySubmission() {}
    func render(detail: PostDetail) {}
    func refreshCurrentCommentPage(detail: PostDetail) {}
    func appendCommentPage(detail: PostDetail) {}
    func updatePostBody(detail: PostDetail) {}
    func updateAuthorRiskWarning(postID: String, isVisible: Bool) {}
    func updateCommentLike(commentID: String, count: Int?, isClicked: Bool) {}
    func updateCommentChickenLeg(commentID: String, count: Int?, isClicked: Bool) {}
    func updateCommentOppose(commentID: String, count: Int?, isClicked: Bool) {}
    func renderLoginRequired(message: String) {}
}

// MARK: - Reflection & hierarchy helpers

/// 通过反射读取节点的私有子节点，避免为测试改动生产代码。
private func uxAuditStoredNode(named name: String, in object: AnyObject) -> ASDisplayNode? {
    var mirror: Mirror? = Mirror(reflecting: object)
    while let current = mirror {
        if let value = current.children.first(where: { $0.label == name })?.value as? ASDisplayNode {
            return value
        }
        mirror = current.superclassMirror
    }
    return nil
}

private extension ASLayout {
    /// 在布局树中查找元素，返回其相对根布局的位置。
    func uxAuditAbsoluteOrigin(of target: ASLayoutElement, offset: CGPoint = .zero) -> CGPoint? {
        // 根布局的 position 是 CGPointNull（NaN），按原点处理。
        let ownPosition = position.x.isFinite && position.y.isFinite ? position : .zero
        let origin = CGPoint(x: offset.x + ownPosition.x, y: offset.y + ownPosition.y)
        if (layoutElement as AnyObject) === (target as AnyObject) {
            return origin
        }
        for sublayout in sublayouts {
            if let match = sublayout.uxAuditAbsoluteOrigin(of: target, offset: origin) {
                return match
            }
        }
        return nil
    }
}

private extension UIView {
    func uxAuditAllSubviews() -> [UIView] {
        subviews + subviews.flatMap { $0.uxAuditAllSubviews() }
    }
}

private extension UIColor {
    func uxAuditIsSameColor(as other: UIColor) -> Bool {
        var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0, la: CGFloat = 0
        var rr: CGFloat = 0, rg: CGFloat = 0, rb: CGFloat = 0, ra: CGFloat = 0
        guard getRed(&lr, green: &lg, blue: &lb, alpha: &la),
              other.getRed(&rr, green: &rg, blue: &rb, alpha: &ra) else {
            return self == other
        }
        return abs(lr - rr) < 0.01 && abs(lg - rg) < 0.01 && abs(lb - rb) < 0.01 && abs(la - ra) < 0.01
    }
}
