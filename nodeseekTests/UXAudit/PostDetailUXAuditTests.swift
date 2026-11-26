//
//  PostDetailUXAuditTests.swift
//  nodeseekTests
//
//  UX 走查（2026-11-18）详情页展示与操作区问题的 RED 测试。
//  每个测试描述修复后应成立的行为，当前代码下应因断言失败。
//

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
        XCTAssertEqual(view.failureToastMessages, ["更多评论加载失败"])
    }

    // MARK: - U19

    // 预期：自己的评论和自己的帖子不显示（或禁用）点赞 / 鸡腿 / 反对按钮，避免点了才报“不能给自己点赞”。
    func test_U19_ownContentHidesEmptyCountsAndDisablesExistingVotes() {
        for count in [0, 3] {
            let cell = DetailFloorListCell(frame: .zero)
            cell.addVotes(like: count, chicken: 0, oppose: 0, liked: false, rewarded: false, opposed: false, isOwn: true,
                          onLike: {}, onChicken: {}, onOppose: {})
            let votes = cell.contentView.uxAuditAllSubviews().compactMap { $0 as? UIButton }.filter {
                $0.accessibilityLabel == DetailListStrings.text("like") || $0.accessibilityLabel == DetailListStrings.text("chicken")
            }
            XCTAssertEqual(votes.count, count == 0 ? 0 : 1)
            if count > 0 {
                XCTAssertEqual(votes.first?.accessibilityValue, "3")
                XCTAssertEqual(votes.first?.isEnabled, false)
            }
        }
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


}

// MARK: - Test doubles

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
    private(set) var failureToastMessages: [String] = []
    private(set) var errorMessages: [String] = []

    func showLoading() {}
    func showLoadingMoreComments() {}
    func hideLoadingMoreComments() {}
    func hideLoading() {}
    func showError(message: String) { errorMessages.append(message) }
    func showToast(message: String) { successToastMessages.append(message) }
    func showProgressToast(message: String) { progressToastMessages.append(message) }
    func showFailureToast(message: String) { failureToastMessages.append(message) }
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
