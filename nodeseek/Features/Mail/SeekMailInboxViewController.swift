//
//  SeekMailInboxViewController.swift
//  nodeseek
//

import SafariServices
import UIKit

/// 已绑定时的邮件列表。顶部平铺邮箱标签，搜索框悬浮在本页底部。
final class SeekMailInboxViewController: UIViewController {
    let model: SeekMailInboxModel
    /// 401 时回调，由入口页清掉 Key 并回到绑定页。
    var onUnauthorized: (() -> Void)?
    /// 邮箱列表变化后（例如能否写信），入口页要重新同步导航栏。
    var onNavigationChange: (() -> Void)?

    /// 不用系统 searchController：iOS 26 会把它放到底部并占用导航栈的底部安全区，返回时底部 Tab 会跳一下。
    let searchBar = ProbeSearchBarView()

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let mailboxTags = SeekMailMailboxTagsView()
    private let folderTabs = SeekMailFolderTabsView()
    private let noticeLabel = UILabel()
    private let noticeBar = UIView()
    private let undoToast = SeekMailUndoToast()
    private var noticeTimer: Timer?
    private var lastDeletedID: Int64?
    private var autoRefreshTimer: Timer?
    private let progressBar = SeekMailProgressBar()
    private lazy var markJob: SeekMailMarkAllReadJob = {
        let job = SeekMailMarkAllReadJob(provider: model.provider)
        job.onChange = { [weak self] state in self?.renderMarkJob(state) }
        job.onMarked = { [weak self] mail in self?.model.applyMarkedRead(id: mail.id, mailboxID: mail.mailboxId) }
        return job
    }()

    private enum Section: Int, CaseIterable { case code, mails }

