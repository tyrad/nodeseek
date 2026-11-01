//
//  LoginWebViewControllerTests.swift
//  nodeseekTests
//

import Testing
import UIKit
@testable import nodeseek

@MainActor
struct LoginWebViewControllerTests {
    @Test func showsHintAndCloseButton() throws {
        let cookieSession = SpyLoginCookieSession()
        let viewController = LoginWebViewController(
            cookieSession: cookieSession,
            automaticallyLoadsPage: false
        )

        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.layoutIfNeeded()

        let hintContainer = try #require(viewController.view.firstView(accessibilityIdentifier: "login-hint-container"))
        let hintLabel = try #require(viewController.view.firstLabel(text: "登录成功后关闭当前页面即可"))
        #expect(hintContainer.layer.cornerRadius == 12)
        #expect(hintContainer.frame.minX > 0)
        #expect(hintLabel.numberOfLines == 0)
        #expect(hintLabel.textAlignment == .natural)
        let closeButton = try #require(viewController.navigationItem.rightBarButtonItem)
        #expect(closeButton.accessibilityLabel == "关闭登录页")
        #expect(closeButton.title == nil)
        #expect(closeButton.image != nil)
        #expect(closeButton.tintColor == .label)
    }

    @Test func closeSyncsCookiesAndCallsCompletion() async throws {
        let cookieSession = SpyLoginCookieSession()
        var closeCount = 0
        let viewController = LoginWebViewController(cookieSession: cookieSession) {
            closeCount += 1
        }
        viewController.loadViewIfNeeded()

        let closeButton = try #require(viewController.navigationItem.rightBarButtonItem)
        let action = try #require(closeButton.action)
        _ = (closeButton.target as AnyObject).perform(action)
        try await Task.sleep(nanoseconds: 120_000_000)

        #expect(cookieSession.captureWebViewSessionCount == 1)
        #expect(closeCount == 1)
    }

    @Test func closeCancelsPendingInitialCookieSync() async throws {
        let cookieSession = SpyLoginCookieSession()
        cookieSession.suspendWebViewPreparation = true
        var closeCount = 0
        let viewController = LoginWebViewController(cookieSession: cookieSession) {
            closeCount += 1
        }
        viewController.loadViewIfNeeded()
        await cookieSession.waitForWebViewPreparationStart()

        let closeButton = try #require(viewController.navigationItem.rightBarButtonItem)
        let action = try #require(closeButton.action)
        _ = (closeButton.target as AnyObject).perform(action)
        try await Task.sleep(nanoseconds: 30_000_000)

        cookieSession.resumeWebViewPreparation()
        try await Task.sleep(nanoseconds: 120_000_000)

        #expect(cookieSession.prepareWebViewLoadObservedCancellation)
        #expect(cookieSession.captureWebViewSessionCount == 1)
        #expect(closeCount == 1)
    }
}

@MainActor
private final class SpyLoginCookieSession: NodeSeekCookieSessionManaging {
    private(set) var prepareWebViewLoadCount = 0
    private(set) var captureWebViewSessionCount = 0
    var suspendWebViewPreparation = false
    private(set) var prepareWebViewLoadObservedCancellation = false
    private var webViewPreparationStartContinuation: CheckedContinuation<Void, Never>?
    private var webViewPreparationResumeContinuation: CheckedContinuation<Void, Never>?

    func prepareWebViewLoad(userInterfaceStyle: UIUserInterfaceStyle?) async {
        prepareWebViewLoadCount += 1
        webViewPreparationStartContinuation?.resume()
        webViewPreparationStartContinuation = nil

        guard suspendWebViewPreparation else { return }

        await withCheckedContinuation { continuation in
            webViewPreparationResumeContinuation = continuation
        }
        prepareWebViewLoadObservedCancellation = Task.isCancelled
    }

    func captureWebViewSession() async {
        captureWebViewSessionCount += 1
    }

    func prepareHTTPLoad() async {}

    func prepareMediaRequest() async {}

    func clearLoginSession() async {}

    func waitForWebViewPreparationStart() async {
        guard prepareWebViewLoadCount == 0 else { return }

        await withCheckedContinuation { continuation in
            webViewPreparationStartContinuation = continuation
        }
    }

    func resumeWebViewPreparation() {
        webViewPreparationResumeContinuation?.resume()
        webViewPreparationResumeContinuation = nil
    }
}

private extension UIView {
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

    func firstLabel(text: String) -> UILabel? {
        if let label = self as? UILabel, label.text == text {
            return label
        }

        for subview in subviews {
            if let matched = subview.firstLabel(text: text) {
                return matched
            }
        }

        return nil
    }
}
