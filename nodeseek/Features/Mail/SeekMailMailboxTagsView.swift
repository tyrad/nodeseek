//
//  SeekMailMailboxTagsView.swift
//  nodeseek
//

import UIKit

/// 一个邮箱标签；id 为 nil 表示「全部」。
struct SeekMailMailboxTag: Equatable {
    let id: Int64?
    let title: String
    let unread: Int

    /// 「名称 (9)」里括号部分；没有未读时不显示。
    var countText: String? {
        guard unread > 0 else { return nil }
        return " (\(unread > 99 ? "99+" : String(unread)))"
    }
}

extension SeekMailInboxModel {
    var mailboxTags: [SeekMailMailboxTag] {
        guard mailboxes.isEmpty == false else { return [] }
        let all = SeekMailMailboxTag(id: nil, title: SeekMailL10n.text("全部"), unread: unreadTotal ?? 0)
        return [all] + mailboxOrder.compactMap { id in
            names[id].map { SeekMailMailboxTag(id: id, title: $0.title, unread: unreadByMailbox[id] ?? 0) }
        }
    }
}

/// 邮箱标签平铺，固定在列表上方。超过两行默认折叠，选中的邮箱始终可见；展开后最多占半屏，再多就在区域内滚动。
final class SeekMailMailboxTagsView: UIView {
    var onSelect: ((Int64?) -> Void)?
    var onToggle: ((Bool) -> Void)?
    private(set) var isExpanded = false

    static let collapsedRows = 2
    /// 字号调大时标签跟着变高，默认档是 30。
    private static var rowHeight: CGFloat { max(30, ceil(SeekMailFont.system(14).lineHeight) + 12) }
    private static let spacing: CGFloat = 8
    private static let insets = UIEdgeInsets(top: 8, left: 16, bottom: 10, right: 16)

