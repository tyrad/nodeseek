//
//  MeViewController.swift
//  nodeseek
//

import UIKit

/// 多 Tab 模式的“我的”页：资料卡（账号 + 五格数字 + 升级进度）、我的内容、签到与最近浏览，设置在右上角。
final class MeViewController: UIViewController {
    private enum Layout {
        static let horizontalInset: CGFloat = 16
        static let groupSpacing: CGFloat = 12
    }

    private let accountController: PostListSideMenuAccountController
    private let client: NodeSeekUserContentClient
    private let notificationClient: NodeSeekNotificationClientProtocol
    private let router = PostListRouter()
    private let visitedStore: VisitedPostStoreProtocol

    private var account = AccountResponse(displayName: "游客", isLoggedIn: false)
    private var profile: UserProfileRecord?
    private var progress: UserTodayProgressRecord?
    private var loadTask: Task<Void, Never>?
    private var loadingUID: Int?
    private var unreadCountTask: Task<Void, Never>?
    /// 登录页是 push 进来的，关闭时本页还不在 window 上，所以用出现/消失自己记可见状态
    private var isPageVisible = false

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let profileCard = MeProfileCardView()
    private let discussionsRow = MeListRowView(symbolName: "doc.text", title: "我的帖子")
    private let commentsRow = MeListRowView(symbolName: "bubble.left", title: "我的评论")
    private let collectionsRow = MeListRowView(symbolName: "bookmark", title: "我的收藏")
    private let checkInRow = MeListRowView(symbolName: "checkmark.seal", title: "每日签到")
    private let recentRow = MeListRowView(symbolName: "clock.arrow.circlepath", title: "最近浏览")

