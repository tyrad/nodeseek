//
//  NewDiscussionDraftStripView.swift
//  nodeseek
//

import UIKit

/// 标题上方的旧草稿细条：一行显示摘要，点开看正文前几行；丢弃后 3 秒内可撤销。
final class NewDiscussionDraftStripView: UIView {
    var onRestore: (() -> Void)?
    /// 撤销窗口结束后才真正丢弃。
    var onDiscard: (() -> Void)?

    private let iconView = UIImageView(image: UIImage(systemName: "doc.text"))
    private let titleLabel = UILabel()
    private let summaryLabel = UILabel()
    private let chevronView = UIImageView(image: UIImage(systemName: "chevron.down"))
    private let restoreButton = UIButton(type: .system)
    private let discardButton = UIButton(type: .system)
    private let previewLabel = UILabel()
    private let undoRow = UIStackView()
    private let mainRow = UIStackView()
    private var isExpanded = false
    private var discardTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(summary: String, preview: String) {
        summaryLabel.text = summary
        previewLabel.text = preview.isEmpty ? "（正文为空）" : preview
        cancelPendingDiscard()
        setExpanded(false, animated: false)
    }

    /// 关闭页面等场景下立即执行还在撤销窗口里的丢弃。
    func commitPendingDiscard() {
        guard discardTask != nil else { return }
        discardTask?.cancel()
        discardTask = nil
        onDiscard?()
    }

    // MARK: - 布局

    private func setupUI() {
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous

        let symbolConfiguration = UIImage.SymbolConfiguration(textStyle: .footnote, scale: .medium)
        iconView.preferredSymbolConfiguration = symbolConfiguration
        iconView.tintColor = .secondaryLabel
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        titleLabel.text = "上次的草稿"
        titleLabel.font = .preferredFont(forTextStyle: .footnote).withWeight(.semibold)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        summaryLabel.font = .preferredFont(forTextStyle: .footnote)
        summaryLabel.adjustsFontForContentSizeCategory = true
        summaryLabel.textColor = .secondaryLabel
        summaryLabel.lineBreakMode = .byTruncatingTail
        summaryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        chevronView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .caption2, scale: .small)
        chevronView.tintColor = .tertiaryLabel
        chevronView.setContentHuggingPriority(.required, for: .horizontal)

        var restoreConfiguration = UIButton.Configuration.plain()
        restoreConfiguration.cornerStyle = .capsule
        restoreConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12)
        restoreButton.configuration = restoreConfiguration
        // 和发布设置一样用 Assets 里的反色，避免半透明背景下系统动态色被调淡。
        restoreButton.configurationUpdateHandler = { button in
            var updated = button.configuration
            var attributes = AttributeContainer()
            attributes.font = UIFont.preferredFont(forTextStyle: .footnote).withWeight(.semibold)
            attributes.foregroundColor = UIColor(named: "InvertedLabel") ?? .systemBackground
            updated?.attributedTitle = AttributedString("恢复", attributes: attributes)
            updated?.background.backgroundColor = .label
            button.configuration = updated
        }
        restoreButton.setContentHuggingPriority(.required, for: .horizontal)
        restoreButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        restoreButton.addAction(UIAction { [weak self] _ in self?.onRestore?() }, for: .touchUpInside)

        var discardConfiguration = UIButton.Configuration.plain()
        discardConfiguration.image = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(textStyle: .footnote, scale: .small))
        discardConfiguration.baseForegroundColor = .secondaryLabel
        discardConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
        discardButton.configuration = discardConfiguration
        discardButton.accessibilityLabel = "丢弃草稿"
        discardButton.setContentHuggingPriority(.required, for: .horizontal)
        discardButton.addAction(UIAction { [weak self] _ in self?.discardTapped() }, for: .touchUpInside)

        let textRow = UIStackView(arrangedSubviews: [titleLabel, summaryLabel, chevronView])
        textRow.spacing = 6
        textRow.alignment = .center
        textRow.isUserInteractionEnabled = false

        mainRow.addArrangedSubview(iconView)
        mainRow.addArrangedSubview(textRow)
        mainRow.addArrangedSubview(restoreButton)
        mainRow.addArrangedSubview(discardButton)
        mainRow.spacing = 8
        mainRow.alignment = .center
        mainRow.setCustomSpacing(2, after: restoreButton)

        previewLabel.font = .preferredFont(forTextStyle: .footnote)
        previewLabel.adjustsFontForContentSizeCategory = true
        previewLabel.textColor = .secondaryLabel
        previewLabel.numberOfLines = 3
        previewLabel.isHidden = true

        setupUndoRow()

        let stack = UIStackView(arrangedSubviews: [mainRow, previewLabel, undoRow])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            mainRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 30)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(stripTapped))
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)
        isAccessibilityElement = false
    }

    private func setupUndoRow() {
        let label = UILabel()
        label.text = "已丢弃上次的草稿"
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel

        var undoConfiguration = UIButton.Configuration.plain()
        undoConfiguration.title = "撤销"
        undoConfiguration.baseForegroundColor = .label
        undoConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
        undoConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var updated = attributes
            updated.font = UIFont.preferredFont(forTextStyle: .footnote).withWeight(.semibold)
            return updated
        }
        let undoButton = UIButton(configuration: undoConfiguration)
        undoButton.setContentHuggingPriority(.required, for: .horizontal)
        undoButton.addAction(UIAction { [weak self] _ in self?.cancelPendingDiscard() }, for: .touchUpInside)

        undoRow.addArrangedSubview(label)
        undoRow.addArrangedSubview(undoButton)
        undoRow.alignment = .center
        undoRow.isHidden = true
        undoRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 30).isActive = true
    }

    // MARK: - 交互

    @objc private func stripTapped(_ recognizer: UITapGestureRecognizer) {
        guard discardTask == nil else { return }
        let point = recognizer.location(in: self)
        // 点在按钮上交给按钮自己处理。
        for button in [restoreButton, discardButton] where button.bounds.contains(button.convert(point, from: self)) {
            return
        }
        setExpanded(!isExpanded, animated: true)
    }

    private func setExpanded(_ expanded: Bool, animated: Bool) {
        isExpanded = expanded
        let changes = {
            self.previewLabel.isHidden = !expanded
            self.chevronView.transform = expanded ? CGAffineTransform(rotationAngle: .pi) : .identity
            self.superview?.superview?.layoutIfNeeded()
        }
        animated ? UIView.animate(withDuration: 0.22, animations: changes) : changes()
    }

    private func discardTapped() {
        UISelectionFeedbackGenerator().selectionChanged()
        mainRow.isHidden = true
        previewLabel.isHidden = true
        undoRow.isHidden = false
        discardTask?.cancel()
        discardTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.commitPendingDiscard()
        }
    }

    private func cancelPendingDiscard() {
        discardTask?.cancel()
        discardTask = nil
        mainRow.isHidden = false
        undoRow.isHidden = true
        previewLabel.isHidden = !isExpanded
    }
}

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
        return UIFont(descriptor: descriptor, size: 0)
    }
}
