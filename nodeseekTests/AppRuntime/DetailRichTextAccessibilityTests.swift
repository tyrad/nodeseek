import DTCoreText
import ObjectiveC
import UIKit
import XCTest
@testable import nodeseek

@MainActor
final class DetailRichTextAccessibilityTests: XCTestCase {
    func testAttachmentAccessibilityUsesRealViewsAndPreservesTextAndLinks() throws {
        let view = try makeRichTextView()
        let elements = try XCTUnwrap(view.accessibilityElements)
        XCTAssertFalse(elements.isEmpty)
        XCTAssertFalse(elements.contains { object_getClass($0 as AnyObject) == DTAccessibilityViewProxy.self },
                       "辅助功能不能拿到伪装成 UIView 的附件代理")
        let image = try XCTUnwrap(elements.compactMap { $0 as? DetailInlineImageView }.first)
        XCTAssertTrue(image.superview === view)
        XCTAssertTrue(elements.contains { ($0 as? UIAccessibilityElement)?.accessibilityLabel?.contains("前文") == true })
        XCTAssertTrue(elements.contains { ($0 as? UIAccessibilityElement)?.accessibilityTraits.contains(.link) == true })
    }

    func testRemovedAttachmentsAreNotReturnedAndRecreatedViewsReplaceOldOnes() throws {
        let view = try makeRichTextView()
        let oldElements = try XCTUnwrap(view.accessibilityElements)
        view.removeAllCustomViews()
        let removed = try XCTUnwrap(view.accessibilityElements)
        XCTAssertFalse(removed.contains { object_getClass($0 as AnyObject) == DTAccessibilityViewProxy.self })
        XCTAssertFalse(removed.contains { $0 is DetailInlineImageView })

        view.layoutSubviews(in: .infinite)
        let newElements = try XCTUnwrap(view.accessibilityElements)
        let image = try XCTUnwrap(newElements.compactMap { $0 as? DetailInlineImageView }.first)
        XCTAssertFalse(oldElements.contains { ($0 as AnyObject) === image })
    }

    private func makeRichTextView() throws -> DetailRichTextView {
        let renderer = DTCoreTextHTMLContentRenderer()
        let blocks = renderer.renderTextBlocks(
            fragment: "<blockquote>前文<img src='file:///tmp/nodeseek-accessibility.png' width='24' height='24'>后文 <a href='https://example.com'>链接</a></blockquote>",
            baseURL: try XCTUnwrap(URL(string: "https://www.nodeseek.com")),
            maxImageWidth: 320
        )
        let text = NSMutableAttributedString(string: "")
        for case .text(let value) in blocks { text.append(value) }
        let view = DetailRichTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 160))
        view.configure(text, onImageTapped: nil, onLayoutInvalidated: nil)
        view.layoutSubviews(in: .infinite)
        return view
    }
}
