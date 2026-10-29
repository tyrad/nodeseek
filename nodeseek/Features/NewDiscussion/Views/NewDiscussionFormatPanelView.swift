//
//  NewDiscussionFormatPanelView.swift
//  nodeseek
//

import UIKit

/// Aa 格式面板，替换键盘显示。所有按钮只在选区两侧插入 Markdown 语法。
final class NewDiscussionFormatPanelView: UIInputView {
    var onSelect: ((MarkdownSnippet) -> Void)?

    private var blockButtons: [MarkdownBlockStyle: UIButton] = [:]
    /// 由页面按打字键盘的高度设置，切换时工具条位置不变。
    private(set) lazy var heightConstraint = heightAnchor.constraint(equalToConstant: 300)

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 300), inputViewStyle: .keyboard)
        allowsSelfSizing = true
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setCurrentBlockStyle(_ style: MarkdownBlockStyle) {
        for (candidate, button) in blockButtons {
            button.isSelected = candidate == style
        }
    }

    private func setupUI() {
        backgroundColor = .secondarySystemBackground
        heightConstraint.isActive = true

        let paragraphButton = makeButton(title: "正文", snippet: .paragraph)
        let headingButton = makeButton(title: "标题", snippet: .heading)
        let codeBlockButton = makeButton(title: "代码块", font: .monospacedSystemFont(ofSize: 13, weight: .regular), snippet: .codeBlock)
        let quoteButton = makeButton(title: "引用", snippet: .quote)
        blockButtons = [.paragraph: paragraphButton, .heading: headingButton, .codeBlock: codeBlockButton, .quote: quoteButton]
        let blockRow = makeRow([paragraphButton, headingButton, codeBlockButton, quoteButton])

        let inlineRow = makeRow([
            makeButton(title: "B", font: .systemFont(ofSize: 17, weight: .heavy), snippet: .bold, accessibility: "粗体"),
            makeButton(title: "I", font: .italicSystemFont(ofSize: 17), snippet: .italic, accessibility: "斜体"),
            makeButton(title: "S", font: .systemFont(ofSize: 17), snippet: .strikethrough, accessibility: "删除线", strikethrough: true),
            makeButton(title: "`code`", font: .monospacedSystemFont(ofSize: 13, weight: .regular), snippet: .inlineCode, accessibility: "行内代码")
        ])
        let listRow = makeRow([
            makeButton(title: "• 无序列表", snippet: .unorderedList),
            makeButton(title: "1. 有序列表", snippet: .orderedList)
        ])
        let insertRow = makeRow([
            makeButton(title: "表格", snippet: .table),
            makeButton(title: "分割线", snippet: .horizontalRule)
        ])

        let stack = UIStackView(arrangedSubviews: [blockRow, inlineRow, listRow, insertRow])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14)
        ])
    }

    /// 一行等宽的分段按钮，外观接近系统分段控件。
    private func makeRow(_ buttons: [UIButton]) -> UIView {
        let row = UIStackView(arrangedSubviews: buttons)
        row.distribution = .fillEqually
        row.spacing = 1
        row.backgroundColor = .separator
        row.layer.cornerRadius = 12
        row.layer.cornerCurve = .continuous
        row.clipsToBounds = true
        row.heightAnchor.constraint(equalToConstant: 46).isActive = true
        return row
    }

    private func makeButton(
        title: String,
        font: UIFont? = nil,
        snippet: MarkdownSnippet,
        accessibility: String? = nil,
        strikethrough: Bool = false
    ) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        var attributes = AttributeContainer()
        attributes.font = font ?? .preferredFont(forTextStyle: .subheadline)
        if strikethrough {
            attributes.strikethroughStyle = .single
        }
        configuration.attributedTitle = AttributedString(title, attributes: attributes)
        configuration.background.cornerRadius = 0

        let button = UIButton(configuration: configuration)
        button.configurationUpdateHandler = { button in
            var updated = button.configuration
            updated?.baseForegroundColor = button.isSelected ? .systemBackground : .label
            updated?.background.backgroundColor = button.isSelected ? .label : .tertiarySystemBackground
            button.configuration = updated
        }
        button.accessibilityLabel = accessibility ?? title
        button.addAction(UIAction { [weak self] _ in self?.onSelect?(snippet) }, for: .touchUpInside)
        return button
    }
}
