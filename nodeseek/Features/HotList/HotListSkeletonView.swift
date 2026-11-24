//
//  HotListSkeletonView.swift
//  nodeseek
//

import UIKit

/// 热榜首次加载时的骨架屏，行结构与 HotListCell 对齐：排名｜标题＋信息行。
final class HotListSkeletonView: UIView {
    private enum Layout {
        static let rowCount = 10
        static let horizontalInset: CGFloat = 16
        static let rankWidth: CGFloat = 28
        static let rowHeight: CGFloat = 72
    }

    private var placeholders: [UIView] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "hot-list-loading"
        isAccessibilityElement = true
        accessibilityLabel = HotListL10n.text("正在加载…")
        clipsToBounds = true
        setupRows()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        window == nil ? stopPulse() : startPulse()
    }

    private func setupRows() {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        // 宽度错落，看起来更像真实标题
        let titleWidths: [CGFloat] = [0.86, 0.7, 0.92, 0.64, 0.8, 0.74, 0.9, 0.6, 0.82, 0.7]
        for index in 0..<Layout.rowCount {
            stack.addArrangedSubview(makeRow(titleWidth: titleWidths[index % titleWidths.count]))
        }
    }

    private func makeRow(titleWidth: CGFloat) -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let rank = placeholder(cornerRadius: 4)
        let title = placeholder(cornerRadius: 5)
        let avatar = placeholder(cornerRadius: 4)
        let meta = placeholder(cornerRadius: 4)
        let stats = placeholder(cornerRadius: 4)
        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        [rank, title, avatar, meta, stats, separator].forEach(row.addSubview)

        let contentLeading = Layout.horizontalInset + Layout.rankWidth + 4
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: Layout.rowHeight),

            rank.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: Layout.horizontalInset + 4),
            rank.topAnchor.constraint(equalTo: row.topAnchor, constant: 15),
            rank.widthAnchor.constraint(equalToConstant: 16),
            rank.heightAnchor.constraint(equalToConstant: 18),

            title.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: contentLeading),
            title.topAnchor.constraint(equalTo: row.topAnchor, constant: 15),
            title.heightAnchor.constraint(equalToConstant: 18),
            title.widthAnchor.constraint(equalTo: row.widthAnchor, multiplier: titleWidth, constant: -contentLeading),

            avatar.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            avatar.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
            avatar.widthAnchor.constraint(equalToConstant: 16),
            avatar.heightAnchor.constraint(equalToConstant: 16),

            meta.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 6),
            meta.centerYAnchor.constraint(equalTo: avatar.centerYAnchor),
            meta.heightAnchor.constraint(equalToConstant: 12),
            meta.widthAnchor.constraint(equalTo: row.widthAnchor, multiplier: 0.3),

            stats.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -Layout.horizontalInset),
            stats.centerYAnchor.constraint(equalTo: avatar.centerYAnchor),
            stats.heightAnchor.constraint(equalToConstant: 12),
            stats.widthAnchor.constraint(equalTo: row.widthAnchor, multiplier: 0.26),

            separator.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: contentLeading),
            separator.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
        ])
        return row
    }

    private func placeholder(cornerRadius: CGFloat) -> UIView {
        let view = UIView()
        view.backgroundColor = .systemGray5
        view.layer.cornerRadius = cornerRadius
        view.translatesAutoresizingMaskIntoConstraints = false
        placeholders.append(view)
        return view
    }

    /// 与首页骨架屏相同的呼吸动画。
    private func startPulse() {
        for view in placeholders where view.layer.animation(forKey: "skeleton_pulse") == nil {
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = 1.0
            animation.toValue = 0.45
            animation.duration = 0.8
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            view.layer.add(animation, forKey: "skeleton_pulse")
        }
    }

    private func stopPulse() {
        placeholders.forEach { $0.layer.removeAnimation(forKey: "skeleton_pulse") }
    }
}