    init(keyStore: SeekMailAPIKeyStoring,
         transport: SeekMailProvider<SeekMailAPI>.Transport? = nil,
         selectionStore: SeekMailSelectionStore = SeekMailSelectionStore(),
         deleteDelay: TimeInterval = 4,
         cache: SeekMailListCache? = nil,
         memoryCache: SeekMailMemoryCache? = nil) {
        let provider: SeekMailProvider<SeekMailAPI>
        if let transport {
            provider = SeekMailProvider(apiKey: { [keyStore] in keyStore.apiKey() }, transport: transport)
        } else {
            provider = SeekMailProvider(apiKey: { [keyStore] in keyStore.apiKey() })
        }
        model = SeekMailInboxModel(provider: provider, selectionStore: selectionStore, deleteDelay: deleteDelay,
                                   cache: cache, cacheKey: { [keyStore] in keyStore.apiKey() },
                                   memoryCache: memoryCache)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        noticeTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupLayout()
        model.onChange = { [weak self] in self?.render() }
        model.onUnauthorized = { [weak self] in self?.onUnauthorized?() }
        model.onMessage = { [weak self] message in self?.undoToast.showMessage(message, in: self?.view) }
        folderTabs.onSelect = { [weak self] scope in self?.model.selectScope(scope) }
        mailboxTags.onSelect = { [weak self] id in self?.model.selectMailbox(id) }
        mailboxTags.onToggle = { [weak self] expanded in self?.model.selectionStore.tagsExpanded = expanded }
        mailboxTags.onCopyAddress = { [weak self] address in self?.copyAddress(address) }
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(unreadCountsDidChange(_:)),
            name: SeekMailUnreadMonitor.didChangeNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(textSizeDidChange),
            name: AppTextSizeSettings.didChangeNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(newMailArrived),
            name: SeekMailUnreadMonitor.newMailNotification, object: nil
        )
        render()
        model.start()
    }

    /// 调整「字体大小」后重设字体；单元格、标签和文件夹 tab 都在刷新时按当前字号配置。
    @objc private func textSizeDidChange() {
        noticeLabel.font = SeekMailFont.of(.footnote)
        undoToast.refreshFonts()
        render()
        mailboxTags.setNeedsLayout()
    }

    /// 回到前台检查到的未读数直接用在标签上，不再单独请求。
    @objc private func unreadCountsDidChange(_ notification: Notification) {
        guard let counts = (notification.object as? SeekMailUnreadMonitor)?.latestCounts else { return }
        model.applyUnreadCounts(counts)
    }

    /// 回到前台时发现新邮件，列表正停在这里就直接刷新。
    @objc private func newMailArrived() {
        guard model.phase == .loaded, model.isSearching == false else { return }
        model.reload()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startAutoRefresh()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopAutoRefresh()
        // 推入详情页不算离开列表，只有真正离开才立即提交删除
        if isMovingFromParent || parent?.isMovingFromParent == true || navigationController?.isBeingDismissed == true {
            // 离开邮箱就停止逐封标已读，已处理的保留
            markJob.stop()
            model.commitPendingDeletes()
        }
    }

    @objc private func appWillResignActive() {
        model.commitPendingDeletes()
        undoToast.dismiss()
        stopAutoRefresh()
    }

    @objc private func appDidBecomeActive() {
        guard viewIfLoaded?.window != nil else { return }
        startAutoRefresh()
    }

    // MARK: - 自动刷新

    /// 只在列表显示且 App 在前台时计时；离开列表、进详情、切到后台都会停。
    private func startAutoRefresh() {
        stopAutoRefresh()
        let seconds = model.selectionStore.autoRefreshSeconds
        guard seconds > 0 else { return }
        autoRefreshTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(seconds), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                // 逐封标已读时额度留给它，不自动刷新
                guard let self, self.markJob.isActive == false else { return }
                self.model.autoRefresh()
            }
        }
    }

    private func stopAutoRefresh() {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = nil
    }

    private static func autoRefreshTitle(_ seconds: Int) -> String {
        seconds == 0 ? SeekMailL10n.text("关闭") : SeekMailL10n.format("每 %@ 秒", String(seconds))
    }

    // MARK: - 全部标为已读

    /// 先只取未读 ID 算出数量，确认时写清楚要逐封处理、大概多久，避免用户以为卡住。
    private func markAllRead() {
        guard markJob.isActive == false else { return }
        let mailboxID = model.selectedMailboxID
        let scopeTitle = model.selectionTitle
        progressBar.show(text: SeekMailL10n.text("正在统计未读…"), progress: nil)
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await markJob.collect(mailboxID: mailboxID)
                progressBar.hide()
                guard result.mails.isEmpty == false else {
                    undoToast.showMessage(SeekMailL10n.text("没有未读邮件"), in: view)
                    model.refreshUnreadCounts()
                    return
                }
                confirmMarkAllRead(result.mails, hasMore: result.total > result.mails.count, scopeTitle: scopeTitle)
            } catch {
                progressBar.hide()
                undoToast.showMessage((error as? SeekMailError)?.userMessage ?? SeekMailL10n.text("加载失败，请稍后重试"), in: view)
            }
        }
    }

    private func confirmMarkAllRead(_ mails: [SeekUnreadMail], hasMore: Bool, scopeTitle: String) {
        let seconds = Int((Double(mails.count) * SeekMailMarkAllReadJob.interval).rounded(.up))
        let duration = seconds < 60
            ? SeekMailL10n.format("%@ 秒", String(max(seconds, 1)))
            : SeekMailL10n.format("%@ 分钟", String(Int((Double(seconds) / 60).rounded(.up))))
        var lines = [
            SeekMailL10n.format("将把 %@ 的 %@ 封未读标为已读（不含垃圾邮件和回收站）。", scopeTitle, String(mails.count)),
            SeekMailL10n.format("seek.li 没有批量接口，会逐封处理，约 %@，期间可继续看邮件。", duration)
        ]
        if hasMore {
            lines.append(SeekMailL10n.format("超过 %@ 封，本次先处理 %@ 封，之后可再执行一次。",
                                             String(SeekMailMarkAllReadJob.maxPerRun), String(mails.count)))
        }
        let alert = UIAlertController(title: SeekMailL10n.text("全部标为已读"), message: lines.joined(separator: "\n"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: SeekMailL10n.text("取消"), style: .cancel))
        alert.addAction(UIAlertAction(title: SeekMailL10n.text("开始"), style: .default) { [weak self] _ in
            self?.markJob.start(mails)
        })
        present(alert, animated: true)
    }

    private func renderMarkJob(_ state: SeekMailMarkAllReadJob.State) {
        switch state {
        case .idle:
            progressBar.hide()
        case .running(let done, let total):
            progressBar.show(text: SeekMailL10n.format("正在标为已读 %@/%@", String(done), String(total)),
                             progress: Float(done) / Float(max(total, 1)),
                             actionTitle: SeekMailL10n.text("停止")) { [weak self] in self?.markJob.stop() }
        case .waiting(let until, let done, let total):
            let seconds = max(Int(until.timeIntervalSinceNow.rounded(.up)), 1)
            progressBar.show(text: SeekMailL10n.format("额度用完，约 %@ 秒后继续 · %@/%@", String(seconds), String(done), String(total)),
                             progress: Float(done) / Float(max(total, 1)),
                             actionTitle: SeekMailL10n.text("停止")) { [weak self] in self?.markJob.stop() }
        case .finished(let succeeded, let failed):
            model.refreshUnreadCounts()
            if failed == 0 {
                progressBar.hide()
                undoToast.showMessage(SeekMailL10n.format("已标为已读 %@ 封", String(succeeded)), in: view)
            } else {
                progressBar.show(text: SeekMailL10n.format("%@ 封成功，%@ 封失败", String(succeeded), String(failed)), progress: nil,
                                 actionTitle: SeekMailL10n.text("重试")) { [weak self] in self?.markJob.retryFailed() }
            }
        case .stopped(let done, let total):
            progressBar.hide()
            model.refreshUnreadCounts()
            if viewIfLoaded?.window != nil {
                undoToast.showMessage(SeekMailL10n.format("已停止，已处理 %@/%@", String(done), String(total)), in: view)
            }
        }
        onNavigationChange?()
    }

    private func presentCreateMailbox() {
        let create = SeekMailCreateMailboxViewController(provider: model.provider) { [weak self] mailbox in
            guard let self else { return }
            model.addCreatedMailbox(mailbox)
            UIPasteboard.general.string = mailbox.address
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            undoToast.showMessage(SeekMailL10n.format("已创建并复制 %@", mailbox.address), in: view)
            onNavigationChange?()
        }
        let navigation = UINavigationController(rootViewController: create)
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(navigation, animated: true)
    }

    private func copyAddress(_ address: String) {
        UIPasteboard.general.string = address
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        undoToast.showMessage(SeekMailL10n.format("已复制 %@", address), in: view)
    }

    /// 入口页「更多」菜单里属于列表的部分。
    func menuElements() -> [UIMenuElement] {
        let refresh = UIAction(title: SeekMailL10n.text("刷新"), image: UIImage(systemName: "arrow.clockwise")) { [weak self] _ in
            self?.model.reload()
        }
        let storage = UIDeferredMenuElement.uncached { [weak self] completion in
            guard let self else { return completion([]) }
            Task {
                let item: UIAction
                if let quota = try? await self.model.provider.quota(), let storage = quota.storage {
                    let percent = storage.usagePercent ?? Int(Double(storage.used) / Double(max(storage.quota, 1)) * 100)
                    item = UIAction(title: SeekMailL10n.text("存储用量"), subtitle: "\(SeekMailFormat.bytes(storage.used)) / \(SeekMailFormat.bytes(storage.quota)) · \(percent)%",
                                    image: UIImage(systemName: "internaldrive")) { _ in }
                } else {
                    item = UIAction(title: SeekMailL10n.text("存储用量"), subtitle: SeekMailL10n.text("暂时无法获取"), image: UIImage(systemName: "internaldrive"),
                                    attributes: .disabled) { _ in }
                }
                completion([item])
            }
        }
        let current = model.selectionStore.autoRefreshSeconds
        let intervals = SeekMailSelectionStore.autoRefreshOptions.map { seconds in
            UIAction(title: Self.autoRefreshTitle(seconds), state: seconds == current ? .on : .off) { [weak self] _ in
                guard let self else { return }
                model.selectionStore.autoRefreshSeconds = seconds
                if viewIfLoaded?.window != nil { startAutoRefresh() }
                // 让入口页重建菜单，显示新的勾选
                onNavigationChange?()
            }
        }
        let autoRefresh = UIMenu(title: SeekMailL10n.text("自动刷新"), subtitle: Self.autoRefreshTitle(current),
                                 image: UIImage(systemName: "timer"), children: intervals)
        let markAll = UIAction(title: SeekMailL10n.text("全部标为已读"), image: UIImage(systemName: "envelope.open"),
                               attributes: model.unreadTotal == 0 || markJob.isActive ? .disabled : []) { [weak self] _ in
            self?.markAllRead()
        }
        let create = UIAction(title: SeekMailL10n.text("新建邮箱"), image: UIImage(systemName: "plus")) { [weak self] _ in
            self?.presentCreateMailbox()
        }
        return [refresh, markAll, create, autoRefresh, storage]
    }

    // MARK: - 布局

    private func setupLayout() {
        folderTabs.translatesAutoresizingMaskIntoConstraints = false

        noticeLabel.font = SeekMailFont.of(.footnote)
        noticeLabel.textColor = .secondaryLabel
        noticeLabel.numberOfLines = 0
        noticeLabel.textAlignment = .center
        noticeLabel.accessibilityIdentifier = "seek-mail-notice"
        noticeLabel.translatesAutoresizingMaskIntoConstraints = false
        noticeBar.backgroundColor = .secondarySystemBackground
        noticeBar.addSubview(noticeLabel)

        tableView.dataSource = self
        tableView.delegate = self
        tableView.estimatedRowHeight = 76
        tableView.rowHeight = UITableView.automaticDimension
        tableView.register(SeekMailCell.self, forCellReuseIdentifier: SeekMailCell.reuseIdentifier)
        tableView.register(SeekMailSkeletonCell.self, forCellReuseIdentifier: SeekMailSkeletonCell.reuseIdentifier)
        tableView.register(SeekMailCodeCell.self, forCellReuseIdentifier: SeekMailCodeCell.reuseIdentifier)
        tableView.accessibilityIdentifier = "seek-mail-list"
        tableView.keyboardDismissMode = .onDrag
        let refresh = UIRefreshControl()
        refresh.addAction(UIAction { [weak self] _ in
            self?.model.reload()
            self?.model.refreshUnreadCounts()
        }, for: .valueChanged)
        tableView.refreshControl = refresh

        progressBar.isHidden = true
        let stack = UIStackView(arrangedSubviews: [mailboxTags, folderTabs, progressBar, noticeBar, tableView])
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            folderTabs.heightAnchor.constraint(equalToConstant: 44),
            noticeLabel.leadingAnchor.constraint(equalTo: noticeBar.layoutMarginsGuide.leadingAnchor),
            noticeLabel.trailingAnchor.constraint(equalTo: noticeBar.layoutMarginsGuide.trailingAnchor),
            noticeLabel.topAnchor.constraint(equalTo: noticeBar.topAnchor, constant: 7),
            noticeLabel.bottomAnchor.constraint(equalTo: noticeBar.bottomAnchor, constant: -7)
        ])
        configureSearch()
        undoToast.onUndo = { [weak self] in
            guard let self, let id = lastDeletedID else { return }
            model.undoDelete(id)
            lastDeletedID = nil
        }
    }

    /// 搜索要请求接口，所以点键盘「搜索」才发；清空或取消时立即回到普通列表。
    private func configureSearch() {
        searchBar.textField.accessibilityIdentifier = "seek-mail-search"
        searchBar.onSubmit = { [weak self] text in self?.model.setSearchText(text) }
        searchBar.onChange = { [weak self] text in
            if text.isEmpty { self?.model.setSearchText("") }
        }
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchBar)
        NSLayoutConstraint.activate([
            searchBar.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            searchBar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -8),
        ])
        // 提示条放在搜索框上方，避免挡住它
        undoToast.bottomOffset = ProbeSearchBarView.height + 8 + 12
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 列表底部让出搜索框的位置；安全区由系统自动加，这里只补高出的部分
        let bottom = max(view.bounds.maxY - searchBar.frame.minY + 8 - view.safeAreaInsets.bottom, 0)
        if tableView.contentInset.bottom != bottom {
            tableView.contentInset.bottom = bottom
            tableView.verticalScrollIndicatorInsets.bottom = bottom
        }
    }

    // MARK: - 渲染

    private func render() {
        tableView.refreshControl?.endRefreshing()
        updateTags()
        onNavigationChange?()
        folderTabs.update(scopes: model.scopes, titles: model.scopes.map(model.title(for:)), selected: model.scope)
        searchBar.textField.placeholder = SeekMailL10n.format("搜索 %@ · %@", model.selectionTitle, model.scopeTitle)
        updateNotice()
        updateBackground()
        tableView.reloadData()
        if lastDeletedID != nil, model.hasPendingDeletes == false {
            lastDeletedID = nil
            undoToast.dismiss()
        }
    }

    private func updateTags() {
        mailboxTags.isHidden = model.mailboxes.isEmpty
        mailboxTags.update(tags: model.mailboxTags, selectedID: model.selectedMailboxID,
                           expanded: model.selectionStore.tagsExpanded)
    }

    private func updateNotice() {
        noticeTimer?.invalidate()
        noticeTimer = nil
        var text: String?
        if let until = model.rateLimitedUntil, until > Date() {
            let seconds = Int(until.timeIntervalSinceNow.rounded(.up))
            text = SeekMailL10n.format("请求太频繁，%@ 秒后可刷新", String(seconds))
            noticeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateNotice() }
            }
        } else if model.isSearching {
            text = SeekMailL10n.format("只搜索 %@ · %@", model.selectionTitle, model.scopeTitle)
        } else if model.isTrash {
            text = SeekMailL10n.text("回收站只能查看 · 网页中恢复")
        }
        noticeLabel.text = text
        noticeBar.isHidden = text == nil
    }

    private func updateBackground() {
        switch model.phase {
        case .loading:
            tableView.backgroundView = nil
            tableView.separatorStyle = .singleLine
        case .failed(let message):
            tableView.backgroundView = SeekMailStateView(message: message, actionTitle: SeekMailL10n.text("重试")) { [weak self] in
                self?.model.reload()
            }
            tableView.separatorStyle = .none
        case .loaded where model.mails.isEmpty:
            tableView.backgroundView = SeekMailStateView(message: emptyMessage, actionTitle: nil, action: nil)
            tableView.separatorStyle = .none
        case .loaded:
            tableView.backgroundView = nil
            tableView.separatorStyle = .singleLine
        }
    }

    private var emptyMessage: String {
        if model.isSearching { return SeekMailL10n.text("没有找到相关邮件") }
        switch model.scope {
        case .inbox: return SeekMailL10n.text("收件箱是空的\n新邮件到达后下拉刷新即可看到")
        case .spam: return SeekMailL10n.text("没有垃圾邮件")
        case .trash: return SeekMailL10n.text("回收站是空的")
        case .custom: return SeekMailL10n.text("这个文件夹里还没有邮件")
        }
    }

    // MARK: - 操作

    private func scheduleDelete(_ id: Int64) {
        model.scheduleDelete(id)
        lastDeletedID = id
        undoToast.showUndo(seconds: 4, in: view)
    }

    /// 写新信或回复；发送成功后在列表页提示。
    func presentCompose(_ content: SeekMailComposeContent = SeekMailComposeContent()) {
        var content = content
        if content.mailboxID == nil { content.mailboxID = model.selectedMailboxID }
        let compose = SeekMailComposeViewController(
            provider: model.provider, mailboxes: model.mailboxes, names: model.names, content: content
        ) { [weak self] in
            guard let self else { return }
            // 接口返回 queued 只代表进了发送队列，不代表已经送达
            undoToast.showMessage(SeekMailL10n.text("已提交发送"), in: view)
        }
        present(UINavigationController(rootViewController: compose), animated: true)
    }

    private func openMail(_ mail: SeekMail) {
        let detail = SeekMailDetailViewController(mailID: mail.id, model: model, onDelete: { [weak self] id in
            self?.scheduleDelete(id)
        }, onReply: { [weak self] content in
            self?.presentCompose(content)
        })
        navigationController?.pushViewController(detail, animated: true)
    }

    private func moveMenu(for mail: SeekMail) -> UIMenu {
        var targets: [(String, Int64?, SeekMailFolderScope)] = [(SeekMailL10n.text("收件箱"), nil, .inbox)]
        targets += model.folders.map { (model.title(for: .custom($0.id)), $0.id, .custom($0.id)) }
        let actions = targets.filter { $0.2 != model.scope }.map { title, folderID, _ in
            UIAction(title: title) { [weak self] _ in self?.model.move(mail.id, toFolderID: folderID) }
        }
        return UIMenu(title: SeekMailL10n.text("移动到…"), image: UIImage(systemName: "folder"), children: actions)
    }

    private func contextMenu(for mail: SeekMail) -> UIMenu {
        var sections: [UIMenuElement] = []
        if model.selectedMailboxID == nil, let display = model.names[mail.mailboxId] {
            sections.append(UIMenu(options: .displayInline, children: [
                UIAction(title: SeekMailL10n.format("只看 %@", display.title), subtitle: display.address, image: UIImage(systemName: "line.3.horizontal.decrease")) { [weak self] _ in
                    self?.model.selectMailbox(mail.mailboxId)
                }
            ]))
        }
        var actions: [UIMenuElement] = [
            UIAction(title: mail.isRead ? SeekMailL10n.text("标为未读") : SeekMailL10n.text("标为已读"),
                     image: UIImage(systemName: mail.isRead ? "envelope.badge" : "envelope.open")) { [weak self] _ in
                self?.model.setRead(mail.id, read: mail.isRead == false)
            },
            UIAction(title: mail.isFlagged ? SeekMailL10n.text("去掉星标") : SeekMailL10n.text("加星标"),
                     image: UIImage(systemName: mail.isFlagged ? "star.slash" : "star")) { [weak self] _ in
                self?.model.setFlagged(mail.id, flagged: mail.isFlagged == false)
            }
        ]
        // 回收站只读：不移动、不删除
        if model.isTrash == false {
            let move = moveMenu(for: mail)
            if move.children.isEmpty == false { actions.append(move) }
        }
        sections.append(UIMenu(options: .displayInline, children: actions))
        if model.isTrash == false {
            sections.append(UIAction(title: SeekMailL10n.text("删除"), image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                self?.scheduleDelete(mail.id)
            })
        }
        return UIMenu(children: sections)
    }
}

