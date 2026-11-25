import Foundation
import Testing
import UIKit
@testable import nodeseek

@Suite(.serialized)
@MainActor
struct ThreadedRepliesSheetTests {
    private static let postID = "12000"

    @Test func floorMenuShowsThreadRepliesOnlyOnPositiveCommentFloorsAndNotOnPostHeader() throws {
        let presenter = ThreadMenuSpyPresenter()
        let viewController = PostDetailViewController(
            presenter: presenter,
            initialHeader: nil,
            sourcePostURL: NodeSeekSite.postURL(id: Self.postID, page: 1),
            currentPage: 1
        )
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.layoutIfNeeded()

        let detail = PostDetail(
            id: Self.postID,
            title: "测试贴",
            authorName: "OP",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>主楼</p>",
            visibleMarkdown: "主楼",
            comments: [
                nodeseek.Comment(
                    id: "90003",
                    anchorID: "3",
                    authorName: "Mori",
                    avatarURL: nil,
                    floorText: "#3",
                    createdAtText: "刚刚",
                    contentHTML: "<p>评论正文</p>",
                    markdown: "评论正文",
                    hasVisibleMarkdown: true
                )
            ],
            page: 1,
            totalPages: 1
        )
        viewController.render(detail: detail)
        viewController.collectionList.view.layoutIfNeeded()

        // 找到主楼 cell（第 0 项）与评论 cell
        let headerCell = try #require(
            viewController.collectionList.view.cellForItem(at: IndexPath(item: 0, section: 0)) as? DetailFloorListCell
        )
        let threadTitle = DetailListStrings.text("thread-replies")
        #expect(headerCell.floorActions.map(\.title).contains(threadTitle) == false)
        #expect(headerCell.firstButton(accessibilityIdentifier: "detail-floor-thread-button-0") == nil)

