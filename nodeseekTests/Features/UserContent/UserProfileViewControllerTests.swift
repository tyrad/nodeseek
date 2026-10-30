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

    func testFollowButtonFollowsAndUpdatesFans() async throws {
        MockProfileURLProtocol.responseData = Data(
            """
            {"success":true,"detail":{"member_id":9,"member_name":"酒神","rank":6,"coin":17995,"stardust":1386,
            "bio":"人生得意须尽欢，莫使金樽空对月","nPost":374,"nComment":4790,"follows":3,"fans":366,"readme":"",
            "roles":[],"followed":false}}
            """.utf8
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockProfileURLProtocol.self]
        let submitter = ProfileFollowSubmitterStub()
        let client = NodeSeekUserContentClient(session: URLSession(configuration: configuration), followSubmitter: submitter)
        let controller = UserProfileViewController(uid: 9, client: client)
        let navigation = UINavigationController(rootViewController: controller)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }

        controller.loadViewIfNeeded()
        var button: UIButton?
        for _ in 0..<50 where button == nil {
            button = descendants(controller.view).first { $0.accessibilityIdentifier == "user-profile-follow-button" && $0.window != nil } as? UIButton
            if button == nil { try await Task.sleep(nanoseconds: 50_000_000) }
        }
        let follow = try XCTUnwrap(button)
        XCTAssertEqual(follow.configuration?.title, "关注")
        window.layoutIfNeeded()
        capture(window, name: "profile-follow-light")

        follow.sendActions(for: .touchUpInside)
        try await Task.sleep(nanoseconds: 100_000_000)
        // 请求中保持原来的反色样式，只转圈、不响应点击
        XCTAssertTrue(follow.isEnabled)
        XCTAssertFalse(follow.isUserInteractionEnabled)
        XCTAssertEqual(follow.configuration?.showsActivityIndicator, true)
        capture(window, name: "profile-follow-busy")
        for _ in 0..<50 where follow.configuration?.title != "已关注" { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(submitter.paths, ["/api/fans/add"])
        XCTAssertEqual(follow.configuration?.title, "已关注")
        XCTAssertTrue(descendants(controller.view).compactMap { $0 as? UILabel }.contains { $0.text == "367" })
        XCTAssertNotNil(descendants(window).first { $0.accessibilityIdentifier == BottomToast.accessibilityIdentifier })
        window.overrideUserInterfaceStyle = .dark
        try await Task.sleep(nanoseconds: 150_000_000)
        capture(window, name: "profile-followed-dark")
    }

    private func capture(_ window: UIWindow, name: String) {
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { window.layer.render(in: $0.cgContext) }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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

private final class ProfileFollowSubmitterStub: UserFollowSubmitting, @unchecked Sendable {
    var paths: [String] = []
    func submit(apiPath: String, bodyJSON: String, referer: URL) async throws {
        paths.append(apiPath)
        // 留出时间检查请求中的按钮样式
        try await Task.sleep(nanoseconds: 400_000_000)
    }
}
