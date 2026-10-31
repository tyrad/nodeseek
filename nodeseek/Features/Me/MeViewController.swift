//
//  MeViewController.swift
//  nodeseek
//

import UIKit

/// 多 Tab 模式的“我的”页：收纳原侧边栏里的账号与个人入口，设置在右上角。
final class MeViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case account
        case content
        case common
    }

    private enum ContentRow: Int, CaseIterable {
        case discussions
        case comments
        case collections

        var title: String {
            switch self {
            case .discussions: return "我的帖子"
            case .comments: return "我的评论"
            case .collections: return "我的收藏"
            }
        }

        var symbolName: String {
            switch self {
            case .discussions: return "doc.text"
            case .comments: return "bubble.left"
            case .collections: return "bookmark"
            }
        }
    }

    private enum CommonRow: Int, CaseIterable {
        case checkIn
        case recentVisited

        var title: String {
            switch self {
            case .checkIn: return "每日签到"
            case .recentVisited: return "最近浏览"
            }
        }

        var symbolName: String {
            switch self {
            case .checkIn: return "checkmark.seal"
            case .recentVisited: return "clock.arrow.circlepath"
            }
        }
    }

    private let accountController: PostListSideMenuAccountController
    private let router = PostListRouter()
    private let visitedStore: VisitedPostStoreProtocol
    private var account = AccountResponse(displayName: "游客", isLoggedIn: false)

    init(
        accountController: PostListSideMenuAccountController? = nil,
        visitedStore: VisitedPostStoreProtocol? = nil
    ) {
        self.accountController = accountController ?? PostListSideMenuAccountController()
        self.visitedStore = visitedStore ?? VisitedPostStore.shared
        super.init(style: .insetGrouped)
        title = "我的"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        router.viewController = self
        tableView.accessibilityIdentifier = "me-table"
        tableView.register(MeAccountCell.self, forCellReuseIdentifier: MeAccountCell.reuseIdentifier)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "row")

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

        accountController.canRefresh = { [weak self] in
            self?.view.window != nil
        }
        // 页面可见时，登录窗口关闭后立即刷新账号
        accountController.isSideMenuVisible = { [weak self] in
            self?.view.window != nil
        }
        accountController.onAccountChanged = { [weak self] account in
            self?.render(account)
        }
        accountController.start()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        accountController.refreshIfNeeded()
    }

    // MARK: - Table

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .account: return 1
        case .content: return ContentRow.allCases.count
        case .common: return CommonRow.allCases.count
        case .none: return 0
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .content: return "我的内容"
        case .common: return "常用"
        default: return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {
        case .account:
            let cell = tableView.dequeueReusableCell(withIdentifier: MeAccountCell.reuseIdentifier, for: indexPath)
            (cell as? MeAccountCell)?.render(account)
            return cell
        case .content:
            let row = ContentRow(rawValue: indexPath.row) ?? .discussions
            return makeRowCell(at: indexPath, title: row.title, symbolName: row.symbolName)
        case .common:
            let row = CommonRow(rawValue: indexPath.row) ?? .checkIn
            return makeRowCell(at: indexPath, title: row.title, symbolName: row.symbolName)
        case .none:
            return UITableViewCell()
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section) {
        case .account:
            if account.isLoggedIn, let profileURL = account.profileURL {
                router.navigateToUserProfile(profileURL: profileURL)
            } else if account.isLoggedIn == false {
                showLogin()
            }
        case .content:
            guard requireLogin() else { return }
            switch ContentRow(rawValue: indexPath.row) {
            case .discussions: router.navigateToUserDiscussions()
            case .comments: router.navigateToUserComments()
            case .collections: router.navigateToUserCollections()
            case .none: break
            }
        case .common:
            switch CommonRow(rawValue: indexPath.row) {
            case .checkIn:
                guard requireLogin() else { return }
                router.navigateToCheckIn(boardURL: NodeSeekSite.boardURL)
            case .recentVisited:
                router.navigateToRecentVisitedPosts(visitedStore: visitedStore)
            case .none:
                break
            }
        case .none:
            break
        }
    }

    // MARK: - Private

    private func makeRowCell(at indexPath: IndexPath, title: String, symbolName: String) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = title
        content.image = UIImage(systemName: symbolName)
        content.imageProperties.tintColor = .label
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    private func render(_ account: AccountResponse) {
        self.account = account
        guard isViewLoaded else { return }
        tableView.reloadSections(IndexSet(integer: Section.account.rawValue), with: .none)
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
            self?.accountController.refreshIfNeeded(force: true)
            self?.reloadHomeList()
        }
    }

    @objc private func settingsTapped() {
        router.navigateToSettings(
            onLogout: { [weak self] in
                NodeSeekNotificationUnreadCountEvent.post(.zero)
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
}

/// “我的”页顶部账号卡片：头像、名字、统计。
private final class MeAccountCell: UITableViewCell {
    static let reuseIdentifier = "MeAccountCell"

    private static let defaultAvatarImage = UIImage(
        systemName: "person.crop.circle.fill",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 48, weight: .regular)
    )

    private let avatarImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 14
        imageView.layer.cornerCurve = .continuous
        imageView.backgroundColor = .secondarySystemBackground
        imageView.tintColor = .tertiaryLabel
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 20, weight: .bold)
        label.textColor = .label
        return label
    }()

    private let statsLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.numberOfLines = 2
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator
        accessibilityIdentifier = "me-account-cell"

        let textStack = UIStackView(arrangedSubviews: [nameLabel, statsLabel])
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(avatarImageView)
        contentView.addSubview(textStack)

        NSLayoutConstraint.activate([
            avatarImageView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            avatarImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            avatarImageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),
            avatarImageView.widthAnchor.constraint(equalToConstant: 60),
            avatarImageView.heightAnchor.constraint(equalToConstant: 60),

            textStack.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 14),
            textStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            textStack.centerYAnchor.constraint(equalTo: avatarImageView.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func render(_ account: AccountResponse) {
        nameLabel.text = account.isLoggedIn ? account.displayName : "未登录"
        statsLabel.text = account.isLoggedIn
            ? account.stats.prefix(3).joined(separator: " · ")
            : "点按登录，同步账号信息"
        accessibilityLabel = account.isLoggedIn ? "账号信息" : "登录账号"

        if account.isLoggedIn {
            ImageLoad.url(account.avatarURL)
                .toAvatar(requestID: account.profileURL?.lastPathComponent ?? account.displayName)
                .into(avatarImageView)
        } else {
            AvatarImageLoader.shared.cancel(on: avatarImageView)
            avatarImageView.image = Self.defaultAvatarImage
        }
    }
}
