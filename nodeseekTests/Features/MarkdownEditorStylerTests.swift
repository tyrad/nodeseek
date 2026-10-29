import UIKit
import XCTest
@testable import nodeseek

@MainActor
final class MarkdownEditorStylerTests: XCTestCase {
    private let sample = """
    让 ai 自己搞就是了
    ![image](https://cdn.nodeimage.com/i/OEux5ISMOQPUdCcQNY2ROsRqSH6anPXL.png)

    [站点链接](https://www.nodeseek.com/post-123-1)
    > 引用中也有 [链接](https://example.com) 和 `code`
    **粗体**、*斜体*、~~删除线~~
    ```
    curl https://example.com
    ```
    """

    func testEverySyntaxColorIsReadableInBothThemes() throws {
        let textView = UITextView()
        textView.text = sample
        MarkdownEditorStyler.apply(to: textView)

        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let background = rgba(.systemBackground, traits: traits)
            textView.textStorage.enumerateAttributes(in: NSRange(location: 0, length: textView.textStorage.length)) { attributes, range, _ in
                let color = attributes[.foregroundColor] as? UIColor ?? .label
                let fill = attributes[.backgroundColor] as? UIColor ?? .clear
                let surface = composite(rgba(fill, traits: traits), over: background)
                let foreground = composite(rgba(color, traits: traits), over: surface)
                let ratio = contrast(foreground, surface)
                let text = (sample as NSString).substring(with: range)
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(style): \(text) 对比度仅 \(ratio)")
            }
        }
    }

    func testRestylingPreservesTextSelectionAndPlainTyping() {
        let textView = UITextView()
        textView.text = sample
        let selection = (sample as NSString).range(of: "OEux5ISMOQPUdCcQNY2ROsRqSH6anPXL")
        textView.selectedRange = selection

        MarkdownEditorStyler.apply(to: textView)
        MarkdownEditorStyler.apply(to: textView)

        XCTAssertEqual(textView.text, sample)
        XCTAssertEqual(textView.selectedRange, selection)
        XCTAssertNil(textView.typingAttributes[.underlineStyle])
        XCTAssertNil(textView.typingAttributes[.backgroundColor])
        XCTAssertNil(textView.typingAttributes[.strikethroughStyle])
    }

    func testCommentEditorAppearanceAndThemeSwitch() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let presenter = ReadabilityPresenter()
        let editor = NewDiscussionViewController(presenter: presenter)
        let navigation = UINavigationController(rootViewController: editor)
        window.rootViewController = navigation
        editor.loadViewIfNeeded()
        editor.fill(NewDiscussionDraft(title: "", content: sample, category: nil, rank: .everyone, updatedAt: Date()))
        editor.render(presenter.state)
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }

        let body = try XCTUnwrap(findBody(in: editor.view))
        let status = try XCTUnwrap(findLabel("未修改", in: editor.view))
        for size in [UIContentSizeCategory.large, .extraExtraExtraLarge] {
            navigation.setOverrideTraitCollection(UITraitCollection(preferredContentSizeCategory: size), forChild: editor)
            for style in [UIUserInterfaceStyle.light, .dark] {
                window.overrideUserInterfaceStyle = style
                window.layoutIfNeeded()
                try await Task.sleep(nanoseconds: 250_000_000)
                XCTAssertEqual(body.text, sample)
                let traits = body.traitCollection
                let surface = rgba(.systemBackground, traits: traits)
                let foreground = composite(rgba(try XCTUnwrap(status.textColor), traits: traits), over: surface)
                XCTAssertGreaterThanOrEqual(contrast(foreground, surface), 4.5)
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "comment-editor-\(style.rawValue)-\(size.rawValue)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }

        body.becomeFirstResponder()
        try await Task.sleep(nanoseconds: 300_000_000)
        body.selectedRange = NSRange(location: body.textStorage.length, length: 0)
        body.insertText("\n补充文字")
        XCTAssertTrue(body.text.hasSuffix("\n补充文字"))
        window.endEditing(true)
        try await Task.sleep(nanoseconds: 300_000_000)
    }

    private func findBody(in view: UIView) -> UITextView? {
        if view.accessibilityIdentifier == "new-discussion-body" { return view as? UITextView }
        return view.subviews.lazy.compactMap { self.findBody(in: $0) }.first
    }

    private func findLabel(_ text: String, in view: UIView) -> UILabel? {
        if let label = view as? UILabel, label.text == text { return label }
        return view.subviews.lazy.compactMap { self.findLabel(text, in: $0) }.first
    }

    private func rgba(_ color: UIColor, traits: UITraitCollection) -> [CGFloat] {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return [red, green, blue, alpha]
    }

    private func composite(_ foreground: [CGFloat], over background: [CGFloat]) -> [CGFloat] {
        (0..<3).map { foreground[$0] * foreground[3] + background[$0] * (1 - foreground[3]) } + [1]
    }

    private func contrast(_ first: [CGFloat], _ second: [CGFloat]) -> CGFloat {
        func luminance(_ color: [CGFloat]) -> CGFloat {
            let linear = color.prefix(3).map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
        }
        let values = [luminance(first), luminance(second)]
        return (values.max()! + 0.05) / (values.min()! + 0.05)
    }
}

private final class ReadabilityPresenter: NewDiscussionPresenterProtocol {
    let state = NewDiscussionViewState(
        isEditing: true, editingCommentFloor: 5, category: nil, rank: .everyone,
        userLevel: .loaded(1), pendingDraft: nil, saveStatus: .unchanged, canPublish: false, isSubmitting: false
    )
    var rankOptions: [DiscussionReadRank] { [.everyone] }
    func viewDidLoad() {}
    func retryLoadingUserLevel() {}
    func didChangeTitle(_ title: String) {}
    func didChangeContent(_ content: String) {}
    func didSelectCategory(_ category: DiscussionCategory) {}
    func didSelectRank(_ rank: DiscussionReadRank) {}
    func didChangeUploadingImageCount(_ count: Int) {}
    func restorePendingDraft() {}
    func discardPendingDraft() {}
    func closeDecision() -> NewDiscussionCloseDecision { .close }
    func close(savingDraft: Bool) {}
    func closeKeepingPendingDraft() {}
    func didTapPublish() {}
    func didTapOpenWebFallback() {}
}
