//
//  NotificationViewController.swift
//  nodeseek
//
//  Created by Codex on 2026/6/8.
//

import SafariServices
import UIKit

@MainActor
final class NotificationViewController: UIViewController {
    private enum DisplayMode {
        case content
        case loading
        case error
        case loginRequired
    }

    private let client: NodeSeekNotificationClientProtocol
    private let currentAccountStore: CurrentAccountStore
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let refreshControl = UIRefreshControl()
    private let segmentedControl = UISegmentedControl()
    private let errorView = UserContentErrorView(accessibilityIdentifier: "notification-error-view")
    private let loginPromptView = NotificationLoginPromptView()
    /// 加载失败时判断是否因为未登录；可注入，测试里不走网络
    private let isLoggedIn: @MainActor () async -> Bool
    private let loadingView = NotificationLoadingView()
    private let emptyLabel = UILabel()
    private var browserButton: UIBarButtonItem?
    private var markAllButton: UIBarButtonItem?
    private var isMarkingAllRead = false

    private var selectedTab: NodeSeekNotificationTab
    private var displayMode: DisplayMode = .content
    private var atMeRecords: [NodeSeekNotificationRecord] = []
    private var replyRecords: [NodeSeekNotificationRecord] = []
    private var messageRecords: [NodeSeekMessageConversationRecord] = []
    private var loadedTabs: Set<NodeSeekNotificationTab> = []
    private var unreadCount: NodeSeekNotificationUnreadCount = .zero
    private var currentUserID: Int?
    private var loadToken = 0
    private var hasAppeared = false

