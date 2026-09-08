import AsyncDisplayKit
import CryptoKit
import UIKit
import WebKit
import XCTest
@testable import nodeseek

@MainActor
final class VoteIntegrationTests: XCTestCase {
    private let baseURL = URL(string: "https://www.nodeseek.com")!

    func testRendererAndFactoryRecognizeOriginalAndMountedVotes() throws {
        for html in [
            #"<p>之前</p><p><a href="javascript://void(0)" data-href="nsapp://vote?id=3108">nsapp://vote?id=3108</a></p><p>之后</p>"#,
            #"<p>之前</p><div class="vote-panel"><form><h2>套餐</h2><input id="vote-item-3108-14131"><p>nsapp://vote?id=3108 (公开投票)</p></form></div><p>之后</p>"#
        ] {
            let blocks = DTCoreTextHTMLContentRenderer().render(fragment: html, baseURL: baseURL)
            XCTAssertEqual(blocks.count, 3)
            guard case .vote(3108) = blocks[1] else { return XCTFail("缺少投票内容块") }
            let nodes = DetailContentBlockNodeFactory.makeNodes(from: blocks, onImageTapped: { _, _ in }, onLinkTapped: { _ in }, onTextLayoutInvalidated: {})
            XCTAssertTrue(nodes[1] is DetailVoteNode)
            XCTAssertEqual(CommentCopyTextFormatter.plainText(from: blocks).split(separator: "\n"), ["之前", "nsapp://vote?id=3108", "之后"])
        }
        let url = URL(string: "nsapp://vote?id=3108")!
        guard case .vote(3108) = PostDetailLinkResolver.destination(for: url, baseURL: baseURL) else {
            return XCTFail("投票链接不能跳转到外部 App")
        }
    }