// MARK: - 表格

extension SeekMailInboxViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .code: return model.phase == .loaded && model.latestCodeMail() != nil ? 1 : 0
        case .mails: return model.phase == .loading ? 6 : model.mails.count
        case nil: return 0
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == Section.code.rawValue, let mail = model.latestCodeMail() {
            let cell = tableView.dequeueReusableCell(withIdentifier: SeekMailCodeCell.reuseIdentifier, for: indexPath) as! SeekMailCodeCell
            cell.configure(mail: mail, recipient: model.showsRecipientMailbox ? model.names[mail.mailboxId] : nil)
            return cell
        }
        if model.phase == .loading {
            return tableView.dequeueReusableCell(withIdentifier: SeekMailSkeletonCell.reuseIdentifier, for: indexPath)
        }
        let mail = model.mails[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: SeekMailCell.reuseIdentifier, for: indexPath) as! SeekMailCell
        cell.configure(mail: mail,
                       recipient: model.showsRecipientMailbox ? model.names[mail.mailboxId] : nil,
                       keyword: model.isSearching ? model.searchText : "")
        cell.accessibilityIdentifier = "seek-mail-row-\(mail.id)"
        return cell
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard indexPath.section == Section.mails.rawValue, model.phase == .loaded else { return }
        if indexPath.row >= model.mails.count - 4 { model.loadMoreIfNeeded() }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == Section.mails.rawValue, model.phase == .loaded,
              model.mails.indices.contains(indexPath.row) else { return }
        openMail(model.mails[indexPath.row])
    }

    private func mail(at indexPath: IndexPath) -> SeekMail? {
        guard indexPath.section == Section.mails.rawValue, model.phase == .loaded,
              model.mails.indices.contains(indexPath.row) else { return nil }
        return model.mails[indexPath.row]
    }

    /// 右滑只有已读/未读。
    func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let mail = mail(at: indexPath) else { return nil }
        let action = UIContextualAction(style: .normal, title: mail.isRead ? SeekMailL10n.text("未读") : SeekMailL10n.text("已读")) { [weak self] _, _, done in
            self?.model.setRead(mail.id, read: mail.isRead == false)
            done(true)
        }
        action.image = UIImage(systemName: mail.isRead ? "envelope.badge" : "envelope.open")
        action.backgroundColor = .systemGray
        return UISwipeActionsConfiguration(actions: [action])
    }

    /// 左滑删除，回收站里没有。
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let mail = mail(at: indexPath), model.isTrash == false else { return nil }
        let action = UIContextualAction(style: .destructive, title: SeekMailL10n.text("删除")) { [weak self] _, _, done in
            self?.scheduleDelete(mail.id)
            done(true)
        }
        action.image = UIImage(systemName: "trash")
        return UISwipeActionsConfiguration(actions: [action])
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard let mail = mail(at: indexPath) else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            self?.contextMenu(for: mail)
        }
    }
}

