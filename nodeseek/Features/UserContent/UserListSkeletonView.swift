//
//  UserListSkeletonView.swift
//  nodeseek
//
//  Created by Claude on 2026/10/30.
//

import UIKit

/// 个人相关列表（关注、星辰、鸡腿）首次加载的骨架。
/// 直接铺在分组背景上，不放进卡片单元格，避免加载时先出现一圈卡片边框和分隔线。
@MainActor
final class UserListSkeletonView: UIView {
    enum Style {
        case member
        case stardust
        case credit
    }

    private static let pulseKey = "user_list_skeleton_pulse"
    private let style: Style
    private var placeholders: [UIView] = []

    init(style: Style, rowCount: Int = 5) {
        self.style = style
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        accessibilityIdentifier = "user-list-skeleton"

        let stack = UIStackView(arrangedSubviews: (0..<rowCount).map { makeRow(index: $0) })
        stack.axis = .vertical
        stack.spacing = 26
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        // 分组页脚本身已按卡片外边距缩进，再加卡片内边距 16，和分组标题、正文左边对齐
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        window == nil ? stopAnimating() : startAnimating()
    }

    private func startAnimating() {
        for view in placeholders where view.layer.animation(forKey: Self.pulseKey) == nil {
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = 1.0
            animation.toValue = 0.45
            animation.duration = 0.8
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            view.layer.add(animation, forKey: Self.pulseKey)
        }
    }

    private func stopAnimating() {
        placeholders.forEach { $0.layer.removeAnimation(forKey: Self.pulseKey) }
    }

    // MARK: - 占位行

    private func makeRow(index: Int) -> UIView {
        // 宽度轻微错落，看起来更像真实内容
        let wide: CGFloat = index.isMultiple(of: 2) ? 1 : 0.78
        switch style {
        case .member:
            let info = vertical([block(width: 110 * wide, height: 16), block(width: 76, height: 12)], spacing: 8)
            let head = horizontal([block(width: 44, height: 44, radius: 10), info], alignment: .center, spacing: 12)
            return vertical([head, block(width: 230 * wide, height: 11), block(width: 190, height: 11)], spacing: 9)
        case .stardust:
            let members = horizontal([
                block(width: 22, height: 22, radius: 11), block(width: 54, height: 12),
                block(width: 16, height: 10, radius: 3),
                block(width: 22, height: 22, radius: 11), block(width: 54 * wide, height: 12),
                UIView()
            ], alignment: .center, spacing: 8)
            return vertical(alignment: .fill, [
                spread(block(width: 120 * wide, height: 16), block(width: 44, height: 18)),
                members,
                spread(block(width: 104, height: 11), block(width: 58, height: 11))
            ], spacing: 10)
        case .credit:
            return vertical(alignment: .fill, [
                spread(block(width: 150 * wide, height: 16), block(width: 44, height: 18)),
                spread(block(width: 104, height: 11), block(width: 58, height: 11))
            ], spacing: 10)
        }
    }

    private func block(width: CGFloat, height: CGFloat, radius: CGFloat = 4) -> UIView {
        let view = UIView()
        view.backgroundColor = .systemGray5
        view.layer.cornerRadius = radius
        view.layer.cornerCurve = .continuous
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: width),
            view.heightAnchor.constraint(equalToConstant: height)
        ])
        placeholders.append(view)
        return view
    }

    private func vertical(alignment: UIStackView.Alignment = .leading, _ views: [UIView], spacing: CGFloat) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .vertical
        stack.alignment = alignment
        stack.spacing = spacing
        return stack
    }

    private func horizontal(_ views: [UIView], alignment: UIStackView.Alignment, spacing: CGFloat) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.alignment = alignment
        stack.spacing = spacing
        return stack
    }

    /// 左右两端对齐的一行，对应「原因 … 变动值」「时间 … 余额」
    private func spread(_ leading: UIView, _ trailing: UIView) -> UIView {
        let row = UIStackView(arrangedSubviews: [leading, UIView(), trailing])
        row.alignment = .center
        return row
    }
}
