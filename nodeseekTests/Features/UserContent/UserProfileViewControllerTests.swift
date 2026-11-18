import AsyncDisplayKit
import JXPhotoBrowser
import UIKit
import XCTest
@testable import nodeseek

@MainActor
final class UserProfileViewControllerTests: XCTestCase {
    func testGroupedCommentButtonsOpenTheirOwnFloor() throws {
        let records = [30, 10, 1].map {
            UserCommentRecord(postID: 1, title: "同一标题下的多条回复", rank: 0, floorID: $0, text: "回复 \($0)")
        }
        var opened: [UserCommentRecord] = []
        let node = UserCommentGroupCellNode(group: try XCTUnwrap(UserCommentGroup.grouped(records).first), traits: UITraitCollection(userInterfaceStyle: .dark)) {
            opened.append($0)
        }
        let layout = node.layoutThatFits(ASSizeRange(
            min: CGSize(width: 320, height: 0),
            max: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
        ))
        node.frame = CGRect(origin: .zero, size: layout.size)
        _ = node.view
        node.layoutIfNeeded()
        func allNodes(_ root: ASDisplayNode) -> [ASDisplayNode] {
            [root] + (root.subnodes ?? []).flatMap { allNodes($0) }
        }
        let texts = allNodes(node).compactMap { $0 as? ASTextNode }
        let titleColor = try XCTUnwrap(texts.first?.attributedText?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor)
        XCTAssertEqual(titleColor, ReadingColors.text.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)))
        let buttons = allNodes(node).compactMap { $0 as? ASButtonNode }
        XCTAssertEqual(buttons.count, 3)
        for button in buttons {
            _ = button.view
            button.sendActions(forControlEvents: .touchUpInside, with: nil)
            XCTAssertGreaterThanOrEqual(button.calculatedSize.width, 44)
            XCTAssertGreaterThanOrEqual(button.calculatedSize.height, 44)
        }
        XCTAssertEqual(opened, records)
        XCTAssertEqual(opened.map(\.commentPage), [3, 1, 1])
        XCTAssertEqual(opened.map(\.anchorID), ["30", "10", "1"])
    }

    func testGroupedCommentsPreview() async throws {
        let rows: [[String: Any]] = [
            ["post_id": 1, "title": "给 NS Connect 加了个查看探针的功能", "rank": 0, "floor_id": 30, "text": "@sequoia 谢谢反馈，新版本已经支持了。"],
            ["post_id": 1, "title": "给 NS Connect 加了个查看探针的功能", "rank": 0, "floor_id": 28, "text": "@Olqynnarion 可以点击右下角页码，直接跳到想看的那一页。"],
            ["post_id": 1, "title": "给 NS Connect 加了个查看探针的功能", "rank": 0, "floor_id": 25, "text": "@chrimast 暗黑模式也适配好了，欢迎试用。"],
            ["post_id": 1, "title": "给 NS Connect 加了个查看探针的功能", "rank": 0, "floor_id": 22, "text": "探针支持加入底部导航，在设置里就能调整。"],
            ["post_id": 2, "title": "用 Codex 开发长线任务，怎么做比较优雅", "rank": 0, "floor_id": 8, "text": "可以试试任务看板，把需求和验收放在一起。"],
            ["post_id": 2, "title": "用 Codex 开发长线任务，怎么做比较优雅", "rank": 0, "floor_id": 5, "text": "我一般先拆小任务，每完成一步就跑一次验证。"],
            ["post_id": 3, "title": "2000–3000 买个什么手机好", "rank": 0, "floor_id": 12, "text": "主要看续航和屏幕，建议先去店里试一下。"]
        ]
        MockProfileURLProtocol.requestedPages = []
        MockProfileURLProtocol.responseData = try JSONSerialization.data(withJSONObject: ["success": true, "comments": rows])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockProfileURLProtocol.self]
        let controller = UserCommentsViewController(uid: 31037, client: NodeSeekUserContentClient(session: URLSession(configuration: configuration)))
        let navigation = UINavigationController(rootViewController: controller)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        controller.loadViewIfNeeded()
        try await Task.sleep(nanoseconds: 1_500_000_000)
        let table = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UITableView }.first)
        XCTAssertEqual(table.numberOfRows(inSection: 0), 3)
        // 分组后首屏较短，也不应在用户阅读前连续分页刷新。
        XCTAssertEqual(MockProfileURLProtocol.requestedPages, ["1"])
        let probeTable = ASTableNode()
        XCTAssertFalse(controller.shouldBatchFetch(for: probeTable))
        controller.scrollViewWillBeginDragging(table)
        XCTAssertTrue(controller.shouldBatchFetch(for: probeTable))
        for (name, style) in [("comments-grouped-light", UIUserInterfaceStyle.light), ("comments-grouped-dark", .dark)] {
            window.overrideUserInterfaceStyle = style
            window.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 300_000_000)
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try XCTUnwrap(image.pngData()).write(to: directory.appendingPathComponent(name + ".png"))
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let nextRows: [[String: Any]] = [
            ["post_id": 1, "title": "给 NS Connect 加了个查看探针的功能", "rank": 0, "floor_id": 10, "text": "跨页追加的回复"],
            ["post_id": 4, "title": "下一页主题", "rank": 0, "floor_id": 1, "text": "新主题回复"]
        ]
        MockProfileURLProtocol.responseData = try JSONSerialization.data(withJSONObject: ["success": true, "comments": nextRows])
        controller.tableNode(probeTable, willBeginBatchFetchWith: ASBatchContext())
        for _ in 0..<50 where table.numberOfRows(inSection: 0) != 4 {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(table.numberOfRows(inSection: 0), 4)
        XCTAssertTrue(MockProfileURLProtocol.requestedPages.contains("2"))
    }

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
    static var requestedPages: [String] = []

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let url = request.url, url.path == "/api/content/list-comments",
           let page = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "page" })?.value {
            Self.requestedPages.append(page)
        }
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