// MARK: - 小组件

/// 列表上方的进度条：逐封标已读时显示进度，可停止或重试。
final class SeekMailProgressBar: UIView {
    private let label = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let button = UIButton(type: .system)
    private var action: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemBackground
        accessibilityIdentifier = "seek-mail-progress"
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.accessibilityIdentifier = "seek-mail-progress-text"
        progressView.progressTintColor = .label
        progressView.trackTintColor = .tertiarySystemFill
        button.accessibilityIdentifier = "seek-mail-progress-action"
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.addAction(UIAction { [weak self] _ in self?.action?() }, for: .touchUpInside)
        let row = UIStackView(arrangedSubviews: [label, button])
        row.alignment = .center
        row.spacing = 8
        let column = UIStackView(arrangedSubviews: [row, progressView])
        column.axis = .vertical
        column.spacing = 6
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            column.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            column.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var text: String? { label.text }

    func show(text: String, progress: Float?, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        label.font = SeekMailFont.of(.footnote)
        label.text = text
        progressView.isHidden = progress == nil
        progressView.setProgress(progress ?? 0, animated: isHidden == false)
        self.action = action
        button.isHidden = actionTitle == nil
        if let actionTitle {
            var configuration = UIButton.Configuration.plain()
            configuration.baseForegroundColor = .label
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 0)
            var title = AttributedString(actionTitle)
            title.font = SeekMailFont.of(.footnote, weight: .semibold)
            configuration.attributedTitle = title
            button.configuration = configuration
        }
        isHidden = false
    }

    func hide() {
        action = nil
        isHidden = true
    }
}

