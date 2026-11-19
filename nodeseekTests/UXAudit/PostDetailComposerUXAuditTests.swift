import AsyncDisplayKit
import UIKit
import XCTest
@testable import nodeseek

/// UX 审计（详情页回复编辑器 + 引用内容构建）的 RED 测试：当前实现下应当失败。
@MainActor
final class PostDetailComposerUXAuditTests: XCTestCase {
    private var windows: [UIWindow] = []

    override func tearDown() async throws {
        for window in windows {
            window.rootViewController?.view.endEditing(true)
            window.isHidden = true
            window.rootViewController = nil
        }
        windows.removeAll()
        try await super.tearDown()
    }

    // MARK: - U10

    // 期望：表情面板展开时，面板（或其容器）贴到视图底边，不在下方露出后面的内容。
    func test_U10_stickerPanelExtendsToViewBottomEdge() async throws {
        let viewController = try await makeHostedDetailViewController()
        viewController.showReplyEditorForTesting(action: "回复", authorName: "netcup", floorText: "#10")
        viewController.setStickerPickerVisible(true, animated: false)
        viewController.view.layoutIfNeeded()

        let rootView = try XCTUnwrap(viewController.view)
        let pickerFrame = viewController.replyStickerPickerView.convert(viewController.replyStickerPickerView.bounds, to: rootView)
        let containerFrame = viewController.replyEditorContainer.convert(viewController.replyEditorContainer.bounds, to: rootView)
        let coveredBottom = max(pickerFrame.maxY, containerFrame.maxY)
        let gap = rootView.bounds.maxY - coveredBottom

        XCTAssertLessThanOrEqual(
            gap, 0.5,
            "U10: 表情面板下方露出 \(gap)pt 空隙（pickerMaxY=\(pickerFrame.maxY), containerMaxY=\(containerFrame.maxY), viewMaxY=\(rootView.bounds.maxY)）"
        )
    }

    // MARK: - U21

    // 期望：引用多行评论时保留换行，每行都是独立的 "> " 引用行。
    func test_U21_quotePreservesLineBreaks() {
        let comment = makeComment(id: "1", floor: 3, html: "<p>line 1<br>line 2<br>line 3</p>")

        let content = CommentComposerContentBuilder.content(
            text: "",
            mode: .quote([comment]),
            postURL: URL(string: "https://www.nodeseek.com/post-1-1")!
        )

        let lines = content.components(separatedBy: "\n")
        let line1 = lines.firstIndex { $0.contains("line 1") }
        let line2 = lines.firstIndex { $0.contains("line 2") }
        let line2IsQuoted = line2.map { lines[$0].hasPrefix(">") } ?? false
        XCTAssertTrue(
            line1 != nil && line2 != nil && line1 != line2 && line2IsQuoted,
            "U21: 多行评论被压成一行引用：\(content.debugDescription)"
        )
    }

    // MARK: - U22

    // 期望：引用只有图片/表情的评论时，引用块里有 “[图片]”/“[表情]” 之类的占位，而不是只有标题行。
    func test_U22_quoteOfImageOnlyCommentHasPlaceholder() {
        let imageComment = makeComment(
            id: "1",
            floor: 1,
            html: #"<p><img src="https://cdn.nodeimage.com/i/FBICDKhbCSRbkZ5Kx5qyiyit927K3vCg.webp" alt="image"></p>"#
        )
        let stickerComment = makeComment(
            id: "2",
            floor: 2,
            html: #"<p><img class="sticker" src="/static/image/sticker/xhj/001.png" loading="lazy" alt="xhj001"></p>"#
        )
        let postURL = URL(string: "https://www.nodeseek.com/post-1-1")!

        let results = [imageComment, stickerComment].map { comment -> (String, Bool) in
            let content = CommentComposerContentBuilder.content(text: "", mode: .quote([comment]), postURL: postURL)
            let bodyLines = content.components(separatedBy: "\n").dropFirst()
            let hasPlaceholder = bodyLines.contains { $0.hasPrefix(">") && ($0.contains("[图片]") || $0.contains("[表情]")) }
            return (content, hasPlaceholder)
        }

        XCTAssertTrue(
            results.allSatisfy(\.1),
            "U22: 图片/表情评论的引用块只有标题行，没有占位内容：\(results.map(\.0).map(\.debugDescription))"
        )
    }

    // MARK: - U28

    // 期望：回复楼主时编辑器顶部显示“回复楼主”之类的文案，不出现 “#0”。
    func test_U28_replyToPosterContextAvoidsFloorZero() async throws {
        let viewController = try await makeHostedDetailViewController()
        let header = PostDetailHeaderContent(
            postID: "703863",
            title: "详情标题",
            authorName: "缭雾",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>正文</p>"
        )

        viewController.handleReply(toPostHeader: header)
        let didShow = await waitUntil(timeout: 2) { viewController.replyEditorContainer.isHidden == false }
        XCTAssertTrue(didShow, "前置条件：回复编辑器应已展示")

        let label = viewController.view.uxFirstLabel(accessibilityIdentifier: "post-detail-reply-context-label")
        let text = label?.text ?? ""
        XCTAssertTrue(
            text.contains("#0") == false && text.contains("楼主"),
            "U28: 回复楼主的上下文文案为 \(text.debugDescription)，应显示“回复楼主”且不含 #0"
        )
    }

    // MARK: - U31