    private let scrollView = UIScrollView()
    private let toggleButton = UIButton(type: .system)
    private var tags: [SeekMailMailboxTag] = []
    private var selectedID: Int64?
    private var buttons: [UIButton] = []
    private lazy var heightConstraint: NSLayoutConstraint = {
        let constraint = heightAnchor.constraint(equalToConstant: Self.insets.top + Self.rowHeight + Self.insets.bottom)
        constraint.priority = .defaultHigh
        return constraint
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground
        accessibilityIdentifier = "seek-mail-tags"
        scrollView.showsVerticalScrollIndicator = true
        scrollView.alwaysBounceVertical = false
        addSubview(scrollView)
        toggleButton.accessibilityIdentifier = "seek-mail-tags-toggle"
        toggleButton.addAction(UIAction { [weak self] _ in self?.toggle() }, for: .touchUpInside)
        scrollView.addSubview(toggleButton)
        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)
        NSLayoutConstraint.activate([
            heightConstraint,
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(tags: [SeekMailMailboxTag], selectedID: Int64?, expanded: Bool) {
        if tags.map(\.id) != self.tags.map(\.id) {
            buttons.forEach { $0.removeFromSuperview() }
            buttons = tags.map { tag in
                let button = UIButton(type: .system)
                button.accessibilityIdentifier = tag.id.map { "seek-mail-tag-\($0)" } ?? "seek-mail-tag-all"
                button.addAction(UIAction { [weak self] _ in self?.onSelect?(tag.id) }, for: .touchUpInside)
                scrollView.addSubview(button)
                return button
            }
        }
        self.tags = tags
        self.selectedID = selectedID
        isExpanded = expanded
        for (tag, button) in zip(tags, buttons) {
            style(button, tag: tag, selected: tag.id == selectedID)
        }
        setNeedsLayout()
    }

    // MARK: - 布局

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        guard bounds.width > 0 else { return }
        let available = bounds.width - Self.insets.left - Self.insets.right
        let widths = buttons.map { min(ceil($0.sizeThatFits(CGSize(width: available, height: Self.rowHeight)).width), available) }

        var visible = Array(buttons.indices)
        var toggleTitle: String?
        if flow(widths, available: available).rows > Self.collapsedRows {
            if isExpanded {
                toggleTitle = SeekMailL10n.text("收起")
            } else {
                (visible, toggleTitle) = collapsedPlan(widths: widths, available: available)
            }
        }

        var itemWidths = visible.map { widths[$0] }
        if let toggleTitle {
            styleToggle(title: toggleTitle)
            itemWidths.append(ceil(toggleButton.sizeThatFits(CGSize(width: available, height: Self.rowHeight)).width))
        }
        let plan = flow(itemWidths, available: available)
        buttons.forEach { $0.isHidden = true }
        for (order, index) in visible.enumerated() {
            buttons[index].isHidden = false
            buttons[index].frame = plan.frames[order]
        }
        toggleButton.isHidden = toggleTitle == nil
        if toggleTitle != nil, let frame = plan.frames.last { toggleButton.frame = frame }

        let contentHeight = Self.insets.top + CGFloat(plan.rows) * Self.rowHeight
            + CGFloat(max(plan.rows - 1, 0)) * Self.spacing + Self.insets.bottom
        scrollView.contentSize = CGSize(width: bounds.width, height: contentHeight)
        let maxHeight = (window?.bounds.height ?? UIScreen.main.bounds.height) * 0.5
        let height = min(contentHeight, maxHeight)
        scrollView.isScrollEnabled = contentHeight > height
        if heightConstraint.constant != height { heightConstraint.constant = height }
    }

    /// 折叠时尽量多放标签，但要和「展开 N 个」一起挤进两行；选中的邮箱在被折叠的部分时，换到可见的最后一位。
    private func collapsedPlan(widths: [CGFloat], available: CGFloat) -> ([Int], String) {
        let selectedIndex = tags.firstIndex { $0.id == selectedID }
        for count in stride(from: widths.count - 1, through: 1, by: -1) {
            var indices = Array(0..<count)
            if let selectedIndex, selectedIndex >= count { indices[count - 1] = selectedIndex }
            let title = SeekMailL10n.format("展开 %@ 个", String(widths.count - count))
            styleToggle(title: title)
            let toggleWidth = ceil(toggleButton.sizeThatFits(CGSize(width: available, height: Self.rowHeight)).width)
            if flow(indices.map { widths[$0] } + [toggleWidth], available: available).rows <= Self.collapsedRows {
                return (indices, title)
            }
        }
        return ([selectedIndex ?? 0], SeekMailL10n.format("展开 %@ 个", String(widths.count - 1)))
    }

    private func flow(_ widths: [CGFloat], available: CGFloat) -> (frames: [CGRect], rows: Int) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var row = 0
        for width in widths {
            if x > 0, x + width > available {
                row += 1
                x = 0
            }
            let y = Self.insets.top + CGFloat(row) * (Self.rowHeight + Self.spacing)
            frames.append(CGRect(x: Self.insets.left + x, y: y, width: width, height: Self.rowHeight))
            x += width + Self.spacing
        }
        return (frames, widths.isEmpty ? 0 : row + 1)
    }

    private func toggle() {
        isExpanded.toggle()
        onToggle?(isExpanded)
        setNeedsLayout()
        UIView.animate(withDuration: window == nil ? 0 : 0.25, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
            self.superview?.layoutIfNeeded()
        }
    }

    // MARK: - 样式

    private func style(_ button: UIButton, tag: SeekMailMailboxTag, selected: Bool) {
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = selected ? .label : .secondarySystemBackground
        let foreground: UIColor = selected ? .systemBackground : .label
        configuration.baseForegroundColor = foreground
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
        configuration.titleLineBreakMode = .byTruncatingMiddle
        var title = AttributedString(tag.title)
        title.font = SeekMailFont.system(14, weight: selected ? .semibold : .regular)
        if let count = tag.countText {
            var suffix = AttributedString(count)
            suffix.font = SeekMailFont.system(14, weight: .regular)
            suffix.foregroundColor = foreground.withAlphaComponent(0.62)
            title += suffix
        }
        configuration.attributedTitle = title
        button.configuration = configuration
        button.accessibilityLabel = tag.unread > 0 ? SeekMailL10n.format("%@，%@ 封未读", tag.title, String(tag.unread)) : tag.title
        button.accessibilityTraits = selected ? [.button, .selected] : .button
    }

    private func styleToggle(title: String) {
        var configuration = UIButton.Configuration.plain()
        configuration.baseForegroundColor = .secondaryLabel
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 6)
        configuration.image = UIImage(systemName: isExpanded ? "chevron.up" : "chevron.down")
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 3
        var text = AttributedString(title)
        text.font = SeekMailFont.system(14)
        configuration.attributedTitle = text
        toggleButton.configuration = configuration
    }
}
