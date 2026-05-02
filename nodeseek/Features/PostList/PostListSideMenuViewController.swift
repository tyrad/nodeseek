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
    var onRecentVisitedTapped: (() -> Void)?
    #if DEBUG
    var onLogFileTapped: (() -> Void)?
    var onDetailTestTapped: (() -> Void)?
    #endif
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

    private let recentVisitedButton: UIButton = {
        let button = UIButton(type: .system)
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "clock.arrow.circlepath", withConfiguration: symbolConfiguration)
        configuration.imagePadding = 10
        configuration.baseForegroundColor = .label
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
        configuration.title = "最近浏览"
        button.configuration = configuration
        button.contentHorizontalAlignment = .leading
        button.accessibilityIdentifier = "post-list-side-menu-recent-visited-button"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    #if DEBUG
    private let accountDebugTextView: UITextView = {
        let textView = UITextView()
        textView.text = "账号调试日志：等待侧栏刷新"
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textColor = .secondaryLabel
        textView.backgroundColor = .secondarySystemBackground
        textView.layer.cornerRadius = 6
        textView.layer.masksToBounds = true
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        textView.accessibilityIdentifier = "post-list-side-menu-account-debug-text-view"
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }()

    private let accountDebugCopyButton: UIButton = {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "doc.on.doc")
        configuration.imagePadding = 6
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
        configuration.title = "复制日志"
        button.configuration = configuration
        button.accessibilityIdentifier = "post-list-side-menu-account-debug-copy-button"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    #endif

    #if DEBUG
    private let logFileButton: UIButton = {
        let button = UIButton(type: .system)
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "doc.text", withConfiguration: symbolConfiguration)
        configuration.imagePadding = 10
        configuration.baseForegroundColor = .label
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
        configuration.title = "文件日志"
        button.configuration = configuration
        button.contentHorizontalAlignment = .leading
        button.accessibilityIdentifier = "post-list-side-menu-log-file-button"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let detailTestButton: UIButton = {
        let button = UIButton(type: .system)
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "doc.text.magnifyingglass", withConfiguration: symbolConfiguration)
        configuration.imagePadding = 10
        configuration.baseForegroundColor = .label
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
        configuration.title = "详情测试"
        button.configuration = configuration
        button.contentHorizontalAlignment = .leading
        button.accessibilityIdentifier = "post-list-side-menu-detail-test-button"
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = !NodeSeekDebugConfig.enablePostDetailTestEntry
        return button
    }()
    #endif

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
        accountHeaderButton.isEnabled = !account.isLoggedIn

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
        #if DEBUG
        accountController.onDebugTextChanged = { [weak self] text in
            self?.accountDebugTextView.text = text
        }
        #endif
    }

    private func setupUI() {
        view.backgroundColor = .clear
        view.isHidden = true
        backdropView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(backdropTapped)))
        accountHeaderButton.addTarget(self, action: #selector(accountHeaderTapped), for: .touchUpInside)
        #if DEBUG
        accountDebugCopyButton.addTarget(self, action: #selector(copyAccountDebugLogTapped), for: .touchUpInside)
        logFileButton.addTarget(self, action: #selector(logFileButtonTapped), for: .touchUpInside)
        if NodeSeekDebugConfig.enablePostDetailTestEntry {
            detailTestButton.addTarget(self, action: #selector(detailTestButtonTapped), for: .touchUpInside)
        }
        #endif
        settingsButton.addTarget(self, action: #selector(settingsButtonTapped), for: .touchUpInside)
        recentVisitedButton.addTarget(self, action: #selector(recentVisitedButtonTapped), for: .touchUpInside)

        view.addSubview(backdropView)
        view.addSubview(sideMenuView)
        sideMenuView.addSubview(avatarImageView)
        sideMenuView.addSubview(nameLabel)
        sideMenuView.addSubview(statsLabel)
        sideMenuView.addSubview(accountHeaderButton)
        #if DEBUG
        sideMenuView.addSubview(accountDebugCopyButton)
        sideMenuView.addSubview(accountDebugTextView)
        #endif
        #if DEBUG
        if NodeSeekDebugConfig.enablePostDetailTestEntry {
            sideMenuView.addSubview(detailTestButton)
        }
        sideMenuView.addSubview(logFileButton)
        #endif
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
            recentVisitedButton.heightAnchor.constraint(equalToConstant: 48)
        ])

        #if DEBUG
        NSLayoutConstraint.activate([
            logFileButton.leadingAnchor.constraint(equalTo: sideMenuView.leadingAnchor, constant: SideMenuLayout.horizontalInset),
            logFileButton.trailingAnchor.constraint(equalTo: sideMenuView.trailingAnchor, constant: -SideMenuLayout.horizontalInset),
            logFileButton.bottomAnchor.constraint(equalTo: recentVisitedButton.topAnchor, constant: -8),
            logFileButton.heightAnchor.constraint(equalToConstant: 48),

            accountDebugCopyButton.trailingAnchor.constraint(equalTo: sideMenuView.trailingAnchor, constant: -SideMenuLayout.horizontalInset),
            accountDebugCopyButton.topAnchor.constraint(equalTo: accountHeaderButton.bottomAnchor, constant: 14),
            accountDebugCopyButton.heightAnchor.constraint(equalToConstant: 32),

            accountDebugTextView.leadingAnchor.constraint(equalTo: sideMenuView.leadingAnchor, constant: SideMenuLayout.horizontalInset),
            accountDebugTextView.trailingAnchor.constraint(equalTo: sideMenuView.trailingAnchor, constant: -SideMenuLayout.horizontalInset),
            accountDebugTextView.topAnchor.constraint(equalTo: accountDebugCopyButton.bottomAnchor, constant: 6),
            accountDebugTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
            accountDebugTextView.bottomAnchor.constraint(lessThanOrEqualTo: logFileButton.topAnchor, constant: -12)
        ])
        #endif

        #if DEBUG
        if NodeSeekDebugConfig.enablePostDetailTestEntry {
            NSLayoutConstraint.activate([
                detailTestButton.leadingAnchor.constraint(equalTo: sideMenuView.leadingAnchor, constant: SideMenuLayout.horizontalInset),
                detailTestButton.trailingAnchor.constraint(equalTo: sideMenuView.trailingAnchor, constant: -SideMenuLayout.horizontalInset),
                detailTestButton.bottomAnchor.constraint(equalTo: logFileButton.topAnchor, constant: -8),
                detailTestButton.heightAnchor.constraint(equalToConstant: 48),
                accountDebugTextView.bottomAnchor.constraint(lessThanOrEqualTo: detailTestButton.topAnchor, constant: -12)
            ])
        }
        #endif
    }

    @objc private func backdropTapped() {
        hide(animated: true)
    }

    @objc private func accountHeaderTapped() {
        guard !accountController.isLoggedIn else { return }
        hide(animated: true)
        onLoginTapped?()
    }

    #if DEBUG
    @objc private func copyAccountDebugLogTapped() {
        UIPasteboard.general.string = accountController.debugText
        accountDebugCopyButton.configuration?.title = "已复制"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.accountDebugCopyButton.configuration?.title = "复制日志"
        }
    }

    @objc private func logFileButtonTapped() {
        hide(animated: true)
        onLogFileTapped?()
    }

    @objc private func detailTestButtonTapped() {
        hide(animated: true)
        onDetailTestTapped?()
    }
    #endif

    @objc private func settingsButtonTapped() {
        hide(animated: true)
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
