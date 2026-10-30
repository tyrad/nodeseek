//
//  UserProfileReadmeView.swift
//  nodeseek
//
//  Created by Claude on 2026/10/30.
//

import Kingfisher
import UIKit

/// 个人页自述：Markdown 先转成站点同款 HTML，再走详情页的 DTCoreText 渲染，最后用 UIKit 排版。
/// 自述通常很短，只覆盖文字、引用、代码块和图片；表格按纯文本显示。
@MainActor
final class UserProfileReadmeView: UIView, UITextViewDelegate {
    private enum Layout {
        static let contentInsets = NSDirectionalEdgeInsets(top: 13, leading: 16, bottom: 15, trailing: 16)
        static let blockSpacing: CGFloat = 10
        static let maxImageHeight: CGFloat = 320
    }

    private let markdown: String
    private let stack = UIStackView()
    private var renderedStyle: UIUserInterfaceStyle?
    private var renderedWidth: CGFloat = 0
    var onOpenURL: ((URL) -> Void)?

    init(markdown: String) {
        self.markdown = markdown
        super.init(frame: .zero)
        stack.axis = .vertical
        stack.spacing = Layout.blockSpacing
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = Layout.contentInsets
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        renderIfNeeded()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // 富文本颜色在渲染时就固定了，深浅色切换要重新渲染
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
        renderedStyle = nil
        setNeedsLayout()
    }

    private func renderIfNeeded() {
        let width = bounds.width - Layout.contentInsets.leading - Layout.contentInsets.trailing
        guard window != nil, width > 0 else { return }
        guard renderedStyle != traitCollection.userInterfaceStyle || abs(renderedWidth - width) > 1 else { return }
        renderedStyle = traitCollection.userInterfaceStyle
        renderedWidth = width

        var blocks: [RenderedContentBlock] = []
        traitCollection.performAsCurrent {
            let html = MarkdownPreviewHTMLRenderer.html(from: markdown)
            blocks = DTCoreTextHTMLContentRenderer().render(
                fragment: html,
                baseURL: NodeSeekSite.baseURL,
                maxImageWidth: width
            )
        }

        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        let views = blocks.compactMap(makeView)
        if views.isEmpty {
            // 渲染不出内容时退回原文，至少不丢信息
            stack.addArrangedSubview(makeTextView(NSAttributedString(
                string: markdown,
                attributes: [.font: UIFont.systemFont(ofSize: 15), .foregroundColor: UIColor.label]
            )))
        } else {
            views.forEach(stack.addArrangedSubview)
        }
        invalidateIntrinsicContentSize()
    }

    private func makeView(for block: RenderedContentBlock) -> UIView? {
        switch block {
        case .text(let text):
            let trimmed = text.string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : makeTextView(Self.uiKitText(from: text))
        case .quote(let quote):
            return makeQuoteView(quote.children)
        case .codeBlock(let code):
            return makeCodeView(code.text)
        case .image(let image):
            return makeImageView(image.url)
        case .table(let table):
            let text = table.rows
                .map { $0.cells.map(\.text).joined(separator: "  ") }
                .joined(separator: "\n")
            return makeCodeView(text)
        case .vote, .terminal, .tabs, .iframeLink, .imagePlaceholder, .unsupported:
            return nil
        }
    }

    private func makeTextView(_ text: NSAttributedString) -> UITextView {
        let textView = UITextView()
        textView.attributedText = text
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.linkTextAttributes = [.foregroundColor: NodeSeekLinkStyle.color]
        textView.delegate = self
        return textView
    }

    /// DTCoreText 的段落样式和取色属性在 UITextView 里表现异常（段间距被放大、链接变黑），
    /// 这里只保留字体、颜色、链接和缩进，重建成系统属性。
    private static func uiKitText(from text: NSAttributedString) -> NSAttributedString {
        let source = NSMutableAttributedString(attributedString: text)
        while source.string.hasSuffix("\n") {
            source.deleteCharacters(in: NSRange(location: source.length - 1, length: 1))
        }
        let result = NSMutableAttributedString(string: source.string)
        source.enumerateAttributes(in: NSRange(location: 0, length: source.length)) { attributes, range, _ in
            var clean: [NSAttributedString.Key: Any] = [:]
            clean[.font] = attributes[.font] ?? UIFont.systemFont(ofSize: 15)
            // 标题保持黑白主题，不用站点绿
            let isHeading = attributes[NSAttributedString.Key("DTHeaderLevel")] != nil
            clean[.foregroundColor] = isHeading ? UIColor.label : (attributes[.foregroundColor] ?? UIColor.label)
            if let link = attributes[.link] {
                clean[.link] = link
            }
            if let original = attributes[.paragraphStyle] as? NSParagraphStyle {
                let style = NSMutableParagraphStyle()
                style.lineSpacing = 3
                style.paragraphSpacing = min(original.paragraphSpacing, 8)
                style.paragraphSpacingBefore = isHeading ? 4 : 0
                style.headIndent = original.headIndent
                style.firstLineHeadIndent = original.firstLineHeadIndent
                style.tabStops = original.tabStops
                style.defaultTabInterval = original.defaultTabInterval
                clean[.paragraphStyle] = style
            }
            result.setAttributes(clean, range: range)
        }
        return result
    }

    private func makeQuoteView(_ children: [RenderedContentBlock]) -> UIView? {
        let childViews = children.compactMap(makeView)
        guard !childViews.isEmpty else { return nil }
        let content = UIStackView(arrangedSubviews: childViews)
        content.axis = .vertical
        content.spacing = 6
        content.alpha = 0.75

        let bar = UIView()
        bar.backgroundColor = .separator
        bar.layer.cornerRadius = 1.5
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.widthAnchor.constraint(equalToConstant: 3).isActive = true

        let row = UIStackView(arrangedSubviews: [bar, content])
        row.axis = .horizontal
        row.spacing = 10
        return row
    }

    private func makeCodeView(_ code: String) -> UIView? {
        let text = code.trimmingCharacters(in: .newlines)
        guard !text.isEmpty else { return nil }
        let label = UILabel()
        label.text = text
        label.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        label.textColor = .label
        label.numberOfLines = 0

        let container = UIView()
        container.backgroundColor = .tertiarySystemFill
        container.layer.cornerRadius = 8
        container.layer.cornerCurve = .continuous
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])
        return container
    }

    private func makeImageView(_ url: URL) -> UIView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 6
        imageView.backgroundColor = .tertiarySystemFill
        let height = imageView.heightAnchor.constraint(equalToConstant: 120)
        height.isActive = true
        imageView.kf.setImage(with: url) { [weak self, weak imageView] result in
            guard let self, let imageView, case .success(let value) = result else { return }
            let size = value.image.size
            guard size.width > 0, size.height > 0 else { return }
            imageView.backgroundColor = .clear
            height.constant = min(renderedWidth * size.height / size.width, Layout.maxImageHeight)
            invalidateIntrinsicContentSize()
        }
        return imageView
    }

    func textView(
        _ textView: UITextView,
        shouldInteractWith url: URL,
        in characterRange: NSRange,
        interaction: UITextItemInteraction
    ) -> Bool {
        guard interaction == .invokeDefaultAction, let onOpenURL else { return true }
        onOpenURL(url)
        return false
    }
}
