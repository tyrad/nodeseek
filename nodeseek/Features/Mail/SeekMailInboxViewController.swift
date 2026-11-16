//
//  SeekMailInboxViewController.swift
//  nodeseek
//

import SafariServices
import UIKit

/// 已绑定时的邮件列表。导航栏的标题按钮和搜索框由入口页挂到自己的导航栏上。
final class SeekMailInboxViewController: UIViewController {
    let model: SeekMailInboxModel
    /// 401 时回调，由入口页清掉 Key 并回到绑定页。
    var onUnauthorized: (() -> Void)?
    /// 标题或搜索框变化后，入口页要重新同步导航栏。
    var onNavigationChange: (() -> Void)?

    private(set) lazy var titleButton = makeTitleButton()
    private(set) lazy var searchController = makeSearchController()

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let folderTabs = SeekMailFolderTabsView()
    private let noticeLabel = UILabel()
    private let noticeBar = UIView()
    private let undoToast = SeekMailUndoToast()
    private var searchDebounce: DispatchWorkItem?
    private var noticeTimer: Timer?
    private var lastDeletedID: Int64?

    private enum Section: Int, CaseIterable { case code, mails }

    init(keyStore: SeekMailAPIKeyStoring,
         transport: SeekMailProvider<SeekMailAPI>.Transport? = nil,
         selectionStore: SeekMailSelectionStore = SeekMailSelectionStore(),
         deleteDelay: TimeInterval = 4) {
        let provider: SeekMailProvider<SeekMailAPI>
        if let transport {
            provider = SeekMailProvider(apiKey: { [keyStore] in keyStore.apiKey() }, transport: transport)
        } else {
            provider = SeekMailProvider(apiKey: { [keyStore] in keyStore.apiKey() })
        }
        model = SeekMailInboxModel(provider: provider, selectionStore: selectionStore, deleteDelay: deleteDelay)
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
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification, object: nil
        )
        render()
        model.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // 推入详情页不算离开列表，只有真正离开才立即提交删除
        if isMovingFromParent || parent?.isMovingFromParent == true || navigationController?.isBeingDismissed == true {
            model.commitPendingDeletes()
        }
    }

    @objc private func appWillResignActive() {
        model.commitPendingDeletes()
        undoToast.dismiss()
    }

    /// 入口页「更多」菜单里属于列表的部分。
    func menuElements() -> [UIMenuElement] {
        let refresh = UIAction(title: "刷新", image: UIImage(systemName: "arrow.clockwise")) { [weak self] _ in
            self?.model.reload()
        }
        let storage = UIDeferredMenuElement.uncached { [weak self] completion in
            guard let self else { return completion([]) }
            Task {
                let item: UIAction
                if let quota = try? await self.model.provider.quota(), let storage = quota.storage {
                    let percent = storage.usagePercent ?? Int(Double(storage.used) / Double(max(storage.quota, 1)) * 100)
                    item = UIAction(title: "存储用量", subtitle: "\(SeekMailFormat.bytes(storage.used)) / \(SeekMailFormat.bytes(storage.quota)) · \(percent)%",
                                    image: UIImage(systemName: "internaldrive")) { _ in }
                } else {
                    item = UIAction(title: "存储用量", subtitle: "暂时无法获取", image: UIImage(systemName: "internaldrive"),
                                    attributes: .disabled) { _ in }
                }
                completion([item])
            }
        }
        return [refresh, storage]
    }

    // MARK: - 布局

    private func setupLayout() {
        folderTabs.translatesAutoresizingMaskIntoConstraints = false

        noticeLabel.font = .preferredFont(forTextStyle: .footnote)
        noticeLabel.textColor = .secondaryLabel
        noticeLabel.adjustsFontForContentSizeCategory = true
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
        refresh.addAction(UIAction { [weak self] _ in self?.model.reload() }, for: .valueChanged)
        tableView.refreshControl = refresh

        let stack = UIStackView(arrangedSubviews: [folderTabs, noticeBar, tableView])
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
        undoToast.onUndo = { [weak self] in
            guard let self, let id = lastDeletedID else { return }
            model.undoDelete(id)
            lastDeletedID = nil
        }
    }

    private func makeTitleButton() -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.baseForegroundColor = .label
        configuration.image = UIImage(systemName: "chevron.down")
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 4
        configuration.titleLineBreakMode = .byTruncatingMiddle
        let button = UIButton(configuration: configuration)
        button.accessibilityIdentifier = "seek-mail-title"
        button.addAction(UIAction { [weak self] _ in self?.presentMailboxPickerIfNeeded() }, for: .touchUpInside)
        return button
    }

    private func makeSearchController() -> UISearchController {
        let controller = UISearchController(searchResultsController: nil)
        controller.obscuresBackgroundDuringPresentation = false
        controller.searchResultsUpdater = self
        controller.searchBar.accessibilityIdentifier = "seek-mail-search"
        return controller
    }

    // MARK: - 渲染

    private func render() {
        tableView.refreshControl?.endRefreshing()
        updateTitle()
        folderTabs.update(scopes: model.scopes, titles: model.scopes.map(model.title(for:)), selected: model.scope)
        searchController.searchBar.placeholder = "搜索 \(model.selectionTitle) · \(model.scopeTitle)"
        updateNotice()
        updateBackground()
        tableView.reloadData()
        if lastDeletedID != nil, model.hasPendingDeletes == false {
            lastDeletedID = nil
            undoToast.dismiss()
        }
    }

    private func updateTitle() {
        var title = AttributedString(model.selectionTitle)
        title.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        if model.selectedMailboxID == nil, model.mailboxes.isEmpty == false {
            var count = AttributedString(" \(model.mailboxes.count)")
            count.font = UIFont.systemFont(ofSize: 13, weight: .regular)
            count.foregroundColor = .secondaryLabel
            title += count
        }
        titleButton.configuration?.attributedTitle = title
        titleButton.accessibilityLabel = "\(model.selectionTitle)，切换邮箱"
        // 5 个及以内直接用系统菜单；更多时弹出可搜索的面板
        if model.mailboxes.count <= 5, model.mailboxes.isEmpty == false {
            titleButton.menu = makeMailboxMenu()
            titleButton.showsMenuAsPrimaryAction = true
        } else {
            titleButton.menu = nil
            titleButton.showsMenuAsPrimaryAction = false
        }
        titleButton.sizeToFit()
        onNavigationChange?()
    }

    private func updateNotice() {
        noticeTimer?.invalidate()
        noticeTimer = nil
        var text: String?
        if let until = model.rateLimitedUntil, until > Date() {
            let seconds = Int(until.timeIntervalSinceNow.rounded(.up))
            text = "请求太频繁，\(seconds) 秒后可刷新"
            noticeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateNotice() }
            }
        } else if model.isSearching {
            text = "只搜索 \(model.selectionTitle) · \(model.scopeTitle)"
        } else if model.isTrash {
            text = "回收站只能查看 · 网页中恢复"
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
            tableView.backgroundView = SeekMailStateView(message: message, actionTitle: "重试") { [weak self] in
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
        if model.isSearching { return "没有找到相关邮件" }
        switch model.scope {
        case .inbox: return "收件箱是空的\n新邮件到达后下拉刷新即可看到"
        case .spam: return "没有垃圾邮件"
        case .trash: return "回收站是空的"
        case .custom: return "这个文件夹里还没有邮件"
        }
    }

    // MARK: - 切换邮箱

    private func makeMailboxMenu() -> UIMenu {
        let all = UIAction(title: "全部邮箱", state: model.selectedMailboxID == nil ? .on : .off) { [weak self] _ in
            self?.model.selectMailbox(nil)
        }
        let items = model.mailboxes.map { mailbox in
            let display = model.names[mailbox.id]
            return UIAction(title: display?.title ?? mailbox.address,
                            subtitle: display?.domainSuffix == nil ? (display?.hasAlias == true ? mailbox.address : nil) : display?.domainSuffix,
                            state: model.selectedMailboxID == mailbox.id ? .on : .off) { [weak self] _ in
                self?.model.selectMailbox(mailbox.id)
            }
        }
        return UIMenu(children: [UIMenu(options: .displayInline, children: [all]), UIMenu(options: .displayInline, children: items)])
    }

    private func presentMailboxPickerIfNeeded() {
        guard model.mailboxes.count > 5 else { return }
        let picker = SeekMailboxPickerViewController(model: model) { [weak self] id in
            self?.model.selectMailbox(id)
        }
        let navigation = UINavigationController(rootViewController: picker)
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
        }
        present(navigation, animated: true)
    }

    // MARK: - 操作

    private func scheduleDelete(_ id: Int64) {
        model.scheduleDelete(id)
        lastDeletedID = id
        undoToast.showUndo(seconds: 4, in: view)
    }

    private func openMail(_ mail: SeekMail) {
        model.setRead(mail.id, read: true, silent: true)
    }

    private func moveMenu(for mail: SeekMail) -> UIMenu {
        var targets: [(String, Int64?, SeekMailFolderScope)] = [("收件箱", nil, .inbox)]
        targets += model.folders.map { (model.title(for: .custom($0.id)), $0.id, .custom($0.id)) }
        let actions = targets.filter { $0.2 != model.scope }.map { title, folderID, _ in
            UIAction(title: title) { [weak self] _ in self?.model.move(mail.id, toFolderID: folderID) }
        }
        return UIMenu(title: "移动到…", image: UIImage(systemName: "folder"), children: actions)
    }

    private func contextMenu(for mail: SeekMail) -> UIMenu {
        var sections: [UIMenuElement] = []
        if model.selectedMailboxID == nil, let display = model.names[mail.mailboxId] {
            sections.append(UIMenu(options: .displayInline, children: [
                UIAction(title: "只看 \(display.title)", subtitle: display.address, image: UIImage(systemName: "line.3.horizontal.decrease")) { [weak self] _ in
                    self?.model.selectMailbox(mail.mailboxId)
                }
            ]))
        }
        var actions: [UIMenuElement] = [
            UIAction(title: mail.isRead ? "标为未读" : "标为已读",
                     image: UIImage(systemName: mail.isRead ? "envelope.badge" : "envelope.open")) { [weak self] _ in
                self?.model.setRead(mail.id, read: mail.isRead == false)
            },
            UIAction(title: mail.isFlagged ? "去掉星标" : "加星标",
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
            sections.append(UIAction(title: "删除", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
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
        let action = UIContextualAction(style: .normal, title: mail.isRead ? "未读" : "已读") { [weak self] _, _, done in
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
        let action = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, done in
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

// MARK: - 搜索

extension SeekMailInboxViewController: UISearchResultsUpdating {
    /// 停顿 400ms 再请求，避免每输入一个字就打一次接口。
    func updateSearchResults(for searchController: UISearchController) {
        let text = searchController.searchBar.text ?? ""
        searchDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.model.setSearchText(text) }
        searchDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (text.isEmpty ? 0 : 0.4), execute: work)
    }
}

// MARK: - 小组件

/// 横向文件夹 tab，选中态用 .label 反色胶囊。
final class SeekMailFolderTabsView: UIView {
    var onSelect: ((SeekMailFolderScope) -> Void)?
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var scopes: [SeekMailFolderScope] = []
    private var buttons: [UIButton] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stack.spacing = 6
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        scrollView.addSubview(stack)
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
            stack.centerYAnchor.constraint(equalTo: scrollView.frameLayoutGuide.centerYAnchor),
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
        for (index, button) in buttons.enumerated() {
            let isSelected = scopes[index] == selected
            var configuration = isSelected ? UIButton.Configuration.filled() : UIButton.Configuration.plain()
            configuration.cornerStyle = .capsule
            configuration.baseBackgroundColor = .label
            configuration.baseForegroundColor = isSelected ? .systemBackground : .secondaryLabel
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12)
            var title = AttributedString(titles[index])
            title.font = UIFont.systemFont(ofSize: 15, weight: isSelected ? .semibold : .regular)
            configuration.attributedTitle = title
            button.configuration = configuration
            button.accessibilityTraits = isSelected ? [.button, .selected] : .button
        }
    }
}

/// 空列表和加载失败时的居中提示。
final class SeekMailStateView: UIView {
    init(message: String, actionTitle: String?, action: (() -> Void)?) {
        super.init(frame: .zero)
        let label = UILabel()
        label.text = message
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.adjustsFontForContentSizeCategory = true
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
    private let label = UILabel()
    private let undoButton = UIButton(type: .system)
    private var timer: Timer?
    private var remaining = 0

    init() {
        super.init(frame: .zero)
        backgroundColor = .label
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .systemBackground
        label.numberOfLines = 2
        label.accessibilityIdentifier = "seek-mail-toast-message"
        var configuration = UIButton.Configuration.plain()
        configuration.baseForegroundColor = .systemBackground
        var title = AttributedString("撤销")
        title.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        configuration.attributedTitle = title
        undoButton.configuration = configuration
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

    func showUndo(seconds: Int, in container: UIView?) {
        remaining = seconds
        undoButton.isHidden = false
        label.text = "已删除 · \(remaining)"
        present(in: container)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        remaining -= 1
        if remaining <= 0 { dismiss() } else { label.text = "已删除 · \(remaining)" }
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
                bottomAnchor.constraint(equalTo: container.safeAreaLayoutGuide.bottomAnchor, constant: -12)
            ])
        }
        layer.removeAllAnimations()
        alpha = 1
        container.bringSubviewToFront(self)
    }
}
