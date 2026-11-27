import UIKit

/// 主楼下的分页条定位这一段回复的起始页；滚动时的浮动页码仍跟随可见楼层。
/// 布局参照网页版：左侧说明当前页，右侧页码；放不下时先隐藏说明，再收成「‹ 2 / 9 ›」。
final class DetailReplyPaginationCell: UICollectionViewCell {
    private enum Item: Equatable {
        case previous, next, picker, compactPicker
        case page(Int)
    }

    private static let verticalPadding: CGFloat = 6
    private static let spacing: CGFloat = 2

    private var startPage = 1
    private var totalPages = 1
    private var items: [Item] = []
    /// 按钮字体在创建时确定，字号变化后需要重建
    private var builtCategory: UIContentSizeCategory?
    private var selectPage: ((Int) -> Void)?
    private var openPicker: (() -> Void)?
    private let stack = UIStackView()
    private let summaryLabel = UILabel()
    private let topSeparator = UIView()
    private let bottomSeparator = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        stack.axis = .horizontal
        stack.distribution = .fill
        stack.alignment = .fill
        stack.spacing = Self.spacing
        summaryLabel.textColor = .secondaryLabel
        summaryLabel.adjustsFontForContentSizeCategory = true
        topSeparator.backgroundColor = .separator
        bottomSeparator.backgroundColor = .separator
        [summaryLabel, stack, topSeparator, bottomSeparator].forEach(contentView.addSubview)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(startPage: Int, totalPages: Int, selectPage: @escaping (Int) -> Void, openPicker: @escaping () -> Void) {
        self.startPage = startPage
        self.totalPages = totalPages
        self.selectPage = selectPage
        self.openPicker = openPicker
        items = []
        setNeedsLayout()
    }

    static func height(for traits: UITraitCollection) -> CGFloat {
        let line = UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: traits).lineHeight
        return max(44, ceil(line) + 12) + 2 * verticalPadding
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = PostDetailContentLayout.horizontalInset
        let hairline = 1 / max(1, traitCollection.displayScale)
        topSeparator.frame = CGRect(x: 0, y: 0, width: bounds.width, height: hairline)
        bottomSeparator.frame = CGRect(x: 0, y: bounds.height - hairline, width: bounds.width, height: hairline)