    init(
        initialTab: NodeSeekNotificationTab = .atMe,
        client: NodeSeekNotificationClientProtocol? = nil,
        currentAccountStore: CurrentAccountStore = .shared,
        isLoggedIn: (@MainActor () async -> Bool)? = nil
    ) {
        self.isLoggedIn = isLoggedIn ?? { await TabLayoutAccountGate.isLoggedIn() }
        self.selectedTab = initialTab
        self.client = client ?? NodeSeekNotificationClient()
        self.currentAccountStore = currentAccountStore
        super.init(nibName: nil, bundle: nil)
        title = "通知"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appTextSizeDidChange),
            name: AppTextSizeSettings.didChangeNotification,
            object: nil
        )
        setupUI()
        loadCurrentUserID()
        loadUnreadCount()
        loadSelectedTab(showLoading: true)
    }

    @objc private func appTextSizeDidChange() {
        tableView.reloadData()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 首次出现已在 viewDidLoad 加载；之后每次回到本页（切 Tab、从详情返回）都静默刷新
        guard hasAppeared else {
            hasAppeared = true
            return
        }
        loadCurrentUserID()
        loadUnreadCount()
        loadSelectedTab(showLoading: true)
    }

    private func setupUI() {
        view.backgroundColor = UIColor.systemBackground
        configureNavigationItems()
        configureSegmentedControl()
        configureTableView()
        configureEmptyLabel()

        errorView.onRetry = { [weak self] in
            self?.loadUnreadCount()
            self?.loadSelectedTab(showLoading: true)
        }

        loginPromptView.onLogin = { [weak self] in
            self?.showLogin()
        }

        let segmentedContainer = UIView()
        segmentedContainer.translatesAutoresizingMaskIntoConstraints = false
        segmentedContainer.backgroundColor = UIColor.systemBackground
        segmentedContainer.addSubview(segmentedControl)

        view.addSubview(segmentedContainer)
        view.addSubview(tableView)
        view.addSubview(errorView)
        view.addSubview(loginPromptView)

        NSLayoutConstraint.activate([
            segmentedContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            segmentedContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            segmentedContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            segmentedContainer.heightAnchor.constraint(equalToConstant: 52),

            segmentedControl.leadingAnchor.constraint(equalTo: segmentedContainer.leadingAnchor, constant: 16),
            segmentedControl.trailingAnchor.constraint(equalTo: segmentedContainer.trailingAnchor, constant: -16),
            segmentedControl.centerYAnchor.constraint(equalTo: segmentedContainer.centerYAnchor),

            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: segmentedContainer.bottomAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            errorView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            errorView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            errorView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            errorView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),

            loginPromptView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loginPromptView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            loginPromptView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            loginPromptView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32)
        ])

        applyDisplayState()
    }

    private func configureNavigationItems() {
        let browserButton = UIBarButtonItem(
            image: UIImage(systemName: "safari"),
            style: .plain,
            target: self,
            action: #selector(openInBrowserTapped)
        )
        browserButton.accessibilityLabel = "在浏览器打开"
        self.browserButton = browserButton

        let markAllButton = UIBarButtonItem(
            image: UIImage(systemName: "envelope.open"),
            style: .plain,
            target: self,
            action: #selector(markAllReadTapped)
        )
        markAllButton.accessibilityLabel = "全部标为已读"
        self.markAllButton = markAllButton

        navigationItem.rightBarButtonItems = [markAllButton, browserButton]
        updateMarkAllButton()
    }

    private func configureSegmentedControl() {
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        for (index, tab) in NodeSeekNotificationTab.allCases.enumerated() {
            segmentedControl.insertSegment(withTitle: tab.title, at: index, animated: false)
        }
        segmentedControl.selectedSegmentIndex = selectedTab.rawValue
        segmentedControl.addTarget(self, action: #selector(tabChanged), for: .valueChanged)
        updateSegmentTitles()
    }

    private func configureTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = UIColor.systemBackground
        tableView.separatorColor = .separator
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 82
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(NotificationMentionCell.self, forCellReuseIdentifier: NotificationMentionCell.reuseIdentifier)
        tableView.register(NotificationMessageCell.self, forCellReuseIdentifier: NotificationMessageCell.reuseIdentifier)
        refreshControl.addTarget(self, action: #selector(refreshTriggered), for: .valueChanged)
        tableView.refreshControl = refreshControl
    }

    private func configureEmptyLabel() {
        emptyLabel.font = .preferredFont(forTextStyle: .subheadline)
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.adjustsFontForContentSizeCategory = true
        emptyLabel.numberOfLines = 0
    }

    private func loadCurrentUserID() {
        Task { [weak self] in
            guard let self else { return }
            currentUserID = await currentAccountStore.snapshot()?.account.nodeSeekUID
            if selectedTab == .message {
                tableView.reloadData()
            }
        }
    }

    private func loadUnreadCount(
        publishUpdate: Bool = true,
        postReadStateChangeOnFailure: Bool = false
    ) {
        Task { [weak self] in
            guard let self else { return }
            await refreshUnreadCount(
                publishUpdate: publishUpdate,
                postReadStateChangeOnFailure: postReadStateChangeOnFailure
            )
        }
    }

    private func refreshUnreadCount(
        publishUpdate: Bool,
        postReadStateChangeOnFailure: Bool
    ) async {
        do {
            let loadedUnreadCount = try await client.loadUnreadCount()
            unreadCount = loadedUnreadCount
            updateSegmentTitles()
            updateMarkAllButton()
            if publishUpdate {
                NodeSeekNotificationUnreadCountEvent.post(loadedUnreadCount)
            }
        } catch {
            if postReadStateChangeOnFailure {
                postNotificationReadStateChange()
            }
            AppLog.debug(.account, "通知未读数加载失败: \(error.localizedDescription)")
        }
    }

    private func refreshUnreadCountAfterReadStateChange() {
        markCurrentAccountNotificationStateStale()
        loadUnreadCount(
            publishUpdate: true,
            postReadStateChangeOnFailure: true
        )
    }

    private func loadSelectedTab(showLoading: Bool) {
        let tab = selectedTab
        loadToken += 1
        let token = loadToken
        if showLoading, loadedTabs.contains(tab) == false {
            displayMode = .loading
            applyDisplayState()
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                switch tab {
                case .atMe:
                    let records = try await client.loadAtMe()
                    guard token == loadToken, tab == selectedTab else { return }
                    atMeRecords = records
                case .reply:
                    let records = try await client.loadReplies()
                    guard token == loadToken, tab == selectedTab else { return }
                    replyRecords = records
                case .message:
                    let records = try await client.loadMessageConversations()
                    guard token == loadToken, tab == selectedTab else { return }
                    messageRecords = records
                }
                loadedTabs.insert(tab)
                finishLoading(tab: tab, token: token)
            } catch {
                showError(error.localizedDescription, tab: tab, token: token)
            }
        }
    }

    private func finishLoading(tab: NodeSeekNotificationTab, token: Int) {
        guard token == loadToken, tab == selectedTab else { return }
        refreshControl.endRefreshing()
        displayMode = .content
        errorView.isHidden = true
        applyDisplayState()
        updateMarkAllButton()
    }

    private func showError(_ message: String, tab: NodeSeekNotificationTab, token: Int) {
        guard token == loadToken, tab == selectedTab else { return }
        // 未登录时接口只会返回 500 之类的错误，改为提示登录，避免看起来像故障
        Task { [weak self] in
            guard let self else { return }
            let loggedIn = await isLoggedIn()
            guard token == loadToken, tab == selectedTab else { return }
            refreshControl.endRefreshing()
            if loggedIn {
                displayMode = .error
                errorView.messageLabel.text = message
            } else {
                displayMode = .loginRequired
            }
            applyDisplayState()
        }
    }

    private func showLogin() {
        let loginViewController = LoginWebViewController { [weak self] in
            // 本页在导航栈里时返回会经 viewWillAppear 刷新；弹出的情况在这里补一次
            guard let self, self.navigationController == nil else { return }
            self.loadUnreadCount()
            self.loadSelectedTab(showLoading: true)
        }
        if let navigationController {
            navigationController.pushViewController(loginViewController, animated: true)
        } else {
            present(UINavigationController(rootViewController: loginViewController), animated: true)
        }
    }

    private func applyDisplayState() {
        switch displayMode {
        case .content:
            errorView.isHidden = true
            loginPromptView.isHidden = true
            loadingView.stopAnimating()
            tableView.backgroundView = currentRecordCount == 0 ? emptyBackgroundView() : nil
        case .loading:
            errorView.isHidden = true
            loginPromptView.isHidden = true
            loadingView.startAnimating()
            tableView.backgroundView = loadingView
        case .error:
            loadingView.stopAnimating()
            errorView.isHidden = false
            loginPromptView.isHidden = true
            tableView.backgroundView = nil
        case .loginRequired:
            loadingView.stopAnimating()
            errorView.isHidden = true
            loginPromptView.isHidden = false
            tableView.backgroundView = nil
        }
        // 标签和显示状态变化时，同步清除表格缓存的旧行数与预取状态。
        tableView.reloadData()
    }

    private func emptyBackgroundView() -> UIView {
        emptyLabel.text = emptyText(for: selectedTab)
        return emptyLabel
    }

    private func emptyText(for tab: NodeSeekNotificationTab) -> String {
        switch tab {
        case .atMe:
            return "没有@消息"
        case .reply:
            return "没有新的评论"
        case .message:
            return "没有私信"
        }
    }

    private func updateSegmentTitles() {
        for tab in NodeSeekNotificationTab.allCases {
            let count = unreadCount.count(for: tab)
            let title = count > 0 ? "\(tab.title) \(count)" : tab.title
            segmentedControl.setTitle(title, forSegmentAt: tab.rawValue)
        }
    }

    private func updateMarkAllButton() {
        // 本地未读数可能与服务端不同步，始终允许点击，只在提交中防止重复触发。
        markAllButton?.isEnabled = !isMarkingAllRead
    }

    private var currentRecordCount: Int {
        switch selectedTab {
        case .atMe:
            return atMeRecords.count
        case .reply:
            return replyRecords.count
        case .message:
            return messageRecords.count
        }
    }

    @objc private func tabChanged() {
        guard let tab = NodeSeekNotificationTab(rawValue: segmentedControl.selectedSegmentIndex),
              tab != selectedTab else {
            return
        }
        selectedTab = tab
        refreshControl.endRefreshing()
        updateMarkAllButton()
        if loadedTabs.contains(tab) {
            loadToken += 1
            displayMode = .content
            applyDisplayState()
        } else {
            loadSelectedTab(showLoading: true)
        }
    }

    @objc private func refreshTriggered() {
        loadUnreadCount()
        loadSelectedTab(showLoading: false)
    }

    @objc private func openInBrowserTapped() {
        openWebURL(selectedTab.webURL)
    }

    @objc private func markAllReadTapped() {
        guard !isMarkingAllRead else { return }
        BottomToast.show("正在标记已读…", style: .progress, in: view)
        isMarkingAllRead = true
        updateMarkAllButton()
        let tab = selectedTab
        let previousUnreadCount = unreadCount
        let previousAtMeRecords = atMeRecords
        let previousReplyRecords = replyRecords
        let previousMessageRecords = messageRecords

        markAllLocally(tab: tab)
        Task { [weak self] in
            guard let self else { return }
            defer {
                isMarkingAllRead = false
                updateMarkAllButton()
            }
            do {
                try await client.markAllViewed(tab: tab)
                BottomToast.show("已全部标为已读", in: view)
                refreshUnreadCountAfterReadStateChange()
            } catch {
                unreadCount = previousUnreadCount
                atMeRecords = previousAtMeRecords
                replyRecords = previousReplyRecords
                messageRecords = previousMessageRecords
                updateSegmentTitles()
                updateMarkAllButton()
                if selectedTab == tab {
                    tableView.reloadData()
                }
                BottomToast.show(error.localizedDescription, style: .failure, in: view)
            }
        }
    }

    private func markAllLocally(tab: NodeSeekNotificationTab) {
        switch tab {
        case .atMe:
            atMeRecords = atMeRecords.map { record in
                var updated = record
                updated.markViewed()
                return updated
            }
        case .reply:
            replyRecords = replyRecords.map { record in
                var updated = record
                updated.markViewed()
                return updated
            }
        case .message:
            messageRecords = messageRecords.map { record in
                var updated = record
                updated.markViewed()
                return updated
            }
        }
        unreadCount.setCount(0, for: tab)
        updateSegmentTitles()
        updateMarkAllButton()
        if selectedTab == tab {
            tableView.reloadData()
        }
    }

    private func markRead(
        id: Int,
        tab: NodeSeekNotificationTab,
        rollbackOnFailure: Bool,
        showFailure: Bool
    ) {
        let previousUnreadCount = unreadCount
        guard markRecordLocally(id: id, tab: tab) else { return }
        if showFailure { BottomToast.show("正在标记已读…", style: .progress, in: view) }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await client.markViewed(ids: [id], tab: tab)
                if showFailure { BottomToast.show("已标为已读", in: view) }
                refreshUnreadCountAfterReadStateChange()
            } catch {
                if rollbackOnFailure {
                    unmarkRecordLocally(id: id, tab: tab)
                    unreadCount = previousUnreadCount
                    updateSegmentTitles()
                    updateMarkAllButton()
                    if selectedTab == tab {
                        tableView.reloadData()
                    }
                } else {
                    loadUnreadCount()
                }
                if showFailure {
                    BottomToast.show(error.localizedDescription, style: .failure, in: view)
                }
            }
        }
    }

    @discardableResult
    private func markRecordLocally(id: Int, tab: NodeSeekNotificationTab) -> Bool {
        switch tab {
        case .atMe:
            guard let index = atMeRecords.firstIndex(where: { $0.id == id }),
                  atMeRecords[index].isViewed == false else {
                return false
            }
            atMeRecords[index].markViewed()
        case .reply:
            guard let index = replyRecords.firstIndex(where: { $0.id == id }),
                  replyRecords[index].isViewed == false else {
                return false
            }
            replyRecords[index].markViewed()
        case .message:
            guard let index = messageRecords.firstIndex(where: { $0.maxID == id }),
                  messageRecords[index].isViewed == false else {
                return false
            }
            messageRecords[index].markViewed()
        }

        unreadCount.decrement(for: tab)
        updateSegmentTitles()
        updateMarkAllButton()
        if selectedTab == tab {
            tableView.reloadData()
        }
        return true
    }

    private func unmarkRecordLocally(id: Int, tab: NodeSeekNotificationTab) {
        switch tab {
        case .atMe:
            guard let index = atMeRecords.firstIndex(where: { $0.id == id }) else { return }
            atMeRecords[index].viewed = 0
        case .reply:
            guard let index = replyRecords.firstIndex(where: { $0.id == id }) else { return }
            replyRecords[index].viewed = 0
        case .message:
            guard let index = messageRecords.firstIndex(where: { $0.maxID == id }) else { return }
            messageRecords[index].viewed = 0
        }
    }

    private func openNotificationRecord(_ record: NodeSeekNotificationRecord, tab: NodeSeekNotificationTab) {
        if record.isViewed == false {
            markRead(id: record.id, tab: tab, rollbackOnFailure: false, showFailure: false)
        }
        let detailViewController = PostDetailRouter.createModule(
            post: record.postSummary,
            page: record.commentPage,
            initialAnchorID: record.anchorID
        )
        navigationController?.pushViewController(detailViewController, animated: true)
    }

    private func openProfile(_ record: NodeSeekNotificationRecord) {
        navigationController?.pushViewController(
            UserProfileRouter.makeViewController(profileURL: record.profileURL),
            animated: true
        )
    }

    private func openMessageConversation(_ record: NodeSeekMessageConversationRecord) {
        if record.isViewed == false {
            markRead(id: record.maxID, tab: .message, rollbackOnFailure: false, showFailure: false)
        }
        openWebURL(record.conversationWebURL(currentUserID: currentUserID))
    }

    private func openWebURL(_ url: URL) {
        if NodeSeekSite.isNodeSeekHost(url) {
            let viewController = NodeSeekWebViewController(url: url)
            navigationController?.pushViewController(viewController, animated: true)
            return
        }
        present(SFSafariViewController(url: url), animated: true)
    }

    private func showErrorMessage(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }

    private func postNotificationReadStateChange() {
        NotificationCenter.default.post(name: .nodeSeekNotificationReadStateDidChange, object: nil)
    }

    private func markCurrentAccountNotificationStateStale() {
        Task { [currentAccountStore] in
            await currentAccountStore.markStale()
        }
    }
}

