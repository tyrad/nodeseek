//
//  NewDiscussionRouter.swift
//  nodeseek
//

import UIKit

final class NewDiscussionRouter: NewDiscussionRouterProtocol {
    weak var viewController: UIViewController?
    private let onPublished: (NodeSeekPostRoute?) -> Void

    init(onPublished: @escaping (NodeSeekPostRoute?) -> Void) {
        self.onPublished = onPublished
    }

    /// 返回包好导航栏的发帖页，由调用方全屏弹出。
    static func createModule(
        draftStore: NewDiscussionDraftStoring = UserDefaultsNewDiscussionDraftStore(),
        submitter: NodeSeekDiscussionSubmitting = WebViewNodeSeekDiscussionSubmitter(),
        onPublished: @escaping (NodeSeekPostRoute?) -> Void
    ) -> UINavigationController {
        let router = NewDiscussionRouter(onPublished: onPublished)
        let presenter = NewDiscussionPresenter(router: router, draftStore: draftStore, submitter: submitter)
        let view = NewDiscussionViewController(presenter: presenter)
        presenter.view = view
        router.viewController = view

        let navigationController = UINavigationController(rootViewController: view)
        navigationController.modalPresentationStyle = .fullScreen
        return navigationController
    }

    /// 编辑已发帖子：复用发帖页，草稿按帖子单独存。
    static func createEditModule(
        editable: EditableDiscussion,
        onSaved: @escaping () -> Void
    ) -> UINavigationController {
        createEditModule(
            mode: .edit(editable),
            draftKey: "com.nodeseek.edit-discussion-draft.\(editable.postID)",
            onSaved: onSaved
        )
    }

    /// 编辑自己的评论：复用发帖页，不显示标题和发布设置，草稿按评论单独存。
    static func createEditModule(
        editable: EditableComment,
        onSaved: @escaping () -> Void
    ) -> UINavigationController {
        createEditModule(
            mode: .editComment(editable),
            draftKey: "com.nodeseek.edit-comment-draft.\(editable.commentID)",
            onSaved: onSaved
        )
    }

    private static func createEditModule(
        mode: NewDiscussionMode,
        draftKey: String,
        onSaved: @escaping () -> Void
    ) -> UINavigationController {
        let editor = WebViewNodeSeekDiscussionSubmitter()
        let router = NewDiscussionRouter(onPublished: { _ in onSaved() })
        let presenter = NewDiscussionPresenter(
            router: router,
            draftStore: UserDefaultsNewDiscussionDraftStore(storageKey: draftKey),
            submitter: editor,
            mode: mode,
            editor: editor
        )
        let view = NewDiscussionViewController(presenter: presenter)
        presenter.view = view
        router.viewController = view

        let navigationController = UINavigationController(rootViewController: view)
        navigationController.modalPresentationStyle = .fullScreen
        return navigationController
    }

    func dismiss() {
        viewController?.dismiss(animated: true)
    }

    func finishPublishing(route: NodeSeekPostRoute?) {
        let onPublished = onPublished
        viewController?.dismiss(animated: true) {
            onPublished(route)
        }
    }

    /// 兜底：回到网页发帖页。正文由页面先复制到剪贴板。
    func openWebFallback() {
        let webViewController = NewDiscussionWebViewController()
        viewController?.navigationController?.pushViewController(webViewController, animated: true)
    }
}
