import AsyncDisplayKit
import UIKit
import XCTest
@testable import nodeseek

@MainActor
final class DetailImagePlaceholderTests: XCTestCase {
    func testBlockKeepsGrayPlaceholderUntilImageCanFit() throws {
        let block = DetailImageBlockView(
            imageBlock: RenderedImageBlock(url: try DetailWebPTestFixture.url(), altText: nil), imageKind: .normal,
            onImageLoaded: { _, _ in }, onImageTapped: {}
        )
        block.frame = CGRect(x: 0, y: 0, width: 160, height: 20)
        block.layoutIfNeeded()
        let placeholder = try XCTUnwrap(block.subviews.compactMap { $0 as? DetailImagePlaceholderView }.first)
        XCTAssertFalse(placeholder.isHidden)
        XCTAssertEqual(placeholder.frame, block.bounds)
        XCTAssertFalse(placeholder.hasFailed)
        let image = try XCTUnwrap(ImageRenderer.downsampledImage(data: DetailWebPTestFixture.data(), maxPixelSize: 160))
        block.applyLoadedImage(DetailInlineImageResult(image: image, resolvedKind: nil, originalSize: CGSize(width: 640, height: 640)))
        block.layoutIfNeeded()
        XCTAssertFalse(placeholder.isHidden, "图片等行高到位时也要保留灰底")
        block.frame.size.height = 160
        block.setNeedsLayout()
        block.layoutIfNeeded()
        XCTAssertTrue(placeholder.isHidden)
    }

    func testFailedBlockAndInlineAttachmentBecomeCompactWithoutReloadLoop() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("broken-\(UUID()).webp")
        try Data("<!doctype html><html>expired image host</html>".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let controller = DetailImageFailureFixtureController(url: url)
        window.rootViewController = controller
        window.windowLevel = .normal + 1
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await waitFor {
            let placeholders = self.descendants(of: controller.view, type: DetailImagePlaceholderView.self)
            return placeholders.count == 2 && placeholders.allSatisfy { $0.hasFailed && !$0.isHidden }
        }
        // 等附件重建和 Texture 行高回流，确保不会因失败触发反复下载和重排。
        try await Task.sleep(nanoseconds: 400_000_000)
        let placeholders = descendants(of: controller.view, type: DetailImagePlaceholderView.self)
        XCTAssertEqual(placeholders.count, 2)
        XCTAssertTrue(placeholders.allSatisfy { $0.hasFailed && !$0.isHidden })
        XCTAssertEqual(controller.imageSizesReported, 0, "失败不能以 8×8 兜底图污染原图尺寸缓存")
        XCTAssertEqual(controller.block.calculatedSize.height, 44, accuracy: 1)
        XCTAssertLessThan(controller.richText.calculatedSize.height, 120)
        XCTAssertEqual(controller.table.view.rectForRow(at: IndexPath(row: 0, section: 0)).height, 68, accuracy: 1)
        XCTAssertLessThan(controller.table.view.rectForRow(at: IndexPath(row: 1, section: 0)).height, 144)
        let invalidations = controller.invalidations
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(controller.invalidations, invalidations)
        for style in [UIUserInterfaceStyle.light, .dark] {
            window.overrideUserInterfaceStyle = style
            controller.view.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 100_000_000)
            let screenshot = XCTAttachment(image: UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            })
            screenshot.name = "Detail-image-failure-\(style == .light ? "light" : "dark")"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    private func descendants<T: UIView>(of view: UIView, type: T.Type) -> [T] {
        view.subviews.flatMap { child in
            (child as? T).map { [$0] } ?? descendants(of: child, type: type)
        }
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        let start = ProcessInfo.processInfo.systemUptime
        while !condition() {
            if ProcessInfo.processInfo.systemUptime - start > 5 {
                XCTFail("等待图片失败占位超时")
                throw DetailOriginalFileError.unavailable
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}

@MainActor
private final class DetailImageFailureFixtureController: UIViewController, ASTableDataSource {
    let table = ASTableNode(style: .plain)
    private(set) var block: DetailImageBlockNode!
    private(set) var richText: DetailRichTextNode!
    private var rows: [ASCellNode] = []
    private(set) var imageSizesReported = 0
    private(set) var invalidations = 0

    init(url: URL) {
        super.init(nibName: nil, bundle: nil)
        block = DetailImageBlockNode(
            imageBlock: RenderedImageBlock(url: url, altText: nil), imageURLs: [url], imageIndex: 0,
            initialImageSize: CGSize(width: 640, height: 640), onImageTapped: { _, _ in },
            onImageSizeResolved: { [weak self] _, _ in self?.imageSizesReported += 1 },
            onLayoutInvalidated: { [weak self] in self?.relayout() }
        )
        let blocks = DTCoreTextHTMLContentRenderer().renderTextBlocks(
            fragment: "<p>我也试试<img src='\(url.absoluteString)'></p>", baseURL: NodeSeekSite.baseURL, maxImageWidth: 320
        )
        let text = NSMutableAttributedString(string: "")
        for case .text(let value) in blocks { text.append(value) }
        richText = DetailRichTextNode(
            attributedText: text, imageSizeProvider: { _ in CGSize(width: 640, height: 640) },
            onImageSizeResolved: { [weak self] _, _ in self?.imageSizesReported += 1 },
            onImageTapped: { _, _ in }, onLayoutInvalidated: { [weak self] in self?.relayout() }
        )
        for node in [block!, richText!] as [ASDisplayNode] {
            let cell = ASCellNode()
            cell.automaticallyManagesSubnodes = true
            cell.layoutSpecBlock = { _, _ in
                ASInsetLayoutSpec(insets: UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16), child: node)
            }
            rows.append(cell)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        table.dataSource = self
        view.addSubview(table.view)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        table.frame = view.bounds.inset(by: view.safeAreaInsets)
    }

    private func relayout() {
        invalidations += 1
        table.performBatch(animated: false, updates: { self.table.relayoutItems() })
    }
    func tableNode(_ tableNode: ASTableNode, numberOfRowsInSection section: Int) -> Int { rows.count }
    func tableNode(_ tableNode: ASTableNode, nodeBlockForRowAt indexPath: IndexPath) -> ASCellNodeBlock {
        let row = rows[indexPath.row]
        return { row }
    }
}