    // 期望：编辑评论的未保存草稿条不显示“无标题”（评论本来就没有标题）。
    func test_U31_commentDraftStripDoesNotShowUntitled() throws {
        let presenter = UXComposerNewDiscussionPresenter(state: NewDiscussionViewState(
            isEditing: true,
            editingCommentFloor: 12,
            category: nil,
            rank: .everyone,
            userLevel: .loaded(2),
            pendingDraft: NewDiscussionDraft(title: "", content: "改过的评论正文", updatedAt: Date().addingTimeInterval(-14)),
            saveStatus: .waitingForDraftDecision,
            canPublish: true,
            isSubmitting: false
        ))
        let editor = NewDiscussionViewController(presenter: presenter)
        editor.loadViewIfNeeded()
        editor.render(presenter.state)

        let stripTexts = editor.view.uxAllLabels()
            .compactMap(\.text)
            .filter { $0.contains("·") || $0.contains("上次") }

        XCTAssertFalse(
            stripTexts.contains { $0.contains("无标题") },
            "U31: 编辑评论的草稿条显示了“无标题”：\(stripTexts)"
        )
    }

    // MARK: - Helpers

    private func host(_ viewController: UIViewController) {
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: UIScreen.main.bounds)
        }
        windows.append(window)
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        viewController.loadViewIfNeeded()
        window.layoutIfNeeded()
    }

    private func makeHostedDetailViewController() async throws -> PostDetailViewController {
        let viewController = PostDetailViewController(
            presenter: UXComposerStubPresenter(),
            accountRefresher: UXComposerLoggedInRefresher()
        )
        host(viewController)
        viewController.render(detail: makeDetail(comments: [
            makeComment(id: "c1", floor: 1, html: "<p>第一楼</p>")
        ]))
        let didRender = await waitUntil(timeout: 3) { viewController.hasRenderedDetailContent }
        XCTAssertTrue(didRender, "前置条件：详情应完成渲染")
        return viewController
    }

    private func makeDetail(comments: [Comment]) -> PostDetail {
        PostDetail(
            id: "703863",
            title: "详情标题",
            authorName: "缭雾",
            avatarURL: nil,
            metadataText: "刚刚",
            contentHTML: "<p>正文</p>",
            comments: comments,
            page: 1,
            isLastPage: true
        )
    }

    private func makeComment(id: String, floor: Int, html: String, isOwnComment: Bool = false) -> Comment {
        Comment(
            id: id,
            anchorID: "\(floor)",
            authorName: "user\(floor)",
            avatarURL: nil,
            floorText: "#\(floor)",
            createdAtText: "1min ago",
            createdAtTitleText: "2026-11-18 10:00:00",
            contentHTML: html,
            isOwnComment: isOwnComment
        )
    }

    @discardableResult
    private func waitUntil(
        timeout: TimeInterval = 1,
        condition: () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }
}

// MARK: - Test doubles

private struct UXComposerLoggedInRefresher: CurrentAccountRefreshing {
    func cachedAccount() async -> AccountResponse? {
        AccountResponse(displayName: "mist", isLoggedIn: true)
    }

    func refreshIfNeeded(force: Bool, maxAge: TimeInterval) async -> AccountResponse? {
        AccountResponse(displayName: "mist", isLoggedIn: true)
    }
}

private final class UXComposerStubPresenter: PostDetailPresenterProtocol {
    func viewDidLoad() {}
    func refreshInitialPage() {}
    func didSelectCommentPage(_ page: Int) {}
    func didTapLogin() {}
    func didApproachCommentEnd() {}
    func didTapRefreshCommentsAtEnd() {}
    func didTapSendReply(content: String) {}
    func didTapFavorite() {}
    func didTapPostLike() {}
    func didTapPostChickenLeg() {}
    func didTapPostOppose() {}
    func didTapCommentLike(_ comment: Comment) {}
    func didTapCommentChickenLeg(_ comment: Comment) {}
    func didTapCommentOppose(_ comment: Comment) {}
    func didTapEditPost() {}
    func didTapEditComment(_ comment: Comment) {}
}

private final class UXComposerNewDiscussionPresenter: NewDiscussionPresenterProtocol {
    let state: NewDiscussionViewState
    let rankOptions: [DiscussionReadRank] = [.everyone]

    init(state: NewDiscussionViewState) {
        self.state = state
    }

    func viewDidLoad() {}
    func retryLoadingUserLevel() {}
    func didChangeTitle(_ title: String) {}
    func didChangeContent(_ content: String) {}
    func didSelectCategory(_ category: DiscussionCategory) {}
    func didSelectRank(_ rank: DiscussionReadRank) {}
    func didChangeUploadingImageCount(_ count: Int) {}
    func restorePendingDraft() {}
    func discardPendingDraft() {}
    func closeDecision() -> NewDiscussionCloseDecision { .close }
    func close(savingDraft: Bool) {}
    func closeKeepingPendingDraft() {}
    func didTapPublish() {}
    func didTapOpenWebFallback() {}
}

private extension UIView {
    func uxAllSubviews<T: UIView>(of type: T.Type) -> [T] {
        var result: [T] = []
        if let matched = self as? T { result.append(matched) }
        for subview in subviews {
            result.append(contentsOf: subview.uxAllSubviews(of: type))
        }
        return result
    }

    func uxAllLabels() -> [UILabel] {
        uxAllSubviews(of: UILabel.self)
    }

    func uxFirstLabel(accessibilityIdentifier: String) -> UILabel? {
        uxAllLabels().first { $0.accessibilityIdentifier == accessibilityIdentifier }
    }
}
