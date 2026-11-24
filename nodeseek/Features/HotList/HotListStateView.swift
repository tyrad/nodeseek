//
//  HotListStateView.swift
//  nodeseek
//

import UIKit

/// 列表背景状态：加载中、空榜、加载失败。
enum HotListStateView {
    static func loading(text: String) -> UIView {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.startAnimating()
        let label = makeLabel(text, font: .preferredFont(forTextStyle: .subheadline), color: .secondaryLabel)
        let stack = UIStackView(arrangedSubviews: [indicator, label])
        stack.axis = .vertical
        stack.spacing = 10
        stack.alignment = .center
        return wrap(stack, identifier: "hot-list-loading")
    }

    static func message(
        symbolName: String,
        title: String,
        body: String,
        retryTitle: String?,
        onRetry: (() -> Void)?
    ) -> UIView {
        let imageView = UIImageView(image: UIImage(
            systemName: symbolName,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 40, weight: .light)
        ))
        imageView.tintColor = .tertiaryLabel
        let titleLabel = makeLabel(title, font: .preferredFont(forTextStyle: .headline), color: .label)
        let bodyLabel = makeLabel(body, font: .preferredFont(forTextStyle: .subheadline), color: .secondaryLabel)
        let stack = UIStackView(arrangedSubviews: [imageView, titleLabel, bodyLabel])
        stack.axis = .vertical
        stack.spacing = 10
        stack.alignment = .center
        if let retryTitle, let onRetry {
            var configuration = UIButton.Configuration.filled()
            configuration.title = retryTitle
            configuration.baseBackgroundColor = .label
            configuration.baseForegroundColor = .systemBackground
            configuration.cornerStyle = .capsule
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 11, leading: 26, bottom: 11, trailing: 26)
            let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in onRetry() })
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            button.accessibilityIdentifier = "hot-list-retry-button"
            stack.setCustomSpacing(18, after: bodyLabel)
            stack.addArrangedSubview(button)
        }
        return wrap(stack, identifier: retryTitle == nil ? "hot-list-empty" : "hot-list-error")
    }

    private static func makeLabel(_ text: String, font: UIFont, color: UIColor) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = font
        label.adjustsFontForContentSizeCategory = true
        label.textColor = color
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }

    private static func wrap(_ content: UIView, identifier: String) -> UIView {
        let container = UIView()
        container.accessibilityIdentifier = identifier
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            content.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -40),
            content.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 40),
            content.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -40)
        ])
        return container
    }
}
