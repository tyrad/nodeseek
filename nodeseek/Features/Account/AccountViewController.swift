//
//  AccountViewController.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import UIKit

class AccountViewController: UIViewController {
    
    // MARK: - Properties
    private let presenter: AccountPresenterProtocol
    private let avatarLoader = AvatarImageLoader.shared
    
    // MARK: - UI Components
    private let avatarImageView: UIImageView = {
        let imageView = UIImageView()
        let configuration = UIImage.SymbolConfiguration(pointSize: 54, weight: .regular)
        imageView.image = UIImage(systemName: "person.crop.circle.fill", withConfiguration: configuration)
        imageView.tintColor = .tertiaryLabel
        imageView.backgroundColor = .secondarySystemBackground
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 36
        imageView.isHidden = true
        imageView.accessibilityIdentifier = "account-avatar-image"
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .body)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.accessibilityIdentifier = "account-status-label"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let statsLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.accessibilityIdentifier = "account-stats-label"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    private let loginButton: UIButton = {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.filled()
        configuration.title = "登录"
        configuration.image = UIImage(systemName: "person.crop.circle.badge.plus")
        configuration.imagePadding = 8
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 18, bottom: 12, trailing: 18)
        button.configuration = configuration
        button.accessibilityIdentifier = "account-login-button"
        button.isHidden = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    // MARK: - Initialization
    init(presenter: AccountPresenterProtocol) {
        self.presenter = presenter
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        presenter.viewDidLoad()
    }
    
    // MARK: - Setup UI
    private func setupUI() {
        title = "账号"
        view.backgroundColor = .systemBackground
        loginButton.addTarget(self, action: #selector(loginButtonTapped), for: .touchUpInside)
        view.addSubview(avatarImageView)
        view.addSubview(statusLabel)
        view.addSubview(statsLabel)
        view.addSubview(loadingIndicator)
        view.addSubview(loginButton)
        
        NSLayoutConstraint.activate([
            avatarImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            avatarImageView.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -18),
            avatarImageView.widthAnchor.constraint(equalToConstant: 72),
            avatarImageView.heightAnchor.constraint(equalToConstant: 72),

            statusLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -28),

            statsLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            statsLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            statsLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),

            loginButton.topAnchor.constraint(equalTo: statsLabel.bottomAnchor, constant: 24),
            loginButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    @objc private func loginButtonTapped() {
        presenter.didTapLogin()
    }
}

// MARK: - View Protocol
extension AccountViewController: AccountViewProtocol {
    
    func showLoading() {
        loginButton.isHidden = true
        loadingIndicator.startAnimating()
    }
    
    func hideLoading() {
        loadingIndicator.stopAnimating()
    }
    
    func showError(message: String) {
        let alert = UIAlertController(title: "错误", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
    
    func render(_ account: AccountResponse) {
        let state = account.isLoggedIn ? "已登录" : "未登录"
        statusLabel.text = "\(account.displayName) · \(state)"
        statsLabel.text = account.stats.joined(separator: " · ")
        avatarImageView.isHidden = !account.isLoggedIn
        loginButton.isHidden = account.isLoggedIn

        if account.isLoggedIn {
            avatarLoader.loadAvatar(
                into: avatarImageView,
                postID: account.profileURL?.lastPathComponent ?? account.displayName,
                avatarURL: account.avatarURL
            )
        } else {
            avatarLoader.cancel(on: avatarImageView)
        }
    }
}
