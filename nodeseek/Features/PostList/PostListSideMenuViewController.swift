//
//  PostListSideMenuViewController.swift
//  nodeseek
//
//  Created by Codex on 2026/4/29.
//

import UIKit

final class PostListSideMenuViewController: UIViewController {
    private var sideMenuLeadingConstraint: NSLayoutConstraint?
    private var isSideMenuVisible = false
    var onLoginTapped: (() -> Void)?

    private let backdropView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.22)
        view.alpha = 0
        view.isHidden = true
        view.accessibilityIdentifier = "post-list-side-menu-backdrop"
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let sideMenuView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.14
        view.layer.shadowRadius = 18
        view.layer.shadowOffset = CGSize(width: 4, height: 0)
        view.accessibilityIdentifier = "post-list-side-menu"
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let avatarImageView: UIImageView = {
        let imageView = UIImageView()
        let configuration = UIImage.SymbolConfiguration(pointSize: 48, weight: .regular)
        imageView.image = UIImage(systemName: "person.crop.circle.fill", withConfiguration: configuration)
        imageView.tintColor = .tertiaryLabel
        imageView.backgroundColor = .secondarySystemBackground
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = SideMenuLayout.avatarSize / 2
        imageView.isUserInteractionEnabled = true
        imageView.accessibilityIdentifier = "post-list-side-menu-avatar"
        imageView.accessibilityLabel = "用户头像"
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let settingsButton: UIButton = {
        let button = UIButton(type: .system)
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "gearshape", withConfiguration: symbolConfiguration)
        configuration.imagePadding = 10
        configuration.baseForegroundColor = .label
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
        configuration.title = "设置"
        button.configuration = configuration
        button.contentHorizontalAlignment = .leading
        button.accessibilityIdentifier = "post-list-side-menu-settings-button"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let loginButton: UIButton = {
        let button = UIButton(type: .system)
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: "person.badge.key", withConfiguration: symbolConfiguration)
        configuration.imagePadding = 10
        configuration.baseBackgroundColor = .label
        configuration.baseForegroundColor = .systemBackground
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
        configuration.title = "登录"
        configuration.cornerStyle = .medium
        button.configuration = configuration
        button.contentHorizontalAlignment = .leading
        button.accessibilityIdentifier = "post-list-side-menu-login-button"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        avatarImageView.layer.cornerRadius = avatarImageView.bounds.width / 2
    }

    func show(animated: Bool) {
        setVisible(true, animated: animated)
    }

    func hide(animated: Bool) {
        setVisible(false, animated: animated)
    }

    private func setupUI() {
        view.backgroundColor = .clear
        view.isHidden = true
        backdropView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(backdropTapped)))
        avatarImageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(avatarTapped)))
        loginButton.addTarget(self, action: #selector(loginButtonTapped), for: .touchUpInside)
        settingsButton.addTarget(self, action: #selector(settingsButtonTapped), for: .touchUpInside)

        view.addSubview(backdropView)
        view.addSubview(sideMenuView)
        sideMenuView.addSubview(avatarImageView)
        sideMenuView.addSubview(loginButton)
        sideMenuView.addSubview(settingsButton)

        let sideMenuLeadingConstraint = sideMenuView.leadingAnchor.constraint(
            equalTo: view.leadingAnchor,
            constant: -SideMenuLayout.width
        )
        self.sideMenuLeadingConstraint = sideMenuLeadingConstraint

        NSLayoutConstraint.activate([
            backdropView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdropView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backdropView.topAnchor.constraint(equalTo: view.topAnchor),
            backdropView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            sideMenuLeadingConstraint,
            sideMenuView.topAnchor.constraint(equalTo: view.topAnchor),
            sideMenuView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sideMenuView.widthAnchor.constraint(equalToConstant: SideMenuLayout.width),

            avatarImageView.leadingAnchor.constraint(equalTo: sideMenuView.leadingAnchor, constant: SideMenuLayout.horizontalInset),
            avatarImageView.topAnchor.constraint(equalTo: sideMenuView.safeAreaLayoutGuide.topAnchor, constant: 28),
            avatarImageView.widthAnchor.constraint(equalToConstant: SideMenuLayout.avatarSize),
            avatarImageView.heightAnchor.constraint(equalToConstant: SideMenuLayout.avatarSize),

            loginButton.leadingAnchor.constraint(equalTo: sideMenuView.leadingAnchor, constant: SideMenuLayout.horizontalInset),
            loginButton.trailingAnchor.constraint(equalTo: sideMenuView.trailingAnchor, constant: -SideMenuLayout.horizontalInset),
            loginButton.topAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: 24),
            loginButton.heightAnchor.constraint(equalToConstant: 48),

            settingsButton.leadingAnchor.constraint(equalTo: sideMenuView.leadingAnchor, constant: SideMenuLayout.horizontalInset),
            settingsButton.trailingAnchor.constraint(equalTo: sideMenuView.trailingAnchor, constant: -SideMenuLayout.horizontalInset),
            settingsButton.bottomAnchor.constraint(equalTo: sideMenuView.safeAreaLayoutGuide.bottomAnchor, constant: -18),
            settingsButton.heightAnchor.constraint(equalToConstant: 48)
        ])
    }

    @objc private func backdropTapped() {
        hide(animated: true)
    }

    @objc private func avatarTapped() {
        hide(animated: true)
    }

    @objc private func loginButtonTapped() {
        hide(animated: true)
        onLoginTapped?()
    }

    @objc private func settingsButtonTapped() {
        hide(animated: true)
    }

    private func setVisible(_ visible: Bool, animated: Bool) {
        guard visible != isSideMenuVisible else { return }
        isSideMenuVisible = visible
        if visible {
            view.isHidden = false
            backdropView.isHidden = false
        }

        sideMenuLeadingConstraint?.constant = visible ? 0 : -SideMenuLayout.width
        let animations = { [weak self] in
            self?.backdropView.alpha = visible ? 1 : 0
            self?.view.layoutIfNeeded()
        }
        let completion: (Bool) -> Void = { [weak self] _ in
            guard let self else { return }
            self.view.isHidden = !self.isSideMenuVisible
            self.backdropView.isHidden = !self.isSideMenuVisible
        }

        guard animated else {
            animations()
            completion(true)
            return
        }
        UIView.animate(
            withDuration: 0.25,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState],
            animations: animations,
            completion: completion
        )
    }
}

private enum SideMenuLayout {
    static let width: CGFloat = 286
    static let horizontalInset: CGFloat = 22
    static let avatarSize: CGFloat = 72
}