    func testVotesInsideQuotesKeepTheirContainers() throws {
        let blocks = DTCoreTextHTMLContentRenderer().render(fragment: #"<blockquote><a href="nsapp://vote?id=3108">投票</a></blockquote>"#, baseURL: baseURL)
        guard case .quote(let quote) = blocks.first,
              case .vote(3108) = quote.children.first else { return XCTFail("投票不应破坏引用") }
    }

    func testVotesInsideTabsAndQuotesKeepTheirContainers() throws {
        let blocks = DTCoreTextHTMLContentRenderer().render(fragment: #"<div class="nsk-magic-tabs"><div class="nsk-magic-tab-title">投票</div><div class="nsk-magic-tab-body"><blockquote><a href="nsapp://vote?id=3108">投票</a></blockquote></div></div>"#, baseURL: baseURL)
        guard case .tabs(let tabs) = blocks.first,
              case .quote(let quote) = tabs.sections.first?.blocks.first,
              case .vote(3108) = quote.children.first else { return XCTFail("投票不应破坏分栏和引用") }
    }

    func testSignedSubmissionPreflightsAndSendsOnlySelectedIDs() async throws {
        let web = try await mockWebView()
        let result = try await web.callAsyncJavaScript(VoteAutomationScript.source, arguments: ["voteID": 3108, "operation": "submit", "ids": [14131], "timeoutMs": 1000], in: nil, contentWorld: .page) as? [String: Any]
        XCTAssertEqual(result?["ok"] as? Bool, true)
        let capturedValue = try await web.evaluateJavaScript("JSON.stringify(window.requests)")
        let captured = try XCTUnwrap(capturedValue as? String)
        let requests = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(captured.utf8)) as? [[String: String]])
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0]["method"], "GET")
        XCTAssertEqual(requests[1]["url"], "https://www.nodeseek.com/api/vote/voteforitem")
        XCTAssertEqual(requests[1]["body"], #"{"ids":[14131]}"#)
        for request in requests {
            let text = [request["method"]!, request["url"]!, request["userAgent"]!, request["body"]!].joined(separator: "\n\n")
            let expected = Insecure.SHA1.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(request["sign"], expected)
        }
    }

    func testScriptNeverPostsIfLockedAlreadyVotedOrInvalidSelection() async throws {
        for scenario in ["locked", "voted", "invalid"] {
            let web = try await mockWebView()
            if scenario != "invalid" {
                _ = try await web.evaluateJavaScript(scenario == "locked" ? "window.fixture.vote.locked=true" : "window.fixture.vote.items[0].voted=true")
            }
            let result = try await web.callAsyncJavaScript(VoteAutomationScript.source, arguments: ["voteID": 3108, "operation": "submit", "ids": scenario == "invalid" ? [999] : [14131], "timeoutMs": 1000], in: nil, contentWorld: .page) as? [String: Any]
            XCTAssertEqual(result?["ok"] as? Bool, false, scenario)
            let count = try await web.evaluateJavaScript("window.requests.filter(x=>x.method==='POST').length") as? Int
            XCTAssertEqual(count, 0, scenario)
        }
    }

    func testSubmissionNotificationDoesNotDuplicateResultRead() async throws {
        let service = VoteTestService()
        service.notifiesChanges = true
        let controller = VoteViewController(voteID: 3108, service: service)
        let window = makeWindow(controller: controller)
        defer { window.isHidden = true }
        let card = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? DetailVoteView }.first)
        await waitUntil { card.model.vote != nil }
        card.model.select(14131)
        await card.model.submit()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(service.loadCount, 2, "首次读取和提交后确认各一次，通知不应额外读取")
        XCTAssertEqual(card.model.vote?.hasVoted, true)
    }

    func testCardSelectionRequiresConfirmationWithoutUtilityButtons() async throws {
        let service = VoteTestService()
        let controller = UIViewController()
        controller.view.backgroundColor = .systemBackground
        let window = makeWindow(controller: controller)
        let card = DetailVoteView(id: 3108, service: service, onHeightChanged: { _ in })
        controller.view.addSubview(card)
        card.frame = CGRect(x: 16, y: 80, width: 358, height: 650)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        await waitUntil { card.model.vote != nil }
        let option = try XCTUnwrap(descendants(card).first { $0.accessibilityIdentifier == "vote-option-14131" } as? UIButton)
        option.sendActions(for: .touchUpInside)
        XCTAssertEqual(card.model.selected, [14131])
        XCTAssertFalse(descendants(card).contains { $0.accessibilityIdentifier == "vote-open-web" })
        XCTAssertFalse(descendants(card).contains { $0.accessibilityIdentifier == "vote-refresh" })
        let submit = try XCTUnwrap(descendants(card).first { $0.accessibilityIdentifier == "vote-submit" } as? UIButton)
        submit.sendActions(for: .touchUpInside)
        let alert = try XCTUnwrap(controller.presentedViewController as? UIAlertController)
        XCTAssertTrue(alert.message?.contains("plus") == true)
        XCTAssertTrue(alert.message?.contains("公开") == true)
        XCTAssertTrue(alert.message?.contains("不可修改") == true)
        XCTAssertEqual(alert.actions.map(\.title), ["取消", "提交"])
        XCTAssertTrue(service.submitted.isEmpty)
        controller.dismiss(animated: false)
    }

    func testVoteControllerMeasuresContentAndRendersBothThemes() async throws {
        let service = VoteTestService()
        let controller = VoteViewController(voteID: 3108, service: service)
        let navigation = UINavigationController(rootViewController: controller)
        let window = makeWindow(controller: navigation)
        defer { window.isHidden = true }
        let card = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? DetailVoteView }.first)
        await waitUntil { card.model.vote != nil }
        for style in [UIUserInterfaceStyle.light, .dark] {
            window.overrideUserInterfaceStyle = style
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            card.setNeedsLayout()
            card.layoutIfNeeded()
            controller.view.layoutIfNeeded()
            XCTAssertGreaterThan(card.bounds.height, 300)
            XCTAssertEqual(descendants(card).filter { $0.accessibilityIdentifier?.hasPrefix("vote-option-") == true }.count, 4)
            try saveSnapshot(window, name: style == .light ? "vote-light" : "vote-dark")
        }
        service.vote = VoteTestService.makeVote(voted: true)
        await card.model.refresh()
        card.layoutIfNeeded()
        controller.view.layoutIfNeeded()
        XCTAssertNil(descendants(card).first { $0.accessibilityIdentifier == "vote-submit" })
        XCTAssertTrue(descendants(card).compactMap { ($0 as? UILabel)?.text }.contains("12 票"))
        try saveSnapshot(window, name: "vote-results-dark")
    }

    func testInlineTextureNodeGrowsAndRefreshesAfterReturningFromWeb() async throws {
        let service = VoteTestService()
        let root = ASDisplayNode()
        root.automaticallyManagesSubnodes = true
        root.backgroundColor = .systemBackground
        let vote = DetailVoteNode(id: 3108, service: service, onLayoutInvalidated: { [weak root] in
            root?.setNeedsLayout()
        })
        root.layoutSpecBlock = { _, _ in
            let stack = ASStackLayoutSpec.vertical()
            stack.children = [vote]
            return ASInsetLayoutSpec(insets: UIEdgeInsets(top: 70, left: 16, bottom: 16, right: 16), child: stack)
        }
        let controller = ASDKViewController(node: root)
        let window = makeWindow(controller: controller)
        defer { window.isHidden = true }
        let card = try XCTUnwrap(vote.view as? DetailVoteView)
        await waitUntil { card.model.vote != nil }
        root.setNeedsLayout()
        root.layoutIfNeeded()
        card.layoutIfNeeded()
        root.layoutIfNeeded()
        XCTAssertGreaterThan(vote.calculatedSize.height, 300)
        XCTAssertLessThan(vote.calculatedSize.height, 600, "卡片不应拉伸填满剩余屏幕")
        try saveSnapshot(window, name: "vote-inline")

        // 网页中完成投票后，重新进入原生卡片必须重新读取状态。
        window.isHidden = true
        controller.view.removeFromSuperview()
        service.vote = VoteTestService.makeVote(voted: true)
        window.rootViewController = nil
        window.rootViewController = controller
        window.makeKeyAndVisible()
        await waitUntil { card.model.vote?.hasVoted == true }
        XCTAssertFalse(card.model.canSubmit)
    }

    func testAccessibilityTextSizeIncreasesCardHeight() async throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("字体环境覆盖需要 iOS 17") }
        let controller = VoteViewController(voteID: 3108, service: VoteTestService())
        let window = makeWindow(controller: controller)
        defer { window.isHidden = true }
        let card = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? DetailVoteView }.first)
        await waitUntil { card.model.vote != nil }
        card.layoutIfNeeded()
        controller.view.layoutIfNeeded()
        let height = card.bounds.height
        controller.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        controller.view.layoutIfNeeded()
        card.layoutIfNeeded()
        controller.view.layoutIfNeeded()
        XCTAssertGreaterThan(card.bounds.height, height)
        try saveSnapshot(window, name: "vote-large-text")
    }

    private func mockWebView() async throws -> WKWebView {
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        web.loadHTMLString("<html><body>Local vote fixture</body></html>", baseURL: baseURL)
        for _ in 0..<100 {
            if (try? await web.evaluateJavaScript("document.readyState === 'complete' && document.body?.textContent === 'Local vote fixture'")) as? Bool == true { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        _ = try await web.evaluateJavaScript(#"""
        window.requests=[];
        window.fixture={success:true,vote:{id:3108,title:"套餐",multiple:false,isPublic:true,locked:false,items:[{vote_item_id:14131,text:"plus",voted:false}]}};
        window.fetch=async (url,init)=>{
          window.requests.push({url,method:init.method,body:init.body||"",sign:init.headers["x-dynamic-sign"],userAgent:navigator.userAgent});
          return {ok:true,status:200,text:async()=>JSON.stringify(init.method==="GET"?window.fixture:{success:true})};
        };
        true;
        """#)
        return web
    }

    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }

    private func makeWindow(controller: UIViewController) -> UIWindow {
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
            window.frame = scene.coordinateSpace.bounds
        } else { window = UIWindow(frame: UIScreen.main.bounds) }
        window.windowLevel = .normal + 1
        window.rootViewController = controller
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        return window
    }

    private func waitUntil(_ predicate: () -> Bool) async {
        for _ in 0..<100 {
            if predicate() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("等待投票状态超时")
    }

    private func saveSnapshot(_ view: UIView, name: String) throws {
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image { _ in
            XCTAssertTrue(view.drawHierarchy(in: view.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/vote-ui")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try XCTUnwrap(image.pngData()).write(to: directory.appendingPathComponent(name + ".png"))
    }
}