extension NotificationViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard displayMode == .content else { return 0 }
        return currentRecordCount
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // 预取回调可能仍携带切换前的行号，不能直接访问当前标签的数组。
        guard displayMode == .content,
              indexPath.section == 0,
              indexPath.row >= 0,
              indexPath.row < currentRecordCount else {
            return UITableViewCell()
        }
        switch selectedTab {
        case .atMe:
            let record = atMeRecords[indexPath.row]
            let cell = tableView.dequeueReusableCell(
                withIdentifier: NotificationMentionCell.reuseIdentifier,
                for: indexPath
            ) as? NotificationMentionCell ?? NotificationMentionCell()
            cell.configure(
                record: record,
                tab: .atMe,
                timeText: NodeSeekNotificationDateParser.displayText(from: record.createdAt),
                onProfileTapped: { [weak self] in self?.openProfile(record) },
                onMarkReadTapped: { [weak self] in
                    self?.markRead(id: record.id, tab: .atMe, rollbackOnFailure: true, showFailure: true)
                }
            )
            return cell
        case .reply:
            let record = replyRecords[indexPath.row]
            let cell = tableView.dequeueReusableCell(
                withIdentifier: NotificationMentionCell.reuseIdentifier,
                for: indexPath
            ) as? NotificationMentionCell ?? NotificationMentionCell()
            cell.configure(
                record: record,
                tab: .reply,
                timeText: NodeSeekNotificationDateParser.displayText(from: record.createdAt),
                onProfileTapped: { [weak self] in self?.openProfile(record) },
                onMarkReadTapped: { [weak self] in
                    self?.markRead(id: record.id, tab: .reply, rollbackOnFailure: true, showFailure: true)
                }
            )
            return cell
        case .message:
            let record = messageRecords[indexPath.row]
            let cell = tableView.dequeueReusableCell(
                withIdentifier: NotificationMessageCell.reuseIdentifier,
                for: indexPath
            ) as? NotificationMessageCell ?? NotificationMessageCell()
            cell.configure(
                record: record,
                currentUserID: currentUserID,
                timeText: NodeSeekNotificationDateParser.displayText(from: record.createdAt)
            )
            return cell
        }
    }
}

