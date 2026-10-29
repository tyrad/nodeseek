//
//  NewDiscussionToolbarView.swift
//  nodeseek
//

import UIKit

/// 键盘上方的悬浮工具条：[文字 表情 Aa] 输入方式切换、图片、链接 ｜ 预览 ｜ 收起键盘。
final class NewDiscussionToolbarView: UIView {
    enum Item: CaseIterable {
        case keyboard
        case photo
        case sticker
        case format
        case link
        case preview
        case dismissKeyboard

        var symbolName: String {
            switch self {
            case .keyboard:
                if #available(iOS 17.0, *) { return "character.cursor.ibeam" }
                return "keyboard"
            case .photo: return "photo"
            case .sticker: return "face.smiling"
            case .format: return "textformat"
            case .link: return "link"
            case .preview: return "eye"
            case .dismissKeyboard: return "keyboard.chevron.compact.down"
            }
        }

        var accessibilityLabel: String {
            switch self {
            case .keyboard: return "文字键盘"
            case .photo: return "插入图片"
            case .sticker: return "表情"
            case .format: return "格式"
            case .link: return "插入链接"
            case .preview: return "预览"
            case .dismissKeyboard: return "收起键盘"
            }
        }
    }

    var onTap: ((Item) -> Void)?

    private var buttons: [Item: UIButton] = [:]
    private let capsule = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))

    override init(frame: CGRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: frame.width, height: 60))
        autoresizingMask = .flexibleHeight
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 60)
    }

    /// 当前输入方式（键盘、表情、格式）对应的按钮显示为反色选中态。
    func setActive(_ item: Item?) {
        for (candidate, button) in buttons {
            button.isSelected = candidate == item
        }
    }

    func setEnabled(_ isEnabled: Bool) {
        buttons.values.forEach { $0.isEnabled = isEnabled }
    }

    private func setupUI() {
        backgroundColor = .clear

        capsule.layer.cornerRadius = 24
        capsule.layer.cornerCurve = .continuous
        capsule.clipsToBounds = true
        capsule.translatesAutoresizingMaskIntoConstraints = false
        addSubview(capsule)

        // 文字、表情、格式三选一，放进同一个底槽里，看得出是在切换键盘区域显示什么。
        let modes = UIStackView(arrangedSubviews: [Item.keyboard, .sticker, .format].map(makeButton))
        modes.spacing = 0
        modes.isLayoutMarginsRelativeArrangement = true
        modes.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 2, leading: 2, bottom: 2, trailing: 2)
        modes.backgroundColor = .secondarySystemFill
        modes.layer.cornerRadius = 20
        modes.layer.cornerCurve = .continuous

        // 图片、链接是一次性插入的动作，不改变输入方式。
        let inserts = UIStackView(arrangedSubviews: [Item.photo, .link].map(makeButton))
        inserts.spacing = 0

        let divider = UIView()
        divider.backgroundColor = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.widthAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        divider.heightAnchor.constraint(equalToConstant: 22).isActive = true

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [modes, inserts, spacer, makePreviewButton(), divider, makeButton(.dismissKeyboard)])
        row.alignment = .center
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        capsule.contentView.addSubview(row)

        NSLayoutConstraint.activate([
            capsule.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            capsule.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            capsule.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            capsule.heightAnchor.constraint(equalToConstant: 48),

            row.leadingAnchor.constraint(equalTo: capsule.contentView.leadingAnchor, constant: 6),
            row.trailingAnchor.constraint(equalTo: capsule.contentView.trailingAnchor, constant: -6),
            row.centerYAnchor.constraint(equalTo: capsule.contentView.centerYAnchor)
        ])
    }

    /// 预览是动作而不是格式，用带文字的小胶囊和左边的图标区分开。
    private func makePreviewButton() -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.title = "预览"
        configuration.image = UIImage(systemName: Item.preview.symbolName)
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .footnote)
        configuration.imagePadding = 4
        configuration.cornerStyle = .capsule
        configuration.baseForegroundColor = .label
        configuration.background.backgroundColor = .secondarySystemFill
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var updated = attributes
            updated.font = UIFont.preferredFont(forTextStyle: .subheadline)
            return updated
        }
        let button = UIButton(configuration: configuration)
        button.accessibilityLabel = Item.preview.accessibilityLabel
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.addAction(UIAction { [weak self] _ in self?.onTap?(.preview) }, for: .touchUpInside)
        buttons[.preview] = button
        return button
    }

    private func makeButton(_ item: Item) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        var symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        if #available(iOS 17.0, *) {
            // textformat 在中文系统里会被本地化成“格式”二字，固定用拉丁字形的 Aa，和其他图标风格一致。
            symbolConfiguration = symbolConfiguration.applying(UIImage.SymbolConfiguration(locale: Locale(identifier: "en")))
        }
        configuration.image = UIImage(systemName: item.symbolName, withConfiguration: symbolConfiguration)
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)

        let button = UIButton(configuration: configuration)
        // 选中态用 .label 反色，深浅模式下自动是黑底白字 / 白底黑字。
        button.configurationUpdateHandler = { button in
            var updated = button.configuration
            updated?.baseForegroundColor = button.isSelected ? .systemBackground : .label
            updated?.background.backgroundColor = button.isSelected ? .label : .clear
            button.configuration = updated
        }
        button.accessibilityLabel = item.accessibilityLabel
        button.addAction(UIAction { [weak self] _ in self?.onTap?(item) }, for: .touchUpInside)
        button.widthAnchor.constraint(equalToConstant: 40).isActive = true
        button.heightAnchor.constraint(equalToConstant: 36).isActive = true
        buttons[item] = button
        return button
    }
}
