//
//  UserContentListChrome.swift
//  nodeseek
//
//  Created by Codex on 2026/5/11.
//

import UIKit

enum UserContentDisplayMode {
    case content
    case skeleton
    case firstPageError
}

final class UserContentErrorView: UIStackView {
    let messageLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    var onRetry: (() -> Void)?

    init(accessibilityIdentifier: String) {
        super.init(frame: .zero)
        axis = .vertical
        alignment = .center
        spacing = 10
        isHidden = true
        self.accessibilityIdentifier = accessibilityIdentifier
        translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = "加载失败"
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .label
        titleLabel.adjustsFontForContentSizeCategory = true

        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.adjustsFontForContentSizeCategory = true

        var configuration = UIButton.Configuration.filled()
        configuration.title = "重试"
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 18)
        retryButton.configuration = configuration
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)

        addArrangedSubview(titleLabel)
        addArrangedSubview(messageLabel)
        addArrangedSubview(retryButton)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func retryTapped() {
        onRetry?()
    }
}

final class UserContentFooterView: UIView {
    private let indicator = UIActivityIndicatorView(style: .medium)

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 1, height: 56))
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(indicator)
        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func startAnimating() {
        indicator.startAnimating()
    }

    func stopAnimating() {
        indicator.stopAnimating()
    }
}
