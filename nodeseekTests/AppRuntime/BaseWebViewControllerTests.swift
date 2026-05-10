//
//  BaseWebViewControllerTests.swift
//  nodeseekTests
//

import Testing
import UIKit
@testable import nodeseek

@MainActor
struct BaseWebViewControllerTests {
    @Test func defaultNavigationItemsIncludeRefreshAction() throws {
        let viewController = TestBaseWebViewController()

        viewController.loadViewIfNeeded()

        let moreButton = try #require(viewController.navigationItem.rightBarButtonItem)
        _ = try #require(moreButton.menu?.children.first { $0.title == "刷新" } as? UIAction)
    }

    @Test func javaScriptDialogTitleUsesHostWhenURLHasHost() throws {
        let url = try #require(URL(string: "https://www.nodeseek.com/post-1-1"))

        #expect(BaseWebViewController.javaScriptDialogTitle(for: url) == "www.nodeseek.com")
    }

    @Test func javaScriptDialogTitleFallsBackToGenericWebTitle() {
        #expect(BaseWebViewController.javaScriptDialogTitle(for: nil) == "网页")
    }

    @Test func textInputAlertKeepsDefaultTextAndActions() {
        let alert = BaseWebViewController.makeJavaScriptTextInputAlert(
            title: "www.nodeseek.com",
            prompt: "请输入内容",
            defaultText: "默认值",
            completionHandler: { _ in }
        )

        #expect(alert.title == "www.nodeseek.com")
        #expect(alert.message == "请输入内容")
        #expect(alert.textFields?.first?.text == "默认值")
        #expect(alert.actions.map(\.title) == ["取消", "确定"])
    }
}

private final class TestBaseWebViewController: BaseWebViewController {
    init() {
        super.init(
            initialURL: NodeSeekSite.baseURL,
            pageTitle: "测试",
            automaticallyLoadsPage: false
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadInitialPage() {}
}