    init(
        accountController: PostListSideMenuAccountController? = nil,
        client: NodeSeekUserContentClient? = nil,
        notificationClient: NodeSeekNotificationClientProtocol? = nil,
        visitedStore: VisitedPostStoreProtocol? = nil
    ) {
        self.accountController = accountController ?? PostListSideMenuAccountController()
        self.client = client ?? NodeSeekUserContentClient()
        self.notificationClient = notificationClient ?? NodeSeekNotificationClient()
        self.visitedStore = visitedStore ?? VisitedPostStore.shared
        super.init(nibName: nil, bundle: nil)
        title = "我的"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
        unreadCountTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        router.viewController = self
        view.backgroundColor = UIColor.systemGroupedBackground
        view.accessibilityIdentifier = "me-page"
        setupNavigationItem()
        setupLayout()
        setupActions()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appTextSizeDidChange),
            name: AppTextSizeSettings.didChangeNotification,
            object: nil
        )
        appTextSizeDidChange()
        render()

        // 刷新只由本页出现和登录关闭触发；不能用 view.window 判断，
        // 出现回调和登录关闭时本页都还不在 window 上，会把刷新丢掉
        accountController.canRefresh = { true }
        accountController.isSideMenuVisible = { [weak self] in
            self?.isPageVisible ?? false
        }
        accountController.onAccountChanged = { [weak self] account in
            self?.accountDidChange(account)
        }
        accountController.start()
    }

    @objc private func appTextSizeDidChange() {
        profileCard.updateTextSize()
        [discussionsRow, commentsRow, collectionsRow, recentRow].forEach { $0.updateTextSize() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isPageVisible = true
        // 每次出现都刷新：账号走缓存（登录后已标记过期），资料与通知未读数直接请求
        accountController.refreshIfNeeded()
        loadProfile()
        refreshNotificationUnreadCount()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        isPageVisible = false
    }

    // MARK: - Setup

    private func setupNavigationItem() {
        let settingsItem = UIBarButtonItem(
            image: UIImage(systemName: "gearshape"),
            style: .plain,
            target: self,
            action: #selector(settingsTapped)
        )
        settingsItem.accessibilityLabel = "设置"
        settingsItem.accessibilityIdentifier = "me-settings-button"
        navigationItem.rightBarButtonItem = settingsItem
        navigationController?.navigationBar.tintColor = .label
    }

    private func setupLayout() {
        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = Layout.groupSpacing
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        contentStack.addArrangedSubview(profileCard)
        contentStack.setCustomSpacing(22, after: profileCard)
        let contentHeader = Self.makeSectionHeader("我的内容")
        contentStack.addArrangedSubview(contentHeader)
        contentStack.setCustomSpacing(7, after: contentHeader)
        contentStack.addArrangedSubview(Self.makeGroup([discussionsRow, commentsRow, collectionsRow]))
        contentStack.addArrangedSubview(Self.makeGroup([checkInRow, recentRow]))

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: Layout.horizontalInset),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -Layout.horizontalInset),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 12),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24)
        ])
    }

    private func setupActions() {
        profileCard.onTap = { [weak self] in self?.profileCardTapped() }
        profileCard.onLoginTap = { [weak self] in self?.showLogin() }
        discussionsRow.addTarget(self, action: #selector(discussionsTapped), for: .touchUpInside)
        commentsRow.addTarget(self, action: #selector(commentsTapped), for: .touchUpInside)
        collectionsRow.addTarget(self, action: #selector(collectionsTapped), for: .touchUpInside)
        checkInRow.addTarget(self, action: #selector(checkInTapped), for: .touchUpInside)
        recentRow.addTarget(self, action: #selector(recentTapped), for: .touchUpInside)
        discussionsRow.accessibilityIdentifier = "me-discussions-row"
        commentsRow.accessibilityIdentifier = "me-comments-row"
        collectionsRow.accessibilityIdentifier = "me-collections-row"
        checkInRow.accessibilityIdentifier = "me-check-in-row"
        recentRow.accessibilityIdentifier = "me-recent-row"
    }

    // MARK: - Data

    private func accountDidChange(_ account: AccountResponse) {
        let uidChanged = account.nodeSeekUID != self.account.nodeSeekUID
        self.account = account
        if uidChanged || account.isLoggedIn == false {
            profile = nil
            progress = nil
        }
        render()
        // 登录、退出或切换账号后，资料和通知角标跟着更新
        if uidChanged {
            loadProfile()
            refreshNotificationUnreadCount()
        }
    }

    private func loadProfile() {
        guard account.isLoggedIn, let uid = account.nodeSeekUID else {
            loadTask?.cancel()
            loadingUID = nil
            return
        }
        // 同一账号已在请求中就不重复发
        guard loadingUID != uid else { return }
        loadTask?.cancel()
        loadingUID = uid
        loadTask = Task { [weak self, client] in
            defer {
                if Task.isCancelled == false { self?.loadingUID = nil }
            }
            // 资料和今日进度并行请求；进度失败不影响资料展示，只是不显示今日摘要
            async let progressResult = try? client.loadTodayProgress(uid: uid)
            do {
                let profile = try await client.loadProfile(uid: uid)
                guard !Task.isCancelled, let self else { return }
                self.profile = profile
                self.render()
                let progress = await progressResult
                guard !Task.isCancelled else { return }
                self.progress = progress
                self.render()
            } catch {
                guard !Task.isCancelled else { return }
                AppLog.warning(.account, "我的页资料加载失败: \(error.localizedDescription)")
            }
        }
    }

    /// 通知 Tab 角标靠未读数事件更新；首页不在前台时由本页补一次。
    private func refreshNotificationUnreadCount() {
        guard account.isLoggedIn, unreadCountTask == nil else { return }
        unreadCountTask = Task { [weak self, notificationClient] in
            defer { self?.unreadCountTask = nil }
            do {
                let unreadCount = try await notificationClient.loadUnreadCount()
                guard !Task.isCancelled else { return }
                NodeSeekNotificationUnreadCountEvent.post(unreadCount)
            } catch {
                AppLog.debug(.account, "我的页通知未读数加载失败: \(error.localizedDescription)")
            }
        }
    }

    private func render() {
        guard isViewLoaded else { return }
        if account.isLoggedIn {
            profileCard.renderLoggedIn(account: account, profile: profile, progress: progress)
        } else {
            profileCard.renderGuest()
        }

        let loggedIn = account.isLoggedIn
        discussionsRow.setValue(loggedIn ? profile.map { "\($0.postCount)" } : nil)
        commentsRow.setValue(loggedIn ? profile.map { "\($0.commentCount)" } : nil)
        collectionsRow.setValue(loggedIn ? profile?.collectionCount.map { "\($0)" } : nil)
        recentRow.setValue(nil)

        if loggedIn, let gain = progress?.checkInGain {
            checkInRow.setValue("今日 +\(gain) 鸡腿")
        } else {
            checkInRow.setAction(title: "签到")
        }
    }

    // MARK: - Actions

    private func profileCardTapped() {
        guard account.isLoggedIn else {
            showLogin()
            return
        }
        if let profileURL = account.profileURL {
            router.navigateToUserProfile(profileURL: profileURL)
        }
    }

    @objc private func discussionsTapped() {
        guard requireLogin() else { return }
        router.navigateToUserDiscussions()
    }

    @objc private func commentsTapped() {
        guard requireLogin() else { return }
        router.navigateToUserComments()
    }

    @objc private func collectionsTapped() {
        guard requireLogin() else { return }
        router.navigateToUserCollections()
    }

    @objc private func checkInTapped() {
        guard requireLogin() else { return }
        // 签到在网页签到页完成，返回本页时会重新加载今日签到结果
        router.navigateToCheckIn(boardURL: NodeSeekSite.boardURL)
    }

    @objc private func recentTapped() {
        router.navigateToRecentVisitedPosts(visitedStore: visitedStore)
    }

    /// 未登录时转去登录，返回是否可继续。
    private func requireLogin() -> Bool {
        guard account.isLoggedIn else {
            showLogin()
            return false
        }
        return true
    }

    private func showLogin() {
        router.navigateToLogin { [weak self] in
            // 登录页关闭时已把账号写进缓存，先用缓存立刻切换，再后台强制刷新确认
            Task { [weak self] in
                guard let account = await CurrentAccountStore.shared.snapshot()?.account,
                      account.isLoggedIn else { return }
                self?.accountDidChange(account)
            }
            self?.accountController.refreshIfNeeded(force: true)
            self?.reloadHomeList()
        }
    }

    @objc private func settingsTapped() {
        router.navigateToSettings(
            onLogout: { [weak self] in
                NodeSeekNotificationUnreadCountEvent.post(.zero)
                // 本地账号已清掉，先直接切到未登录，不等网络确认
                self?.accountDidChange(AccountResponse(displayName: "游客", isLoggedIn: false))
                self?.accountController.refreshIfNeeded(force: true)
                self?.reloadHomeList()
            },
            onLogFile: { [weak self] in
                self?.router.navigateToLogFile()
            },
            onDetailTest: nil
        )
    }

    /// 登录状态变化后刷新首页列表（未登录看不到部分分类内容）。
    private func reloadHomeList() {
        let homeNavigation = tabBarController?.viewControllers?.first as? UINavigationController
        (homeNavigation?.viewControllers.first as? PostListViewProtocol)?.reloadSelectedCategory()
    }

    // MARK: - Factory

    private static func makeSectionHeader(_ title: String) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        let container = UIView()
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: container.topAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    /// 圆角分组卡片，行之间加缩进分隔线。
    private static func makeGroup(_ rows: [MeListRowView]) -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.backgroundColor = .secondarySystemGroupedBackground
        stack.layer.cornerRadius = 16
        stack.layer.cornerCurve = .continuous
        stack.clipsToBounds = true
        for (index, row) in rows.enumerated() {
            row.showsSeparator = index > 0
            stack.addArrangedSubview(row)
        }
        return stack
    }
}

// MARK: - 资料卡

/// 账号 + 五格数字 + 升级进度合成一张卡，整卡可点；未登录时显示登录引导。
private final class MeProfileCardView: UIControl {
    var onTap: (() -> Void)?
    var onLoginTap: (() -> Void)?

    private static let defaultAvatarImage = UIImage(
        systemName: "person",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .regular)
    )

    private let headerView = UIView()
    private let avatarImageView = UIImageView()
    private let nameLabel = UILabel()
    private let metaLabel = UILabel()
    private let chevronView = UIImageView(image: UIImage(systemName: "chevron.right"))
    private let loginButton = UIButton(type: .system)

    private let statsSeparator = MeSeparatorView()
    private let statsStack = UIStackView()
    private let statViews: [MeStatView] = ["等级", "鸡腿", "星辰", "粉丝", "关注"].map { MeStatView(title: $0) }

    private let levelSeparator = MeSeparatorView()
    private let levelContainer = UIView()
    private let levelTitleLabel = UILabel()
    private let todayLabel = UILabel()
    private let levelBar = MeProgressBar()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        accessibilityIdentifier = "me-profile-card"
        isAccessibilityElement = true
        accessibilityTraits = .button
        addTarget(self, action: #selector(cardTapped), for: .touchUpInside)
        setupHeader()
        setupStats()
        setupLevel()

        let stack = UIStackView(arrangedSubviews: [headerView, statsSeparator, statsStack, levelSeparator, levelContainer])
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            guard oldValue != isHighlighted else { return }
            UIView.animate(withDuration: isHighlighted ? 0.05 : 0.2) {
                self.backgroundColor = self.isHighlighted ? .tertiarySystemGroupedBackground : .secondarySystemGroupedBackground
            }
        }
    }

    /// 除了“登录”按钮，卡片内任意位置的点按都交给整卡处理。
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hitView = super.hitTest(point, with: event) else { return nil }
        if loginButton.isHidden == false, hitView.isDescendant(of: loginButton) {
            return hitView
        }
        return self
    }

    func renderLoggedIn(account: AccountResponse, profile: UserProfileRecord?, progress: UserTodayProgressRecord?) {
        nameLabel.text = profile?.name ?? account.displayName
        if let profile {
            var parts = ["UID \(profile.uid)"]
            if let days = profile.joinedDays() { parts.append("加入 \(days) 天") }
            metaLabel.text = parts.joined(separator: " · ")
        } else {
            metaLabel.text = account.stats.prefix(2).joined(separator: " · ")
        }
        chevronView.isHidden = false
        loginButton.isHidden = true

        ImageLoad.url(account.avatarURL)
            .toAvatar(requestID: account.profileURL?.lastPathComponent ?? account.displayName)
            .into(avatarImageView)

        let values: [String] = profile.map {
            ["Lv \($0.rank)", "\($0.coin)", "\($0.stardust)", "\($0.fans)", "\($0.follows)"]
        } ?? Array(repeating: "–", count: 5)
        zip(statViews, values).forEach { $0.setValue($1) }
        updateAccessibility(loggedIn: true)
        statsSeparator.isHidden = false
        statsStack.isHidden = false

        if let profile {
            let level = profile.levelProgress
            levelTitleLabel.text = level.isMaxRank
                ? "Lv \(level.rank) 已满级"
                : "距 Lv \(level.nextRank) 还差 \(level.remaining) 鸡腿"
            levelBar.fraction = level.fraction
            todayLabel.text = progress.map {
                "今日 评论 \($0.commentBonusCount)/\($0.maxCommentBonusCount) · 发帖 \($0.postBonusCount)/\($0.maxPostBonusCount)"
            }
            levelSeparator.isHidden = false
            levelContainer.isHidden = false
        } else {
            levelSeparator.isHidden = true
            levelContainer.isHidden = true
        }
    }

    func renderGuest() {
        nameLabel.text = "未登录"
        metaLabel.text = "登录后查看等级、鸡腿和今日进度"
        chevronView.isHidden = true
        loginButton.isHidden = false
        updateAccessibility(loggedIn: false)
        AvatarImageLoader.shared.cancel(on: avatarImageView)
        avatarImageView.image = Self.defaultAvatarImage
        statsSeparator.isHidden = true
        statsStack.isHidden = true
        levelSeparator.isHidden = true
        levelContainer.isHidden = true
    }

    // MARK: Setup

    func updateTextSize() {
        nameLabel.font = AppTypography.font(basePointSize: 22, weight: .bold)
        metaLabel.font = AppTypography.font(basePointSize: 13)
    }

    private func setupHeader() {
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.layer.cornerRadius = 16
        avatarImageView.layer.cornerCurve = .continuous
        avatarImageView.backgroundColor = .tertiarySystemFill
        avatarImageView.tintColor = .tertiaryLabel
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = .systemFont(ofSize: 22, weight: .bold)
        nameLabel.textColor = ReadingColors.text
        metaLabel.font = .systemFont(ofSize: 13)
        metaLabel.textColor = .secondaryLabel
        metaLabel.numberOfLines = 2

        chevronView.tintColor = .tertiaryLabel
        chevronView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        chevronView.setContentHuggingPriority(.required, for: .horizontal)

        var configuration = UIButton.Configuration.filled()
        configuration.baseBackgroundColor = .label
        configuration.baseForegroundColor = .systemBackground
        configuration.cornerStyle = .capsule
        configuration.title = "登录"
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 15, weight: .semibold)
            return outgoing
        }
        loginButton.configuration = configuration
        loginButton.accessibilityIdentifier = "me-login-button"
        loginButton.setContentHuggingPriority(.required, for: .horizontal)
        loginButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        loginButton.addTarget(self, action: #selector(loginTapped), for: .touchUpInside)

        let textStack = UIStackView(arrangedSubviews: [nameLabel, metaLabel])
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.isUserInteractionEnabled = false

        let row = UIStackView(arrangedSubviews: [avatarImageView, textStack, chevronView, loginButton])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 14
        row.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.isUserInteractionEnabled = false
        chevronView.isUserInteractionEnabled = false
        headerView.addSubview(row)

        NSLayoutConstraint.activate([
            avatarImageView.widthAnchor.constraint(equalToConstant: 64),
            avatarImageView.heightAnchor.constraint(equalToConstant: 64),
            row.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16),
            row.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 16),
            row.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -14)
        ])
    }

    private func setupStats() {
        statsStack.axis = .horizontal
        statsStack.distribution = .fillEqually
        statsStack.isLayoutMarginsRelativeArrangement = true
        statsStack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0)
        for (index, statView) in statViews.enumerated() {
            statView.showsLeadingDivider = index > 0
            statsStack.addArrangedSubview(statView)
        }
    }

    private func setupLevel() {
        levelTitleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        levelTitleLabel.textColor = ReadingColors.text
        todayLabel.font = .systemFont(ofSize: 12.5)
        todayLabel.textColor = .secondaryLabel
        todayLabel.textAlignment = .right
        todayLabel.adjustsFontSizeToFitWidth = true
        todayLabel.minimumScaleFactor = 0.85
        levelTitleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let titleRow = UIStackView(arrangedSubviews: [levelTitleLabel, todayLabel])
        titleRow.axis = .horizontal
        titleRow.spacing = 8
        titleRow.alignment = .firstBaseline
        let stack = UIStackView(arrangedSubviews: [titleRow, levelBar])
        stack.axis = .vertical
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        levelContainer.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: levelContainer.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: levelContainer.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: levelContainer.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: levelContainer.bottomAnchor, constant: -14)
        ])
    }

    /// 整卡作为一个无障碍元素：读名字、UID 和五格数字。
    private func updateAccessibility(loggedIn: Bool) {
        guard loggedIn else {
            accessibilityLabel = "未登录，登录后查看等级、鸡腿和今日进度"
            accessibilityHint = "点按登录"
            return
        }
        let stats = statViews.compactMap(\.accessibilityLabel).joined(separator: "，")
        accessibilityLabel = [nameLabel.text, metaLabel.text, stats].compactMap { $0 }.joined(separator: "，")
        accessibilityHint = "点按查看个人主页"
    }

    @objc private func cardTapped() {
        onTap?()
    }

    @objc private func loginTapped() {
        onLoginTap?()
    }
}

