import JXPhotoBrowser
import UIKit
import XCTest
@testable import nodeseek

@MainActor
final class UserProfileViewControllerTests: XCTestCase {
    func testTappingAvatarPresentsFullImage() async throws {
        MockProfileURLProtocol.responseData = Data(
            """
            {"success":true,"detail":{"member_id":1,"member_name":"Lloyd","rank":6,"coin":1,"stardust":1,
            "bio":"","nPost":1,"nComment":1,"follows":0,"fans":1,"readme":"","roles":[]}}
            """.utf8
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockProfileURLProtocol.self]
        let client = NodeSeekUserContentClient(session: URLSession(configuration: configuration))
        let controller = UserProfileViewController(uid: 1, client: client)
        let navigation = UINavigationController(rootViewController: controller)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }

        controller.loadViewIfNeeded()
        let avatar = try await waitForAvatar(in: controller)
        XCTAssertEqual(avatar.accessibilityLabel, "查看头像大图")
        XCTAssertTrue(avatar.accessibilityTraits.contains(.button))

        avatar.sendActions(for: .touchUpInside)
        let browser = try await waitForBrowser(from: controller)
        let presenter = try XCTUnwrap(browser.delegate as? DetailPhotoBrowserPresenter)
        XCTAssertEqual(presenter.numberOfItems(in: browser), 1)
    }

    private func waitForAvatar(in controller: UserProfileViewController) async throws -> UIControl {
        for _ in 0..<50 {
            if let avatar = descendants(controller.view).compactMap({ $0 as? UIControl }).first(where: { $0.accessibilityIdentifier == "user-profile-avatar" }) {
                return avatar
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("个人页头像没有出现")
        throw CancellationError()
    }

    private func waitForBrowser(from controller: UIViewController) async throws -> JXPhotoBrowserViewController {
        for _ in 0..<50 {
            if let browser = controller.presentedViewController as? JXPhotoBrowserViewController {
                return browser
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        return try XCTUnwrap(controller.presentedViewController as? JXPhotoBrowserViewController)
    }

    private func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }
}

private final class MockProfileURLProtocol: URLProtocol, @unchecked Sendable {
    static var responseData = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
