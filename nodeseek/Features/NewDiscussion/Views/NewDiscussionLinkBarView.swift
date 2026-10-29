//
//  NewDiscussionLinkBarView.swift
//  nodeseek
//

import UIKit

/// 贴在键盘上方的链接编辑条：名称、地址分开填，不弹窗打断写作。
final class NewDiscussionLinkBarView: UIView {
    var onConfirm: ((_ name: String, _ url: String) -> Void)?
    var onCancel: (() -> Void)?

    private let titleLabel = UILabel()
    private let nameField = UITextField()
    private let urlField = UITextField()
    private let confirmButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 已有名称时直接去填地址。
    func begin(name: String, url: String, isEditing: Bool) {
        titleLabel.text = isEditing ? "编辑链接" : "插入链接"
        nameField.text = name
        urlField.text = url
        updateConfirmState(isEditing: isEditing)
        if name.isEmpty || !url.isEmpty {
            nameField.becomeFirstResponder()
        } else {
            urlField.becomeFirstResponder()
        }
    }

    var containsFirstResponder: Bool {
        nameField.isFirstResponder || urlField.isFirstResponder
    }

    // MARK: - 布局

    private func setupUI() {
        let background = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
        background.layer.cornerRadius = 20
        background.layer.cornerCurve = .continuous
        background.clipsToBounds = true
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)

        titleLabel.font = .preferredFont(forTextStyle: .subheadline).withBoldTrait()
        titleLabel.adjustsFontForContentSizeCategory = true

        var cancelConfiguration = UIButton.Configuration.plain()
        cancelConfiguration.title = "取消"
        cancelConfiguration.baseForegroundColor = .secondaryLabel
        cancelConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
        let cancelButton = UIButton(configuration: cancelConfiguration)
        cancelButton.addAction(UIAction { [weak self] _ in self?.onCancel?() }, for: .touchUpInside)

        var confirmConfiguration = UIButton.Configuration.filled()
        confirmConfiguration.cornerStyle = .capsule
        confirmConfiguration.baseBackgroundColor = .label
        confirmConfiguration.baseForegroundColor = UIColor(named: "InvertedLabel") ?? .systemBackground
        confirmConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14)
        confirmButton.configuration = confirmConfiguration
        confirmButton.addAction(UIAction { [weak self] _ in self?.confirm() }, for: .touchUpInside)

        let header = UIStackView(arrangedSubviews: [titleLabel, UIView(), cancelButton, confirmButton])
        header.alignment = .center
        header.spacing = 4

        configure(nameField, label: "名称", placeholder: "可不填，默认显示地址")
        nameField.returnKeyType = .next
        configure(urlField, label: "地址", placeholder: "https://")
        urlField.keyboardType = .URL
        urlField.autocapitalizationType = .none
        urlField.autocorrectionType = .no
        urlField.returnKeyType = .done
        urlField.addAction(UIAction { [weak self] _ in self?.updateConfirmState(isEditing: nil) }, for: .editingChanged)
        nameField.addAction(UIAction { [weak self] _ in self?.urlField.becomeFirstResponder() }, for: .editingDidEndOnExit)
        urlField.addAction(UIAction { [weak self] _ in self?.confirm() }, for: .editingDidEndOnExit)

        let separator = UIView()
        separator.backgroundColor = .separator
        separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true

        let fields = UIStackView(arrangedSubviews: [nameField, separator, urlField])
        fields.axis = .vertical
        fields.backgroundColor = .tertiarySystemFill
        fields.layer.cornerRadius = 12
        fields.layer.cornerCurve = .continuous
        fields.isLayoutMarginsRelativeArrangement = true
        fields.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 8)

        let stack = UIStackView(arrangedSubviews: [header, fields])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: topAnchor),
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.topAnchor.constraint(equalTo: background.contentView.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: background.contentView.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: background.contentView.trailingAnchor, constant: -8),
            stack.bottomAnchor.constraint(equalTo: background.contentView.bottomAnchor, constant: -12),
            nameField.heightAnchor.constraint(equalToConstant: 42),
            urlField.heightAnchor.constraint(equalToConstant: 42)
        ])
    }

    private func configure(_ field: UITextField, label: String, placeholder: String) {
        let prefix = UILabel()
        prefix.text = label
        prefix.font = .preferredFont(forTextStyle: .subheadline)
        prefix.textColor = .secondaryLabel
        prefix.sizeToFit()
        // leftView 会按内在尺寸排版，包一层固定宽度的容器才能和输入内容留出间距。
        let container = UIView(frame: CGRect(x: 0, y: 0, width: prefix.bounds.width + 12, height: prefix.bounds.height))
        container.addSubview(prefix)
        field.leftView = container
        field.leftViewMode = .always
        field.placeholder = placeholder
        field.font = .preferredFont(forTextStyle: .subheadline)
        field.clearButtonMode = .whileEditing
        field.tintColor = .label
    }

    // MARK: - 交互

    private var isEditingExisting = false

    /// 地址为空时不能插入。
    private func updateConfirmState(isEditing: Bool?) {
        if let isEditing { isEditingExisting = isEditing }
        var configuration = confirmButton.configuration
        configuration?.attributedTitle = AttributedString(
            isEditingExisting ? "保存" : "插入",
            attributes: AttributeContainer([.font: UIFont.preferredFont(forTextStyle: .subheadline).withBoldTrait()])
        )
        confirmButton.configuration = configuration
        confirmButton.isEnabled = !(urlField.text ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func confirm() {
        guard confirmButton.isEnabled else { return }
        onConfirm?(nameField.text ?? "", urlField.text ?? "")
    }
}

private extension UIFont {
    func withBoldTrait() -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }
}
