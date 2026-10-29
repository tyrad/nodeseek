//
//  MarkdownEditorStyler.swift
//  nodeseek
//

import UIKit

/// 把 `MarkdownEditorHighlighter` 的结果画到 UITextView 上：只改字体和颜色，不改文字和选区；只有标题略微放大。
enum MarkdownEditorStyler {
    static func baseFont(compatibleWith traits: UITraitCollection? = nil) -> UIFont {
        UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits)
    }

    static func baseAttributes(compatibleWith traits: UITraitCollection? = nil) -> [NSAttributedString.Key: Any] {
        [.font: baseFont(compatibleWith: traits), .foregroundColor: UIColor.label]
    }

    static func apply(to textView: UITextView) {
        // 拼音等输入法组字中改属性会打断组字，选完字后再着色。
        guard textView.markedTextRange == nil else { return }

        let storage = textView.textStorage
        let fullRange = NSRange(location: 0, length: storage.length)
        let base = baseAttributes(compatibleWith: textView.traitCollection)
        let font = base[.font] as? UIFont ?? baseFont()

        storage.beginEditing()
        storage.setAttributes(base, range: fullRange)
        for highlight in MarkdownEditorHighlighter.highlights(in: storage.string)
        where NSMaxRange(highlight.range) <= storage.length {
            storage.addAttributes(attributes(for: highlight.style, baseFont: font), range: highlight.range)
        }
        storage.endEditing()
        textView.typingAttributes = base
    }

    private static func attributes(for style: MarkdownEditorStyle, baseFont: UIFont) -> [NSAttributedString.Key: Any] {
        switch style {
        case .marker:
            // 三级灰在暗黑模式下几乎看不清，标记用二级灰：清楚可见又比正文浅。
            return [.foregroundColor: UIColor.secondaryLabel]
        case .heading:
            let font = baseFont.withTraits(.traitBold)
            return [.font: font.withSize(round(font.pointSize * 1.1))]
        case .bold:
            return [.font: baseFont.withTraits(.traitBold)]
        case .italic:
            return [.font: baseFont.withTraits(.traitItalic)]
        case .strikethrough:
            return [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: UIColor.secondaryLabel]
        case .inlineCode, .codeBlock:
            return [
                .font: UIFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.92, weight: .regular),
                .backgroundColor: UIColor.secondarySystemFill
            ]
        case .quote:
            return [.foregroundColor: UIColor.secondaryLabel]
        case .link:
            return [.underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: UIColor.secondaryLabel]
        case .image:
            return [.foregroundColor: UIColor.tertiaryLabel]
        }
    }
}

private extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(traits)) else {
            return self
        }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