/// 横向文件夹 tab，选中态用 .label 反色胶囊。
final class SeekMailFolderTabsView: UIView {
    var onSelect: ((SeekMailFolderScope) -> Void)?
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var scopes: [SeekMailFolderScope] = []
    private var buttons: [UIButton] = []
    private var selectedIndex: Int?
    /// 选中下划线：邮箱标签已经用了反色胶囊，文件夹用文字加下划线区分层级。
    private let indicator = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stack.spacing = 6
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        scrollView.addSubview(stack)
        indicator.backgroundColor = .label
        scrollView.addSubview(indicator)
        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: scrollView.frameLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.frameLayoutGuide.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
        ])
        accessibilityIdentifier = "seek-mail-folder-tabs"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(scopes: [SeekMailFolderScope], titles: [String], selected: SeekMailFolderScope) {
        if scopes != self.scopes {
            self.scopes = scopes
            buttons.forEach { $0.removeFromSuperview() }
            buttons = zip(scopes, titles).map { scope, title in
                let button = UIButton(type: .system)
                button.accessibilityIdentifier = "seek-mail-folder-\(scope.storageValue)"
                button.addAction(UIAction { [weak self] _ in self?.onSelect?(scope) }, for: .touchUpInside)
                return button
            }
            buttons.forEach(stack.addArrangedSubview)
        }
        selectedIndex = scopes.firstIndex(of: selected)
        setNeedsLayout()
        for (index, button) in buttons.enumerated() {
            let isSelected = scopes[index] == selected
            var configuration = UIButton.Configuration.plain()
            configuration.baseForegroundColor = isSelected ? .label : .secondaryLabel
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)
            var title = AttributedString(titles[index])
            title.font = SeekMailFont.system(15, weight: isSelected ? .semibold : .regular)
            configuration.attributedTitle = title
            button.configuration = configuration
            button.accessibilityTraits = isSelected ? [.button, .selected] : .button
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let selectedIndex, buttons.indices.contains(selectedIndex) else {
            indicator.isHidden = true
            return
        }
        scrollView.layoutIfNeeded()
        let frame = buttons[selectedIndex].convert(buttons[selectedIndex].bounds, to: scrollView)
        indicator.isHidden = false
        indicator.frame = CGRect(x: frame.minX + 8, y: bounds.height - 2, width: max(frame.width - 16, 0), height: 2)
    }
}