extension NotificationViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard displayMode == .content else { return }
        switch selectedTab {
        case .atMe:
            guard atMeRecords.indices.contains(indexPath.row) else { return }
            openNotificationRecord(atMeRecords[indexPath.row], tab: .atMe)
        case .reply:
            guard replyRecords.indices.contains(indexPath.row) else { return }
            openNotificationRecord(replyRecords[indexPath.row], tab: .reply)
        case .message:
            guard messageRecords.indices.contains(indexPath.row) else { return }
            openMessageConversation(messageRecords[indexPath.row])
        }
    }
}

private final class NotificationLoadingView: UIView {
    private let indicator = UIActivityIndicatorView(style: .medium)
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.systemBackground

        label.text = "加载中"
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.adjustsFontForContentSizeCategory = true

        let stack = UIStackView(arrangedSubviews: [indicator, label])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
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

/// 未登录时的通知页占位：说明 + 登录按钮。
private final class NotificationLoginPromptView: UIStackView {
    var onLogin: (() -> Void)?

    init() {
        super.init(frame: .zero)
        axis = .vertical
        alignment = .center
        spacing = 10
        isHidden = true
        accessibilityIdentifier = "notification-login-view"
        translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView(image: UIImage(systemName: "bell"))
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 34, weight: .regular)
        iconView.tintColor = .tertiaryLabel

        let titleLabel = UILabel()
        titleLabel.text = "登录后查看通知"
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = ReadingColors.text
        titleLabel.adjustsFontForContentSizeCategory = true

        let messageLabel = UILabel()
        messageLabel.text = "@我、回复和私信都需要登录"
        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.adjustsFontForContentSizeCategory = true

        var configuration = UIButton.Configuration.filled()
        configuration.title = "登录"
        configuration.baseBackgroundColor = .label
        configuration.baseForegroundColor = .systemBackground
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 24, bottom: 8, trailing: 24)
        let loginButton = UIButton(configuration: configuration)
        loginButton.accessibilityIdentifier = "notification-login-button"
        loginButton.addTarget(self, action: #selector(loginTapped), for: .touchUpInside)

        addArrangedSubview(iconView)
        setCustomSpacing(14, after: iconView)
        addArrangedSubview(titleLabel)
        addArrangedSubview(messageLabel)
        setCustomSpacing(18, after: messageLabel)
        addArrangedSubview(loginButton)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func loginTapped() {
        onLogin?()
    }
}
