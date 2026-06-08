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
    }

    private let client: NodeSeekNotificationClientProtocol
    private let currentAccountStore: CurrentAccountStore
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let refreshControl = UIRefreshControl()
    private let segmentedControl = UISegmentedControl()
    private let errorView = UserContentErrorView(accessibilityIdentifier: "notification-error-view")
    private let loadingView = NotificationLoadingView()
    private let emptyLabel = UILabel()
    private var browserButton: UIBarButtonItem?
    private var markAllButton: UIBarButtonItem?

    private var selectedTab: NodeSeekNotificationTab = .atMe
    private var displayMode: DisplayMode = .content
    private var atMeRecords: [NodeSeekNotificationRecord] = []
    private var replyRecords: [NodeSeekNotificationRecord] = []
    private var messageRecords: [NodeSeekMessageConversationRecord] = []
    private var loadedTabs: Set<NodeSeekNotificationTab> = []
    private var unreadCount: NodeSeekNotificationUnreadCount = .zero
    private var currentUserID: Int?
    private var loadToken = 0

    init(
        client: NodeSeekNotificationClientProtocol? = nil,
        currentAccountStore: CurrentAccountStore = .shared
    ) {
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
        setupUI()
        loadCurrentUserID()
        loadUnreadCount()
        loadSelectedTab(showLoading: true)
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground
        configureNavigationItems()
        configureSegmentedControl()
        configureTableView()
        configureEmptyLabel()

        errorView.onRetry = { [weak self] in
            self?.loadUnreadCount()
            self?.loadSelectedTab(showLoading: true)
        }

        let segmentedContainer = UIView()
        segmentedContainer.translatesAutoresizingMaskIntoConstraints = false
        segmentedContainer.backgroundColor = .systemBackground
        segmentedContainer.addSubview(segmentedControl)

        view.addSubview(segmentedContainer)
        view.addSubview(tableView)
        view.addSubview(errorView)

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
            errorView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32)
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
        tableView.backgroundColor = .systemBackground
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

    private func loadUnreadCount() {
        Task { [weak self] in
            guard let self else { return }
            do {
                unreadCount = try await client.loadUnreadCount()
                updateSegmentTitles()
                updateMarkAllButton()
            } catch {
                AppLog.debug(.account, "通知未读数加载失败: \(error.localizedDescription)")
            }
        }
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
                    atMeRecords = try await client.loadAtMe()
                case .reply:
                    replyRecords = try await client.loadReplies()
                case .message:
                    messageRecords = try await client.loadMessageConversations()
                }
                loadedTabs.insert(tab)
                finishLoading(tab: tab, token: token)
            } catch {
                showError(error.localizedDescription, tab: tab, token: token)
            }
        }
    }

    private func finishLoading(tab: NodeSeekNotificationTab, token: Int) {
        refreshControl.endRefreshing()
        guard token == loadToken, tab == selectedTab else { return }
        displayMode = .content
        errorView.isHidden = true
        applyDisplayState()
        tableView.reloadData()
        updateMarkAllButton()
    }

    private func showError(_ message: String, tab: NodeSeekNotificationTab, token: Int) {
        refreshControl.endRefreshing()
        guard token == loadToken, tab == selectedTab else { return }
        displayMode = .error
        errorView.messageLabel.text = message
        applyDisplayState()
    }

    private func applyDisplayState() {
        switch displayMode {
        case .content:
            errorView.isHidden = true
            loadingView.stopAnimating()
            tableView.backgroundView = currentRecordCount == 0 ? emptyBackgroundView() : nil
        case .loading:
            errorView.isHidden = true
            loadingView.startAnimating()
            tableView.backgroundView = loadingView
        case .error:
            loadingView.stopAnimating()
            errorView.isHidden = false
            tableView.backgroundView = nil
        }
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
        markAllButton?.isEnabled = currentUnreadCount > 0
    }

    private var currentUnreadCount: Int {
        let count = unreadCount.count(for: selectedTab)
        if count > 0 { return count }
        return currentUnreadRecordCount
    }

    private var currentUnreadRecordCount: Int {
        switch selectedTab {
        case .atMe:
            return atMeRecords.filter { !$0.isViewed }.count
        case .reply:
            return replyRecords.filter { !$0.isViewed }.count
        case .message:
            return messageRecords.filter { !$0.isViewed }.count
        }
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
        updateMarkAllButton()
        if loadedTabs.contains(tab) {
            displayMode = .content
            applyDisplayState()
            tableView.reloadData()
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
        let tab = selectedTab
        let previousUnreadCount = unreadCount
        let previousAtMeRecords = atMeRecords
        let previousReplyRecords = replyRecords
        let previousMessageRecords = messageRecords

        markAllLocally(tab: tab)
        Task { [weak self] in
            guard let self else { return }
            do {
                try await client.markAllViewed(tab: tab)
                markAccountNotificationStateStale()
                loadUnreadCount()
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
                showErrorMessage(error.localizedDescription)
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
        Task { [weak self] in
            guard let self else { return }
            do {
                try await client.markViewed(ids: [id], tab: tab)
                markAccountNotificationStateStale()
                loadUnreadCount()
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
                    showErrorMessage(error.localizedDescription)
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
            UserInfoWebViewController(profileURL: record.profileURL),
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

    private func markAccountNotificationStateStale() {
        NotificationCenter.default.post(name: .nodeSeekNotificationReadStateDidChange, object: nil)
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
        backgroundColor = .systemBackground

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
