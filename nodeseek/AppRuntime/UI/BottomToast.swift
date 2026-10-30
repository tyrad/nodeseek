//
//  BottomToast.swift
//  nodeseek
//
//  Created by Claude on 2026/10/30.
//

import UIKit

/// 底部轻提示，样式与帖子详情页的 toast 一致：反色圆角底 + 可选状态图标，自动消失。
@MainActor
enum BottomToast {
    enum Style {
        case success
        case failure

        var image: UIImage? {
            UIImage(systemName: self == .success ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
        }

        var tintColor: UIColor {
            self == .success ? .systemGreen : .systemOrange
        }
    }

    static let accessibilityIdentifier = "bottom-toast"

    static func show(_ message: String, style: Style = .success, in sourceView: UIView, duration: TimeInterval = 2) {
        // 挂到窗口上，和自动签到提示一样，不会被页面里的列表、导航层级遮住
        let view: UIView = sourceView.window ?? sourceView
        // 连续操作时只保留最新一条
        view.subviews
            .filter { $0.accessibilityIdentifier == accessibilityIdentifier }
            .forEach { $0.removeFromSuperview() }

        let toast = makeToastView(message: message, style: style)
        view.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            toast.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        ])
        UIAccessibility.post(notification: .announcement, argument: message)

        toast.alpha = 0
        toast.transform = CGAffineTransform(translationX: 0, y: 8)
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            toast.alpha = 1
            toast.transform = .identity
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak toast] in
            guard let toast, toast.superview != nil else { return }
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseIn, .allowUserInteraction]) {
                toast.alpha = 0
                toast.transform = CGAffineTransform(translationX: 0, y: 8)
            } completion: { _ in
                toast.removeFromSuperview()
            }
        }
    }

    private static func makeToastView(message: String, style: Style) -> UIView {
        let container = UIView()
        container.accessibilityIdentifier = accessibilityIdentifier
        container.isUserInteractionEnabled = false
        container.backgroundColor = UIColor.label.withAlphaComponent(0.92)
        container.layer.cornerRadius = 14
        container.layer.cornerCurve = .continuous
        container.layer.shadowColor = UIColor.black.cgColor
        container.layer.shadowOpacity = 0.18
        container.layer.shadowRadius = 14
        container.layer.shadowOffset = CGSize(width: 0, height: 8)
        container.translatesAutoresizingMaskIntoConstraints = false

        let icon = UIImageView(image: style.image)
        icon.tintColor = style.tintColor
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = message
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .systemBackground
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(icon)
        container.addSubview(label)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10)
        ])
        return container
    }
}
