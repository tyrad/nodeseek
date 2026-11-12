//
//  SearchScopeTabsView.swift
//  nodeseek
//

import UIKit

/// 搜索范围切换：选中项用 .label 反色胶囊，其余为次要文字，替代系统分段控件。
/// 接口沿用 UISegmentedControl 的命名，切换时发送 .valueChanged。
final class SearchScopeTabsView: UIControl {
    private let scrollView = UIScrollView()
    private let titles: [String]
    private var buttons: [UIButton] = []
    private let stackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    var selectedSegmentIndex: Int = 0 {
        didSet { updateAppearance() }
    }

    var numberOfSegments: Int { titles.count }

    init(titles: [String]) {
        self.titles = titles
        super.init(frame: .zero)
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        scrollView.addSubview(stackView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])

        buttons = titles.enumerated().map { index, title in
            let button = UIButton(type: .system)
            button.accessibilityLabel = title
            button.addAction(UIAction { [weak self] _ in
                self?.select(index)
            }, for: .touchUpInside)
            stackView.addArrangedSubview(button)
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
            return button
        }
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func titleForSegment(at index: Int) -> String? {
        titles.indices.contains(index) ? titles[index] : nil
    }

    private func select(_ index: Int) {
        guard index != selectedSegmentIndex else { return }
        selectedSegmentIndex = index
        scrollView.scrollRectToVisible(buttons[index].frame, animated: !UIAccessibility.isReduceMotionEnabled)
        sendActions(for: .valueChanged)
    }

    func refreshTypography() {
        updateAppearance()
        invalidateIntrinsicContentSize()
    }

    private func updateAppearance() {
        for (index, button) in buttons.enumerated() {
            let isSelected = index == selectedSegmentIndex
            var configuration = UIButton.Configuration.plain()
            configuration.title = titles[index]
            configuration.cornerStyle = .capsule
            configuration.background.backgroundColor = isSelected ? .label : .clear
            configuration.baseForegroundColor = isSelected ? .systemBackground : .secondaryLabel
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14)
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = AppTypography.font(basePointSize: 15, weight: isSelected ? .semibold : .medium)
                return outgoing
            }
            button.configuration = configuration
            button.accessibilityTraits = isSelected ? [.button, .selected] : .button
        }
    }
}