        let commentRow = try #require(
            viewController.collectionList.rows.firstIndex {
                if case .comment = $0 { return true }
                return false
            }
        )
        // 首屏主楼按一屏高度预估，先滚到评论行再读取已出队的 cell。
        viewController.collectionList.scroll(to: commentRow, position: .centeredVertically)
        viewController.collectionList.view.layoutIfNeeded()
        let commentCell = try #require(
            viewController.collectionList.view.cellForItem(at: IndexPath(item: commentRow, section: 0)) as? DetailFloorListCell
        )
        #expect(commentCell.floorActions.map(\.title).contains(threadTitle))

        // 楼号左侧应展示细线分支按钮，且点击按钮（或命合体热区）直接触发吃瓜
        let threadButton = try #require(commentCell.firstButton(accessibilityIdentifier: "detail-floor-thread-button-3"))
        #expect(threadButton.isHidden == false)
        let buttonCenterInCell = threadButton.convert(CGPoint(x: threadButton.bounds.midX, y: threadButton.bounds.midY), to: commentCell)
        #expect(commentCell.hitTest(buttonCenterInCell, with: nil) === threadButton)
        threadButton.sendActions(for: .touchUpInside)
        #expect(presenter.threadedReplyComments.map(\.id) == ["90003"])

        // 长按菜单兜底入口仍有效
        let action = try #require(commentCell.floorActions.first { $0.title == threadTitle })
        #expect(action.perform())
        #expect(presenter.threadedReplyComments.map(\.id) == ["90003", "90003"])
    }

    @Test func sheetRendersStatesParentBadgeAndPreservesScrollPositionOnPrepend() throws {
        let root = Self.comment(floor: 3, author: "Mori", markdown: "杭州电信的节点有人测过吗？")
        let fetcher = StaticNoopFetcher()
        let coordinator = ThreadedReplyCoordinator(
            postID: Self.postID,
            pageFetcher: fetcher,
            sessionStore: NodeSeekSessionStore(),
            accountFingerprintProvider: {
                ThreadedReplyAccountFingerprint(sessionID: nil, isLoggedIn: false, displayName: nil, profileURL: nil)
            },
            sleep: { _ in }
        )

        let sheet = ThreadedRepliesSheetViewController(rootComment: root, coordinator: coordinator)
        sheet.loadViewIfNeeded()
        sheet.stopSubscription()
        sheet.view.frame = CGRect(x: 0, y: 0, width: 390, height: 640)
        sheet.view.layoutIfNeeded()

        // 1. 完成空态
        let emptySnapshot = ThreadedReplyPanelSnapshot(
            postID: Self.postID,
            rootFloor: 3,
            rootComment: root,
            nodes: [],
            state: .completed,
            totalPages: 1,
            completedPages: [1]
        )
        sheet.apply(emptySnapshot)
        sheet.collectionView.layoutIfNeeded()
        #expect(sheet.view.firstLabel(accessibilityIdentifier: "threaded-replies-empty-label") != nil)
        let statusLabel = try #require(sheet.view.firstLabel(accessibilityIdentifier: "threaded-replies-status-label"))
        #expect(statusLabel.text == DetailListStrings.text("thread-completed-empty"))

        // 2. 四级深度展示「回复 #上级」提示 & 单轮上限暂停按钮
        let deepNodes: [ThreadedReplyNode] = [
            Self.node(floor: 4, parent: 3, depth: 1, last: false, hasChildren: true),
            Self.node(floor: 5, parent: 4, depth: 2, last: true, hasChildren: true),
            Self.node(floor: 6, parent: 5, depth: 3, last: true, hasChildren: true),
            Self.node(floor: 7, parent: 6, depth: 4, last: true, hasChildren: false),
            Self.node(floor: 23, parent: 3, depth: 1, last: true, hasChildren: false)
        ]
        let pausedSnapshot = ThreadedReplyPanelSnapshot(
            postID: Self.postID,
            rootFloor: 3,
            rootComment: root,
            nodes: deepNodes,
            state: .pausedAtBatchLimit(scannedUpToPage: 20, totalPages: 35),
            totalPages: 35,
            completedPages: Set(1...20)
        )
        sheet.apply(pausedSnapshot)
        sheet.collectionView.layoutIfNeeded()

        let actionButton = try #require(sheet.view.firstButton(accessibilityIdentifier: "threaded-replies-action-button"))
        #expect(actionButton.isHidden == false)
        #expect(actionButton.configuration?.title == DetailListStrings.text("thread-continue"))

        let deepBadge = sheet.collectionView.firstLabel(accessibilityIdentifier: "threaded-reply-parent-badge-7")
        #expect(deepBadge?.isHidden == false)
        #expect(deepBadge?.text == String(format: DetailListStrings.text("thread-replying-to"), 6))

        // 3. 滚到后方分支后，在前方插入新回复，可见楼层应保持屏内相对偏移稳定
        let initialLongNodes = (20...32).map { floor in
            Self.node(floor: floor, parent: 3, depth: 1, last: floor == 32, hasChildren: false)
        }
        sheet.apply(
            ThreadedReplyPanelSnapshot(
                postID: Self.postID,
                rootFloor: 3,
                rootComment: root,
                nodes: initialLongNodes,
                state: .scanning(currentPage: 2, totalPages: 3),
                totalPages: 3,
                completedPages: [1]
            )
        )
        sheet.collectionView.layoutIfNeeded()
        sheet.collectionView.contentOffset.y = 260
        sheet.collectionView.layoutIfNeeded()

        let anchorPathBefore = try #require(sheet.collectionView.indexPathsForVisibleItems.sorted { $0.item < $1.item }.first)
        let anchorFloorBefore = initialLongNodes[max(0, anchorPathBefore.item - 1)].floor
        let anchorFrameBefore = try #require(sheet.collectionView.layoutAttributesForItem(at: anchorPathBefore)?.frame)
        let relativeBefore = anchorFrameBefore.minY - sheet.collectionView.contentOffset.y

        // 在最前面插入 3 条新分支节点
        let prependedNodes = [
            Self.node(floor: 8, parent: 3, depth: 1, last: false, hasChildren: true),
            Self.node(floor: 15, parent: 8, depth: 2, last: true, hasChildren: true),
            Self.node(floor: 18, parent: 15, depth: 3, last: true, hasChildren: false)
        ] + initialLongNodes
        sheet.apply(
            ThreadedReplyPanelSnapshot(
                postID: Self.postID,
                rootFloor: 3,
                rootComment: root,
                nodes: prependedNodes,
                state: .completed,
                totalPages: 3,
                completedPages: [1, 2, 3]
            )
        )
        sheet.collectionView.layoutIfNeeded()

        let expectedNewItem = try #require(prependedNodes.firstIndex { $0.floor == anchorFloorBefore }) + 1
        let anchorFrameAfter = try #require(
            sheet.collectionView.layoutAttributesForItem(at: IndexPath(item: expectedNewItem, section: 0))?.frame
        )
        let relativeAfter = anchorFrameAfter.minY - sheet.collectionView.contentOffset.y
        #expect(abs(relativeAfter - relativeBefore) < 2.0)

        // 4. 长按的楼层本身回复了上级楼层时，上方展示祖先链且焦点楼高亮区分
        let floor3 = Self.comment(floor: 3, author: "Mori", markdown: "杭州电信的节点有人测过吗？")
        let floor8 = Self.comment(floor: 8, author: "Alice", markdown: "@Mori [#3](/post-12000-1#3) 晚高峰测了几次，挺稳的。")
        let floor15 = Self.comment(floor: 15, author: "Kero", markdown: "@Alice [#8](/post-12000-1#8) 有延迟数据吗？")
        let ancestorSnapshot = ThreadedReplyPanelSnapshot(
            postID: Self.postID,
            rootFloor: 15,
            rootComment: floor15,
            ancestors: [
                ThreadedAncestorNode(comment: floor3, floor: 3, parentFloorInChain: nil),
                ThreadedAncestorNode(comment: floor8, floor: 8, parentFloorInChain: 3)
            ],
            rootDisplayedParentFloor: 8,
            nodes: [Self.node(floor: 18, parent: 15, depth: 1, last: true, hasChildren: false)],
            state: .completed,
            totalPages: 3,
            completedPages: [1, 2, 3]
        )
        sheet.collectionView.contentOffset.y = 0
        sheet.apply(ancestorSnapshot)
        sheet.collectionView.layoutIfNeeded()

        // 顺序：#3（祖先）-> #8（祖先）-> #15（焦点楼，高亮）-> #18（下游回复）
        let cell0 = try #require(sheet.collectionView.cellForItem(at: IndexPath(item: 0, section: 0)))
        let cell1 = try #require(sheet.collectionView.cellForItem(at: IndexPath(item: 1, section: 0)))
        let cell2 = try #require(sheet.collectionView.cellForItem(at: IndexPath(item: 2, section: 0)))
        let cell3 = try #require(sheet.collectionView.cellForItem(at: IndexPath(item: 3, section: 0)))
        #expect(cell0.accessibilityIdentifier == "thread-ancestor-3-comment-90003")
        #expect(cell1.accessibilityIdentifier == "thread-ancestor-8-comment-90008")
        #expect(cell2.accessibilityIdentifier == "root-15-90015")
        #expect(cell3.accessibilityIdentifier == "thread-floor-18-comment-90018")
        #expect(cell2.contentView.backgroundColor == .secondarySystemBackground)
        #expect(cell0.contentView.backgroundColor == .systemBackground)
    }

    private static func comment(floor: Int, author: String = "User", markdown: String? = "正文") -> nodeseek.Comment {
        nodeseek.Comment(
            id: "\(90000 + floor)",
            anchorID: "\(floor)",
            authorName: author,
            avatarURL: nil,
            floorText: "#\(floor)",
            createdAtText: "刚刚",
            contentHTML: "<p>html</p>",
            markdown: markdown,
            hasVisibleMarkdown: true
        )
    }

    private static func node(floor: Int, parent: Int, depth: Int, last: Bool, hasChildren: Bool) -> ThreadedReplyNode {
        ThreadedReplyNode(
            comment: comment(floor: floor, author: "User\(floor)", markdown: "第 \(floor) 楼正文"),
            floor: floor,
            parentFloor: parent,
            depth: depth,
            ancestorContinuations: Array(repeating: false, count: max(0, depth - 1)),
            isLastSibling: last,
            hasChildren: hasChildren
        )
    }
}

