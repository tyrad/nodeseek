//
//  UserProfileSkeletonView.swift
//  nodeseek
//
//  Created by Claude on 2026/10/30.
//

import UIKit

/// 个人页首次加载的骨架：按真实布局摆出头部、数字卡片和内容列表的占位。
@MainActor
final class UserProfileSkeletonView: UIView {
    private static let pulseKey = "user_profile_skeleton_pulse"
    private var placeholders: [UIView] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false

        let stack = UIStackView(arrangedSubviews: [
            makeHeader(),
            makeCard(height: 72) { self.makeStatsContent() },
            makeSectionTitle(),
            makeCard(height: 92) { self.makeRowsContent() }
        ])
        stack.axis = .vertical
        stack.spacing = 18
        stack.setCustomSpacing(4, after: stack.arrangedSubviews[2])
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stopAnimating()
        } else if !isHidden {
            startAnimating()
        }
    }

    override var isHidden: Bool {
        didSet {
            isHidden ? stopAnimating() : startAnimating()
        }
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

    // MARK: - 占位块

    private func placeholder(width: CGFloat? = nil, height: CGFloat, radius: CGFloat = 5) -> UIView {
        let view = UIView()
        view.backgroundColor = .systemGray5
        view.layer.cornerRadius = radius
        view.layer.cornerCurve = .continuous
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        if let width {
            view.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
        placeholders.append(view)
        return view
    }

    private func makeHeader() -> UIView {
        let info = UIStackView(arrangedSubviews: [
            placeholder(width: 120, height: 22, radius: 6),
            placeholder(width: 170, height: 13, radius: 4)
        ])
        info.axis = .vertical
        info.alignment = .leading
        info.spacing = 10

        let header = UIStackView(arrangedSubviews: [placeholder(width: 72, height: 72, radius: 16), info])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 14
        header.isLayoutMarginsRelativeArrangement = true
        header.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)
        return header
    }

    private func makeStatsContent() -> UIView {
        let columns = (0..<4).map { _ -> UIView in
            let column = UIStackView(arrangedSubviews: [
                placeholder(width: 40, height: 18, radius: 5),
                placeholder(width: 28, height: 11, radius: 4)
            ])
            column.axis = .vertical
            column.alignment = .center
            column.spacing = 8
            return column
        }
        let stack = UIStackView(arrangedSubviews: columns)
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .center
        return stack
    }

    private func makeRowsContent() -> UIView {
        let rows = (0..<2).map { index -> UIView in
            let row = UIStackView(arrangedSubviews: [
                placeholder(width: 20, height: 20, radius: 5),
                placeholder(width: index == 0 ? 72 : 56, height: 15, radius: 4),
                UIView()
            ])
            row.axis = .horizontal
            row.alignment = .center
            row.spacing = 14
            return row
        }
        let stack = UIStackView(arrangedSubviews: rows)
        stack.axis = .vertical
        stack.distribution = .fillEqually
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
        return stack
    }

    private func makeSectionTitle() -> UIView {
        let container = UIView()
        let bar = placeholder(width: 36, height: 12, radius: 4)
        container.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 32),
            bar.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            bar.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    private func makeCard(height: CGFloat, content: () -> UIView) -> UIView {
        let card = UIView()
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 14
        card.layer.cornerCurve = .continuous
        let inner = content()
        inner.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(inner)
        card.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView()
        container.addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            card.topAnchor.constraint(equalTo: container.topAnchor),
            card.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            card.heightAnchor.constraint(equalToConstant: height),
            inner.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            inner.topAnchor.constraint(equalTo: card.topAnchor),
            inner.bottomAnchor.constraint(equalTo: card.bottomAnchor)
        ])
        return container
    }
}