/// 五格数字中的一格：粗体数字 + 灰色标签，左侧细分隔线。
private final class MeStatView: UIView {
    var showsLeadingDivider = false {
        didSet { divider.isHidden = !showsLeadingDivider }
    }

    private let valueLabel = UILabel()
    private let titleLabel = UILabel()
    private let divider = UIView()

    init(title: String) {
        super.init(frame: .zero)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 19, weight: .bold)
        valueLabel.textColor = ReadingColors.text
        valueLabel.textAlignment = .center
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.7
        valueLabel.text = "–"
        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.textColor = .secondaryLabel
        titleLabel.textAlignment = .center
        titleLabel.text = title
        divider.backgroundColor = .separator
        divider.isHidden = true

        let stack = UIStackView(arrangedSubviews: [valueLabel, titleLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        divider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        addSubview(divider)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: leadingAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            divider.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5)
        ])
        isAccessibilityElement = true
        updateAccessibility()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setValue(_ value: String) {
        valueLabel.text = value
        updateAccessibility()
    }

    private func updateAccessibility() {
        accessibilityLabel = "\(titleLabel.text ?? "") \(valueLabel.text ?? "")"
    }
}

/// 分组卡片里的一行：线性图标 + 标题 + 右侧数量 / 描边胶囊 + 箭头。
private final class MeListRowView: UIControl {
    var showsSeparator = false {
        didSet { separator.isHidden = !showsSeparator }
    }

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let valueLabel = UILabel()
    private let actionLabel = MeCapsuleLabel()
    private let chevronView = UIImageView(image: UIImage(systemName: "chevron.right"))
    private let separator = MeSeparatorView()