private final class StaticNoopFetcher: PostDetailPageFetching {
    func fetchPostDetailPage(postID: String, page: Int) async throws -> NodeSeekResult<PostDetail> {
        throw CancellationError()
    }
}

private final class ThreadMenuSpyPresenter: PostDetailPresenterProtocol {
    var threadedReplyComments: [nodeseek.Comment] = []

    func viewDidLoad() {}
    func refreshInitialPage() {}
    func didSelectCommentPage(_ page: Int) {}
    func didTapLogin() {}
    @discardableResult func didApproachCommentEnd() -> Bool { false }
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
    func didTapThreadedReplies(for comment: nodeseek.Comment) {
        threadedReplyComments.append(comment)
    }
}

private extension UIView {
    func firstLabel(accessibilityIdentifier: String) -> UILabel? {
        if let label = self as? UILabel, label.accessibilityIdentifier == accessibilityIdentifier {
            return label
        }
        for subview in subviews {
            if let found = subview.firstLabel(accessibilityIdentifier: accessibilityIdentifier) {
                return found
            }
        }
        return nil
    }

    func firstButton(accessibilityIdentifier: String) -> UIButton? {
        if let button = self as? UIButton, button.accessibilityIdentifier == accessibilityIdentifier {
            return button
        }
        for subview in subviews {
            if let found = subview.firstButton(accessibilityIdentifier: accessibilityIdentifier) {
                return found
            }
        }
        return nil
    }
}
