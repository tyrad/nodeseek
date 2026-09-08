import AsyncDisplayKit
import UIKit
import XCTest
@testable import nodeseek

@MainActor
final class VoteLayoutRegressionTests: XCTestCase {
    func testDelayedVoteExpandsRealPostBodyCellWithoutOverlappingFollowingContent() async throws {
        let service = VoteTestService()
        service.loadDelayNanoseconds = 350_000_000
        service.vote = NodeSeekVote(id: 3108, title: "Plus 截至北京时间 10：45 分（也就是发这贴的时间）是否重置了", multiple: false, isPublic: true, locked: false, items: [
            .init(vote_item_id: 14131, text: "没重置", voted: false, count: nil),
            .init(vote_item_id: 14132, text: "重置了", voted: false, count: nil),
            .init(vote_item_id: 14133, text: "Pro、Team 路过", voted: false, count: nil),
            .init(vote_item_id: 14134, text: "纯路过", voted: false, count: nil)
        ])
        let controller = try VoteTableFixtureController(service: service)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.windowLevel = .normal + 1
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        let card = try await waitForCard(in: controller)
        let loadingHeight = card.bounds.height
        await settle { card.model.vote != nil }
        // 仅等待真实列表回调和正常布局周期，不主动使 cell 或祖先缓存失效。
        try await Task.sleep(nanoseconds: 600_000_000)
        assertContentFits(card: card, controller: controller)
        XCTAssertGreaterThan(card.bounds.height, loadingHeight + 150)
        try snapshot(window, name: "vote-post-body-loaded")

        service.vote = VoteTestService.makeVote(voted: true)
        await card.model.refresh()
        try await Task.sleep(nanoseconds: 500_000_000)
        assertContentFits(card: card, controller: controller)
        window.overrideUserInterfaceStyle = .dark
        try snapshot(window, name: "vote-post-body-results-dark")

        if #available(iOS 17.0, *) {
            controller.traitOverrides.preferredContentSizeCategory = .accessibilityExtraLarge
            try await Task.sleep(nanoseconds: 500_000_000)
            assertContentFits(card: card, controller: controller)
        }
    }

    private func assertContentFits(card: DetailVoteView, controller: VoteTableFixtureController, file: StaticString = #filePath, line: UInt = #line) {
        guard let stack = card.subviews.compactMap({ $0 as? UIStackView }).first,
              let lastContent = stack.arrangedSubviews.last else {
            return XCTFail("投票卡片缺少内容", file: file, line: line)
        }
        let lastControlBottom = card.convert(lastContent.bounds, from: lastContent).maxY
        XCTAssertGreaterThanOrEqual(card.bounds.height, lastControlBottom + 11, "投票背景必须包含全部选项和按钮", file: file, line: line)
        guard let cell = controller.table.nodeForRow(at: IndexPath(row: 0, section: 0)),
              let following = (cell.subnodes ?? []).compactMap({ $0 as? DetailRichTextNode }).first else {
            return XCTFail("真实正文缺少投票后的文字", file: file, line: line)
        }
        let contentBottom = cell.view.convert(CGPoint(x: 0, y: lastControlBottom), from: card).y
        XCTAssertGreaterThanOrEqual(following.frame.minY, contentBottom + 11, "投票后的正文不得与选项重叠", file: file, line: line)
        let followingImage = (cell.subnodes ?? []).compactMap { $0 as? DetailImageBlockNode }.first
        XCTAssertNotNil(followingImage, file: file, line: line)
        XCTAssertGreaterThan(followingImage?.frame.minY ?? 0, contentBottom, "后续图片不得覆盖投票", file: file, line: line)
        let nextRow = controller.table.view.rectForRow(at: IndexPath(row: 1, section: 0))
        let contentBottomInTable = controller.table.view.convert(CGPoint(x: 0, y: lastControlBottom), from: card).y
        XCTAssertGreaterThan(nextRow.minY, contentBottomInTable, "列表行高必须随投票内容增长", file: file, line: line)
    }

    private func waitForCard(in controller: VoteTableFixtureController) async throws -> DetailVoteView {
        await settle { self.descendants(controller.view).contains { $0 is DetailVoteView } }
        return try XCTUnwrap(descendants(controller.view).compactMap { $0 as? DetailVoteView }.first)
    }

    private func settle(_ done: () -> Bool) async {
        for _ in 0..<150 {
            if done() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("等待投票单元格超时")
    }

    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }

    private func snapshot(_ window: UIWindow, name: String) throws {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/vote-layout-regression")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try XCTUnwrap(image.pngData()).write(to: directory.appendingPathComponent(name + ".png"))
    }
}

@MainActor
private final class VoteTableFixtureController: UIViewController, ASTableDataSource, ASTableDelegate {
    let table = ASTableNode(style: .plain)
    private let service: NodeSeekVoteServing
    private let imageURL: URL
    private var refreshWork: DispatchWorkItem?

    init(service: NodeSeekVoteServing) throws {
        self.service = service
        self.imageURL = FileManager.default.temporaryDirectory.appendingPathComponent("vote-following-\(UUID().uuidString).png")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 120)).image { context in
            UIColor.secondarySystemBackground.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 320, height: 120))
            ("剩余用量\n5 小时    65%\n1 周        31%" as NSString).draw(at: CGPoint(x: 16, y: 12), withAttributes: [.font: UIFont.systemFont(ofSize: 18), .foregroundColor: UIColor.label])
        }
        try image.pngData()?.write(to: imageURL)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        table.dataSource = self
        table.delegate = self
        table.view.frame = view.bounds
        table.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(table.view)
    }

    func tableNode(_ tableNode: ASTableNode, numberOfRowsInSection section: Int) -> Int { 2 }

    func tableNode(_ tableNode: ASTableNode, nodeBlockForRowAt indexPath: IndexPath) -> ASCellNodeBlock {
        if indexPath.row == 1 {
            return {
                let cell = ASTextCellNode()
                cell.text = "后面的回帖"
                return cell
            }
        }
        let html = #"<p><a href="javascript://void(0)" data-href="nsapp://vote?id=3108">nsapp://vote?id=3108</a></p><p>难不成真的歧视 Plus？</p><p>截至为止，我的两个 Plus 还没重置</p>"#
        var blocks = DTCoreTextHTMLContentRenderer().render(fragment: html, baseURL: NodeSeekSite.baseURL)
        blocks.append(.image(.init(url: imageURL, altText: "剩余用量截图")))
        let content = PostDetailHeaderContent(postID: "917518", title: "统计下，截至目前为止，Plus 用户重置的分布", authorName: "CIYYYT", avatarURL: nil, metadataText: "4min ago · 日常", contentHTML: html)
        return { [weak self, service] in
            PostBodyCellNode(content: content, renderedContent: blocks, voteService: service, onImageTapped: { _, _ in }, onTextLayoutInvalidated: {
                self?.refreshWork?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    self?.table.relayoutItems()
                    self?.table.performBatch(animated: false, updates: {})
                }
                self?.refreshWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
            }, imageSizeProvider: { _ in CGSize(width: 320, height: 120) })
        }
    }
}
