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
        let synchronizer = SpyLoginCookieSynchronizer()
        let viewController = LoginWebViewController(cookieSynchronizer: synchronizer)

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
        let synchronizer = SpyLoginCookieSynchronizer()
        var closeCount = 0
        let viewController = LoginWebViewController(cookieSynchronizer: synchronizer) {
            closeCount += 1
        }
        viewController.loadViewIfNeeded()

        let closeButton = try #require(viewController.navigationItem.rightBarButtonItem)
        let action = try #require(closeButton.action)
        _ = (closeButton.target as AnyObject).perform(action)
        try await Task.sleep(nanoseconds: 120_000_000)

        #expect(synchronizer.syncWebToURLSessionCount == 1)
        #expect(closeCount == 1)
    }

    @Test func closeCancelsPendingInitialCookieSync() async throws {
        let synchronizer = SpyLoginCookieSynchronizer()
        synchronizer.suspendURLSessionSync = true
        var closeCount = 0
        let viewController = LoginWebViewController(cookieSynchronizer: synchronizer) {
            closeCount += 1
        }
        viewController.loadViewIfNeeded()
        await synchronizer.waitForURLSessionSyncStart()

        let closeButton = try #require(viewController.navigationItem.rightBarButtonItem)
        let action = try #require(closeButton.action)
        _ = (closeButton.target as AnyObject).perform(action)
        try await Task.sleep(nanoseconds: 30_000_000)

        synchronizer.resumeURLSessionSync()
        try await Task.sleep(nanoseconds: 120_000_000)

        #expect(synchronizer.syncURLSessionObservedCancellation)
        #expect(synchronizer.syncWebToURLSessionCount == 1)
        #expect(closeCount == 1)
    }
}

@MainActor
private final class SpyLoginCookieSynchronizer: LoginCookieSynchronizing {
    private(set) var syncURLSessionToWebCount = 0
    private(set) var syncWebToURLSessionCount = 0
    var suspendURLSessionSync = false
    private(set) var syncURLSessionObservedCancellation = false
    private var urlSessionSyncStartContinuation: CheckedContinuation<Void, Never>?
    private var urlSessionSyncResumeContinuation: CheckedContinuation<Void, Never>?

    func syncURLSessionCookiesToWebView() async {
        syncURLSessionToWebCount += 1
        urlSessionSyncStartContinuation?.resume()
        urlSessionSyncStartContinuation = nil

        guard suspendURLSessionSync else { return }

        await withCheckedContinuation { continuation in
            urlSessionSyncResumeContinuation = continuation
        }
        syncURLSessionObservedCancellation = Task.isCancelled
    }

    func syncWebViewCookiesToURLSession() async {
        syncWebToURLSessionCount += 1
    }

    func waitForURLSessionSyncStart() async {
        guard syncURLSessionToWebCount == 0 else { return }

        await withCheckedContinuation { continuation in
            urlSessionSyncStartContinuation = continuation
        }
    }

    func resumeURLSessionSync() {
        urlSessionSyncResumeContinuation?.resume()
        urlSessionSyncResumeContinuation = nil
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