        let available = max(0, contentView.bounds.width - 2 * inset)
        let full = fullControls()
        let fullWidth = rowWidth(full)
        summaryLabel.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: .systemFont(ofSize: 13), compatibleWith: traitCollection)
        summaryLabel.attributedText = summaryText()
        let labelWidth = ceil(summaryLabel.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: bounds.height)).width)

        let visible: [Item]
        let showsSummary: Bool
        if fullWidth + 12 + labelWidth <= available {
            (visible, showsSummary) = (full, true)
        } else if fullWidth <= available {
            (visible, showsSummary) = (full, false)
        } else {
            (visible, showsSummary) = ([.previous, .compactPicker, .next], false)
        }
        if visible != items || builtCategory != traitCollection.preferredContentSizeCategory {
            builtCategory = traitCollection.preferredContentSizeCategory
            stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
            items = visible
            for item in visible { stack.addArrangedSubview(button(for: item)) }
        }

        let width = min(available, rowWidth(visible))
        let rtl = effectiveUserInterfaceLayoutDirection == .rightToLeft
        stack.frame = CGRect(x: rtl ? inset : bounds.width - inset - width, y: Self.verticalPadding,
                             width: width, height: bounds.height - 2 * Self.verticalPadding)
        summaryLabel.isHidden = !showsSummary
        summaryLabel.frame = CGRect(x: rtl ? bounds.width - inset - labelWidth : inset, y: 0,
                                    width: labelWidth, height: bounds.height)
    }

    /// 页数少时全部列出；否则保留首页、当前页附近和末页，最多 7 项。
    private func fullControls() -> [Item] {
        if totalPages <= 5 {
            return [.previous] + (1...totalPages).map(Item.page) + [.next]
        }
        var pages = [1, startPage, totalPages]
        if startPage <= 2 { pages += [2, 3] }
        if startPage >= totalPages - 1 { pages += [totalPages - 2, totalPages - 1] }
        var result: [Item] = [.previous]
        var previous = 0
        for page in Set(pages).sorted() {
            if page - previous > 1 { result.append(.picker) }
            result.append(.page(page))
            previous = page
        }
        return result + [.next]
    }

    /// 胶囊默认 30pt，大字号时随文字行高放大，避免数字顶到边缘
    private var chipHeight: CGFloat {
        max(30, ceil(chipFont.lineHeight) + 10)
    }

    private var chipFont: UIFont {
        let base = UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: traitCollection)
        return .monospacedDigitSystemFont(ofSize: base.pointSize, weight: .regular)
    }

    private func title(for item: Item) -> String? {
        switch item {
        case .previous, .next: return nil
        case .picker: return "···"
        case .compactPicker: return "\(startPage.formatted()) / \(totalPages.formatted())"
        case .page(let page): return page.formatted()
        }
    }

    /// 页码宽度按数字实际测量，三位数页码也不会被挤压；点击区至少 36pt 宽、44pt 高。
    private func width(for item: Item) -> CGFloat {
        let font = UIFont.monospacedDigitSystemFont(ofSize: chipFont.pointSize, weight: .semibold)
        let text = title(for: item).map { ($0 as NSString).size(withAttributes: [.font: font]).width } ?? 0
        let padding: CGFloat = item == .compactPicker ? 28 : 14
        return max(36, chipHeight, ceil(text) + padding)
    }

    private func rowWidth(_ items: [Item]) -> CGFloat {
        items.reduce(0) { $0 + width(for: $1) } + CGFloat(max(0, items.count - 1)) * Self.spacing
    }

    private func summaryText() -> NSAttributedString {
        let format = localize("reply-page-summary")
        let marker = "\u{FFFC}"
        let plain = String(format: format, marker, totalPages.formatted())
        let text = NSMutableAttributedString(string: plain, attributes: [.foregroundColor: UIColor.secondaryLabel])
        let range = (plain as NSString).range(of: marker)
        if range.location != NSNotFound {
            let bold = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: .systemFont(ofSize: 13, weight: .semibold), compatibleWith: traitCollection)
            text.replaceCharacters(in: range, with: NSAttributedString(string: startPage.formatted(),
                                                                       attributes: [.font: bold, .foregroundColor: UIColor.label]))
        }
        return text
    }

    private func button(for item: Item) -> UIButton {
        let selected = item == .page(startPage) || item == .compactPicker
        var config = UIButton.Configuration.plain()
        config.contentInsets = .zero
        config.background.cornerRadius = chipHeight / 2
        // 视觉胶囊较矮，按钮本身仍保持至少 44pt 点击高度
        let height = Self.height(for: traitCollection) - 2 * Self.verticalPadding
        let inset = max(0, (height - chipHeight) / 2)
        config.background.backgroundInsets = NSDirectionalEdgeInsets(top: inset, leading: 2, bottom: inset, trailing: 2)
        config.baseForegroundColor = item == .picker ? .secondaryLabel : .label
        if selected {
            config.background.backgroundColor = .label
            config.baseForegroundColor = .systemBackground
        }
        let font = UIFont.monospacedDigitSystemFont(ofSize: chipFont.pointSize, weight: selected ? .semibold : .regular)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = font
            return attributes
        }

        let button = UIButton(configuration: config)
        let target: Int?
        switch item {
        case .previous, .next:
            let previous = item == .previous
            button.configuration?.image = UIImage(systemName: previous ? "chevron.backward" : "chevron.forward")
            button.configuration?.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(font: chipFont, scale: .small)
            target = previous ? max(1, startPage - 1) : (startPage < totalPages ? startPage + 1 : nil)
            button.isEnabled = previous ? startPage > 1 : startPage < totalPages
            button.accessibilityLabel = localize(previous ? "reply-page-previous" : "reply-page-next")
        case .picker, .compactPicker:
            button.setTitle(title(for: item), for: .normal)
            button.accessibilityLabel = localize("reply-page-choose")
            if item == .compactPicker { button.accessibilityValue = startPage.formatted() }
            target = nil
        case .page(let page):
            button.setTitle(page.formatted(), for: .normal)
            button.accessibilityLabel = String.localizedStringWithFormat(localize("reply-page-number"), page)
            target = page
        }
        if selected { button.accessibilityTraits.insert(.selected) }
        button.widthAnchor.constraint(equalToConstant: width(for: item)).isActive = true
        button.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if let target {
                if target != self.startPage { self.selectPage?(target) }
            } else {
                self.openPicker?()
            }
        }, for: .touchUpInside)
        return button
    }

    private func localize(_ key: String) -> String {
        NSLocalizedString(key, tableName: "DetailPrototype", comment: "")
    }
}