/// 空列表和加载失败时的居中提示。
final class SeekMailStateView: UIView {
    init(message: String, actionTitle: String?, action: (() -> Void)?) {
        super.init(frame: .zero)
        let label = UILabel()
        label.text = message
        label.font = SeekMailFont.of(.subheadline)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.textAlignment = .center
        label.accessibilityIdentifier = "seek-mail-state-message"
        let stack = UIStackView(arrangedSubviews: [label])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        if let actionTitle, let action {
            var configuration = UIButton.Configuration.filled()
            configuration.baseBackgroundColor = .label
            configuration.baseForegroundColor = .systemBackground
            configuration.cornerStyle = .capsule
            configuration.title = actionTitle
            let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
            button.accessibilityIdentifier = "seek-mail-state-action"
            stack.addArrangedSubview(button)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -40),
            stack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor, constant: -24)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// 底部 toast：删除后倒计时可撤销，或者显示一句错误提示。
final class SeekMailUndoToast: UIView {
    var onUndo: (() -> Void)?
    /// 距离安全区底部的距离，第一次显示前设置才生效。
    var bottomOffset: CGFloat = 12
    private let label = UILabel()
    private let undoButton = UIButton(type: .system)
    private var timer: Timer?
    private var remaining = 0

    init() {
        super.init(frame: .zero)
        backgroundColor = .label
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        label.textColor = .systemBackground
        label.numberOfLines = 2
        label.accessibilityIdentifier = "seek-mail-toast-message"
        refreshFonts()
        undoButton.accessibilityIdentifier = "seek-mail-toast-undo"
        undoButton.setContentHuggingPriority(.required, for: .horizontal)
        undoButton.addAction(UIAction { [weak self] _ in
            self?.onUndo?()
            self?.dismiss()
        }, for: .touchUpInside)
        let row = UIStackView(arrangedSubviews: [label, undoButton])
        row.alignment = .center
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 36)
        ])
        accessibilityIdentifier = "seek-mail-toast"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func refreshFonts() {
        label.font = SeekMailFont.of(.subheadline)
        var configuration = UIButton.Configuration.plain()
        configuration.baseForegroundColor = .systemBackground
        var title = AttributedString(SeekMailL10n.text("撤销"))
        title.font = SeekMailFont.system(15, weight: .semibold)
        configuration.attributedTitle = title
        undoButton.configuration = configuration
    }

    func showUndo(seconds: Int, in container: UIView?) {
        remaining = seconds
        undoButton.isHidden = false
        label.text = SeekMailL10n.format("已删除 · %@", String(remaining))
        present(in: container)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        remaining -= 1
        if remaining <= 0 { dismiss() } else { label.text = SeekMailL10n.format("已删除 · %@", String(remaining)) }
    }

    func showMessage(_ message: String, in container: UIView?) {
        timer?.invalidate()
        undoButton.isHidden = true
        label.text = message
        present(in: container)
        timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
    }

    func dismiss() {
        timer?.invalidate()
        timer = nil
        guard superview != nil else { return }
        UIView.animate(withDuration: 0.2, animations: { self.alpha = 0 }) { _ in
            if self.alpha == 0 { self.removeFromSuperview() }
        }
    }

    private func present(in container: UIView?) {
        guard let container else { return }
        if superview !== container {
            removeFromSuperview()
            translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(self)
            NSLayoutConstraint.activate([
                leadingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.leadingAnchor, constant: 16),
                trailingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.trailingAnchor, constant: -16),
                bottomAnchor.constraint(equalTo: container.safeAreaLayoutGuide.bottomAnchor, constant: -bottomOffset)
            ])
        }
        layer.removeAllAnimations()
        alpha = 1
        container.bringSubviewToFront(self)
    }
}