    init(symbolName: String, title: String) {
        super.init(frame: .zero)
        iconView.image = UIImage(systemName: symbolName)
        iconView.tintColor = .label
        iconView.contentMode = .center
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.textColor = ReadingColors.text
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .regular)
        valueLabel.textColor = .secondaryLabel
        chevronView.tintColor = .tertiaryLabel
        chevronView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        actionLabel.isHidden = true
        separator.isHidden = true

        for subview in [iconView, titleLabel, valueLabel, actionLabel, chevronView, separator] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            subview.isUserInteractionEnabled = false
            addSubview(subview)
        }
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        chevronView.setContentHuggingPriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 50),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 14),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 12),
            chevronView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            chevronView.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: chevronView.leadingAnchor, constant: -8),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),
            actionLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            actionLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            separator.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.topAnchor.constraint(equalTo: topAnchor)
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
        updateAccessibility()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet { backgroundColor = isHighlighted ? .systemFill : .clear }
    }

    func updateTextSize() {
        titleLabel.font = AppTypography.font(basePointSize: 17)
    }

    /// 右侧灰字（数量或今日所得），nil 时只显示箭头。
    func setValue(_ value: String?) {
        valueLabel.text = value
        valueLabel.isHidden = value == nil
        actionLabel.isHidden = true
        chevronView.isHidden = false
        updateAccessibility()
    }

    /// 右侧描边胶囊，例如未签到时的“签到”。
    func setAction(title: String) {
        actionLabel.text = title
        actionLabel.isHidden = false
        valueLabel.isHidden = true
        chevronView.isHidden = true
        updateAccessibility()
    }

    private func updateAccessibility() {
        let detail = actionLabel.isHidden ? valueLabel.text : actionLabel.text
        accessibilityLabel = [titleLabel.text, detail].compactMap { $0 }.joined(separator: "，")
    }
}

