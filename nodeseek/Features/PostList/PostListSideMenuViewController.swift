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
    var onAccountProfileTapped: ((URL) -> Void)?
    var onNewDiscussionTapped: (() -> Void)?
    var onRecentVisitedTapped: (() -> Void)?
    var onSettingsTapped: (() -> Void)?
    private let accountController: PostListSideMenuAccountController
    private let avatarLoader = AvatarImageLoader.shared

    private static let defaultAvatarImage: UIImage? = {
        let configuration = UIImage.SymbolConfiguration(pointSize: 48, weight: .regular)
        return UIImage(systemName: "person.crop.circle.fill", withConfiguration: configuration)
    }()

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
        imageView.image = PostListSideMenuViewController.defaultAvatarImage
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

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.text = "未登录"
        label.font = .preferredFont(forTextStyle: .headline)
        label.textColor = .label
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.accessibilityIdentifier = "post-list-side-menu-name-label"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let statsLabel: UILabel = {
        let label = UILabel()
        label.text = "登录后同步账号信息"
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        label.accessibilityIdentifier = "post-list-side-menu-stats-label"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let accountHeaderButton: UIButton = {
        let button = UIButton(type: .custom)
        button.backgroundColor = .clear
        button.accessibilityIdentifier = "post-list-side-menu-account-header-button"
        button.accessibilityLabel = "登录账号"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let settingsButton: UIButton = {
        let button = PostListSideMenuViewController.makeMenuButton(title: "设置", systemImageName: "gearshape")
        button.accessibilityIdentifier = "post-list-side-menu-settings-button"
        return button
    }()

    private let recentVisitedButton: UIButton = {
        let button = PostListSideMenuViewController.makeMenuButton(title: "最近浏览", systemImageName: "clock.arrow.circlepath")
        button.accessibilityIdentifier = "post-list-side-menu-recent-visited-button"
        return button
    }()

    private let newDiscussionButton: UIButton = {
        let button = PostListSideMenuViewController.makeMenuButton(title: "发帖", systemImageName: "square.and.pencil")
        button.accessibilityIdentifier = "post-list-side-menu-new-discussion-button"
        return button
    }()

    init(
        currentAccountStore: CurrentAccountStore = .shared,
        accountRefresher: (any CurrentAccountRefreshing)? = nil,
        refreshMaxAge: TimeInterval = 60
    ) {
        self.accountController = PostListSideMenuAccountController(
            currentAccountStore: currentAccountStore,
            accountRefresher: accountRefresher,
            refreshMaxAge: refreshMaxAge
        )
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        configureAccountController()
        accountController.start()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        avatarImageView.layer.cornerRadius = avatarImageView.bounds.width / 2
    }

    private static func makeMenuButton(title: String, systemImageName: String) -> UIButton {
        let button = UIButton(type: .system)
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: systemImageName, withConfiguration: symbolConfiguration)
        configuration.imagePadding = 10
        configuration.baseForegroundColor = .label
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
        configuration.title = title
        button.configuration = configuration
        button.contentHorizontalAlignment = .leading
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    func show(animated: Bool) {
        accountController.refreshIfNeeded()
        setVisible(true, animated: animated)
    }

    func hide(animated: Bool) {
        setVisible(false, animated: animated)
    }

    private func renderAccount(_ account: AccountResponse) {
        nameLabel.text = account.isLoggedIn ? account.displayName : "未登录"
        statsLabel.text = account.isLoggedIn
            ? account.stats.prefix(3).joined(separator: " · ")
            : "登录后同步账号信息"
        accountHeaderButton.accessibilityLabel = account.isLoggedIn ? "账号信息" : "登录账号"
        accountHeaderButton.isEnabled = !account.isLoggedIn || account.profileURL != nil

        if account.isLoggedIn {
            avatarLoader.loadAvatar(
                into: avatarImageView,
                postID: account.profileURL?.lastPathComponent ?? account.displayName,
                avatarURL: account.avatarURL
            )
        } else {
            avatarLoader.cancel(on: avatarImageView)
            avatarImageView.image = Self.defaultAvatarImage
            avatarImageView.tintColor = .tertiaryLabel
        }
    }

    private func configureAccountController() {
        accountController.canRefresh = { [weak self] in
            self?.view.window != nil
        }
        accountController.isSideMenuVisible = { [weak self] in
            self?.isSideMenuVisible == true
        }
        accountController.onAccountChanged = { [weak self] account in
            self?.renderAccount(account)
        }
    }

    private func setupUI() {
        view.backgroundColor = .clear
        view.isHidden = true
        backdropView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(backdropTapped)))
        accountHeaderButton.addTarget(self, action: #selector(accountHeaderTapped), for: .touchUpInside)
        settingsButton.addTarget(self, action: #selector(settingsButtonTapped), for: .touchUpInside)
        newDiscussionButton.addTarget(self, action: #selector(newDiscussionButtonTapped), for: .touchUpInside)
        recentVisitedButton.addTarget(self, action: #selector(recentVisitedButtonTapped), for: .touchUpInside)

        view.addSubview(backdropView)
        view.addSubview(sideMenuView)
        sideMenuView.addSubview(avatarImageView)
        sideMenuView.addSubview(nameLabel)
        sideMenuView.addSubview(statsLabel)
        sideMenuView.addSubview(accountHeaderButton)
        sideMenuView.addSubview(newDiscussionButton)
        sideMenuView.addSubview(recentVisitedButton)
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

            nameLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 14),
            nameLabel.trailingAnchor.constraint(equalTo: sideMenuView.trailingAnchor, constant: -SideMenuLayout.horizontalInset),
            nameLabel.topAnchor.constraint(equalTo: avatarImageView.topAnchor, constant: 8),

            statsLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            statsLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            statsLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 6),

            accountHeaderButton.leadingAnchor.constraint(equalTo: avatarImageView.leadingAnchor),
            accountHeaderButton.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            accountHeaderButton.topAnchor.constraint(equalTo: avatarImageView.topAnchor, constant: -8),
            accountHeaderButton.bottomAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: 8),

            settingsButton.leadingAnchor.constraint(equalTo: sideMenuView.leadingAnchor, constant: SideMenuLayout.horizontalInset),
            settingsButton.trailingAnchor.constraint(equalTo: sideMenuView.trailingAnchor, constant: -SideMenuLayout.horizontalInset),
            settingsButton.bottomAnchor.constraint(equalTo: sideMenuView.safeAreaLayoutGuide.bottomAnchor, constant: -18),
            settingsButton.heightAnchor.constraint(equalToConstant: 48),

            recentVisitedButton.leadingAnchor.constraint(equalTo: sideMenuView.leadingAnchor, constant: SideMenuLayout.horizontalInset),
            recentVisitedButton.trailingAnchor.constraint(equalTo: sideMenuView.trailingAnchor, constant: -SideMenuLayout.horizontalInset),
            recentVisitedButton.bottomAnchor.constraint(equalTo: settingsButton.topAnchor, constant: -8),
            recentVisitedButton.heightAnchor.constraint(equalToConstant: 48),

            newDiscussionButton.leadingAnchor.constraint(equalTo: sideMenuView.leadingAnchor, constant: SideMenuLayout.horizontalInset),
            newDiscussionButton.trailingAnchor.constraint(equalTo: sideMenuView.trailingAnchor, constant: -SideMenuLayout.horizontalInset),
            newDiscussionButton.bottomAnchor.constraint(equalTo: recentVisitedButton.topAnchor, constant: -8),
            newDiscussionButton.heightAnchor.constraint(equalToConstant: 48)
        ])
    }

    @objc private func backdropTapped() {
        hide(animated: true)
    }

    @objc private func accountHeaderTapped() {
        if accountController.isLoggedIn {
            guard let profileURL = accountController.profileURL else { return }
            hide(animated: true)
            onAccountProfileTapped?(profileURL)
            return
        }

        hide(animated: true)
        onLoginTapped?()
    }

    @objc private func settingsButtonTapped() {
        hide(animated: true)
        onSettingsTapped?()
    }

    @objc private func newDiscussionButtonTapped() {
        hide(animated: true)
        onNewDiscussionTapped?()
    }

    @objc private func recentVisitedButtonTapped() {
        hide(animated: true)
        onRecentVisitedTapped?()
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

        let shouldAnimate = animated && UIView.areAnimationsEnabled
        guard shouldAnimate else {
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
