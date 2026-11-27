import UIKit
import XCTest
@testable import nodeseek

@MainActor
final class DetailPreviewMigrationTests: XCTestCase {
    func testDraftAndCommentPreviewUseSafeWidthAndKeepActions() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil }
        var published = 0
        var revealed = 0
        var opened = 0
        let draft = NewDiscussionDraft(title: "预览标题", content: String(repeating: "正文段落\n\n", count: 60))
        let editor = NewDiscussionPreviewViewController(draft: draft) { published += 1 }
        let comment = Comment(id: "7", authorName: "作者", avatarURL: nil, floorText: "#7",
                              createdAtText: nil, contentHTML: "<p>可见的回复</p>", signatureHTML: "<p>签名</p>",
                              isLikeClicked: true, chickenLegCount: 2, opposeCount: 1)
        let reply = LoadedCommentPreviewViewController(comment: comment, baseURL: NodeSeekSite.baseURL,
                                                      showsFullPostButton: true, onOpenFullPost: { opened += 1 },
                                                      onReveal: { revealed += 1 })
        for controller in [editor as UIViewController, reply] {
            let navigation = UINavigationController(rootViewController: controller)
            window.rootViewController = navigation
            window.makeKeyAndVisible()
            navigation.view.layoutIfNeeded()
            let preview = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? DetailFloorPreviewScrollView }.first)
            var previousBodyFont: CGFloat = 0
            for (style, category) in [(UIUserInterfaceStyle.light, UIContentSizeCategory.large),
                                      (.dark, .accessibilityExtraExtraLarge)] {
                controller.overrideUserInterfaceStyle = style
                navigation.setOverrideTraitCollection(UITraitCollection(preferredContentSizeCategory: category), forChild: controller)
                for _ in 0..<200 {
                    controller.view.layoutIfNeeded()
                    if let text = (preview.floor.body.arrangedSubviews.first as? DetailRichTextView)?.debugAttributedString,
                       text.length > 0, let font = text.attribute(.font, at: 0, effectiveRange: nil) as? UIFont,
                       font.pointSize > previousBodyFont, preview.contentSize.height > 0 { break }
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
                let text = try XCTUnwrap((preview.floor.body.arrangedSubviews.first as? DetailRichTextView)?.debugAttributedString)
                let bodyFont = try XCTUnwrap(text.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
                XCTAssertGreaterThan(bodyFont.pointSize, previousBodyFont)
                previousBodyFont = bodyFont.pointSize
                let safe = controller.view.safeAreaLayoutGuide.layoutFrame
                XCTAssertEqual(preview.frame.minX, safe.minX, accuracy: 1)
                XCTAssertEqual(preview.frame.maxX, safe.maxX, accuracy: 1)
                if controller === reply {
                    let buttons = try XCTUnwrap(preview.floor.stack.arrangedSubviews.compactMap { $0 as? UIScrollView }.last?
                        .subviews.compactMap { $0 as? UIStackView }.first?.arrangedSubviews.compactMap { $0 as? UIButton })
                    XCTAssertEqual(buttons.map(\.accessibilityValue), [nil, "2", "1"])
                    let like = try XCTUnwrap(buttons.first)
                    XCTAssertNil(like.title(for: .normal))
                    XCTAssertTrue(like.accessibilityTraits.contains(.selected))
                    XCTAssertTrue(buttons.allSatisfy { !$0.isUserInteractionEnabled && $0.accessibilityTraits.contains(.staticText) && $0.bounds.height > 0 })
                    let footer = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? UIStackView }.first)
                    XCTAssertEqual(footer.axis, category.isAccessibilityCategory ? .vertical : .horizontal)
                }
                if controller === editor { XCTAssertGreaterThan(preview.contentSize.height, preview.bounds.height) }
            }
            if controller === editor {
                let button = try XCTUnwrap(editor.navigationItem.rightBarButtonItem?.customView as? UIButton)
                button.sendActions(for: .touchUpInside)
            } else {
                let footer = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? UIStackView }.first)
                for button in footer.arrangedSubviews.compactMap({ $0 as? UIButton }) {
                    button.sendActions(for: .touchUpInside)
                }
            }
        }
        XCTAssertEqual(published, 1)
        XCTAssertEqual(opened, 1)
        XCTAssertEqual(revealed, 1)
    }

    func testWidthChangeDiscardsStaleBody() throws {
        let preview = DetailFloorPreviewScrollView(frame: CGRect(x: 0, y: 0, width: 390, height: 400))
        var completions: [DetailFloorPreviewScrollView.Delivery] = []
        preview.loadContent = { _, _, deliver in completions.append(deliver); return nil }
        preview.layoutIfNeeded()
        preview.frame.size.width = 320
        preview.setNeedsLayout()
        preview.layoutIfNeeded()
        XCTAssertEqual(completions.count, 2)
        try XCTUnwrap(completions.last)([.text(NSAttributedString(string: "窄屏正文"))])
        try XCTUnwrap(completions.first)([.text(NSAttributedString(string: "已过期的宽屏正文"))])
        XCTAssertEqual(preview.floor.body.arrangedSubviews.count, 1)
    }
}