/// 文字色描边的小胶囊。
private final class MeCapsuleLabel: UILabel {
    private let insets = UIEdgeInsets(top: 4, left: 11, bottom: 4, right: 11)

    override init(frame: CGRect) {
        super.init(frame: frame)
        font = .systemFont(ofSize: 13, weight: .semibold)
        textColor = ReadingColors.text
        layer.borderWidth = 1
        clipsToBounds = true
        updateBorderColor()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateBorderColor()
    }

    private func updateBorderColor() {
        // layer 颜色不会自动跟随深浅色
        layer.borderColor = UIColor.label.resolvedColor(with: traitCollection).cgColor
    }
}

private final class MeSeparatorView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .separator
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// 升级进度条：只有这里用彩色（系统 indigo）。
private final class MeProgressBar: UIView {
    private let fillView = UIView()

    var fraction: Double = 0 {
        didSet { setNeedsLayout() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemFill
        layer.cornerRadius = 2.5
        clipsToBounds = true
        fillView.backgroundColor = .systemIndigo
        fillView.layer.cornerRadius = 2.5
        addSubview(fillView)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 5).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let clamped = min(1, max(0, fraction))
        fillView.frame = CGRect(x: 0, y: 0, width: bounds.width * clamped, height: bounds.height)
    }
}
