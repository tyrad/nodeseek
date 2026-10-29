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
