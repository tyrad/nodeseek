//
//  HotListViewController.swift
//  nodeseek
//

import UIKit

/// 热榜：实时 / 日榜 / 周榜共用一个列表。数据来自第三方，失败时保留上次结果。
final class HotListViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, TabReselectHandling {
    var onSelectPost: ((PostSummary) -> Void)?

    private let repository: HotListRepository
    private var selectedKind: HotListKind = .realtime
    private var entries: [HotListEntry] = []
    private var snapshot: HotListSnapshot?
    private var lastLoadFailed = false
    private var loadTask: Task<Void, Never>?

    private let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private var tabButtons: [HotListKind: CategoryTabButton] = [:]
    private let tabStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    private let tabSeparator: UIView = {
        let view = UIView()
        view.backgroundColor = .separator
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    private let rangeLabel = HotListViewController.makeStripLabel()
    private let updatedLabel = HotListViewController.makeStripLabel()
    private let stripView: UIView = {
        let view = UIView()
        view.backgroundColor = .secondarySystemBackground
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    private let tableView = UITableView(frame: .zero, style: .plain)

    init(repository: HotListRepository = HotListService.shared) {
        self.repository = repository
        super.init(nibName: nil, bundle: nil)
        title = HotListL10n.text("热榜")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never
        let settingsItem = UIBarButtonItem(
            image: UIImage(systemName: "slider.horizontal.3"),
            style: .plain,
            target: self,
            action: #selector(settingsTapped)
        )
        settingsItem.accessibilityLabel = HotListL10n.text("热榜设置")
        settingsItem.accessibilityIdentifier = "hot-list-settings-button"
        navigationItem.rightBarButtonItem = settingsItem
        setupTabs()
        setupStrip()
        setupTableView()
        NotificationCenter.default.addObserver(
            self, selector: #selector(sourceSettingsChanged),
            name: HotListSourceSettings.didChangeNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(appTextSizeDidChange),
            name: AppTextSizeSettings.didChangeNotification, object: nil
        )
        select(.realtime)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 返回本页时只在缓存过期后才真正请求
        if isViewLoaded, loadTask == nil, snapshot != nil {
            load(userInitiated: false)
        }
        renderStrip()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // 统计图标是带颜色的图片，切换深浅色后需重新生成
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            tableView.reloadData()
        }
    }

    func handleTabReselect() {
        guard !entries.isEmpty else { return }
        tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: true)
    }

    // MARK: - Setup

    private func setupTabs() {
        for kind in HotListKind.allCases {
            let button = CategoryTabButton()
            button.setTitle(kind.tabTitle, for: .normal)
            button.accessibilityIdentifier = "hot-list-tab-\(kind.rawValue)"
            button.addAction(UIAction { [weak self] _ in self?.select(kind) }, for: .touchUpInside)
            tabButtons[kind] = button
            tabStack.addArrangedSubview(button)
        }
        view.addSubview(tabStack)
        view.addSubview(tabSeparator)
        NSLayoutConstraint.activate([
            tabStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tabStack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            tabStack.trailingAnchor.constraint(lessThanOrEqualTo: view.layoutMarginsGuide.trailingAnchor),
            tabStack.heightAnchor.constraint(equalToConstant: 40),
            tabSeparator.topAnchor.constraint(equalTo: tabStack.bottomAnchor),
            tabSeparator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabSeparator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabSeparator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
        ])
    }

    private func setupStrip() {
        updatedLabel.textAlignment = .natural
        updatedLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        rangeLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let stack = UIStackView(arrangedSubviews: [rangeLabel, UIView(), updatedLabel])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        stripView.addSubview(stack)
        view.addSubview(stripView)
        NSLayoutConstraint.activate([
            stripView.topAnchor.constraint(equalTo: tabSeparator.bottomAnchor),
            stripView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stripView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: stripView.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: stripView.bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor)
        ])
    }

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .systemBackground
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 76
        tableView.accessibilityIdentifier = "hot-list-table"
        tableView.register(HotListCell.self, forCellReuseIdentifier: HotListCell.reuseIdentifier)
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(pullToRefresh), for: .valueChanged)
        tableView.refreshControl = refreshControl
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: stripView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - Loading

    private func select(_ kind: HotListKind) {
        let isSameKind = kind == selectedKind && snapshot?.kind == kind
        selectedKind = kind
        for (buttonKind, button) in tabButtons {
            button.applySelectedStyle(isSelected: buttonKind == kind)
            button.accessibilityTraits = buttonKind == kind ? [.button, .selected] : .button
        }
        guard !isSameKind else {
            handleTabReselect()
            return
        }
        loadTask?.cancel()
        loadTask = nil
        Task { [weak self] in
            guard let self else { return }
            let cached = await self.repository.cachedSnapshot(for: kind)
            guard self.selectedKind == kind else { return }
            self.lastLoadFailed = false
            self.apply(cached)
            self.load(userInitiated: false)
        }
    }

    private func load(userInitiated: Bool) {
        let kind = selectedKind
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.repository.load(kind, userInitiated: userInitiated)
                guard !Task.isCancelled, self.selectedKind == kind else { return }
                self.lastLoadFailed = false
                self.apply(result)
            } catch {
                guard !Task.isCancelled, !UserFacingError.isCancellation(error), self.selectedKind == kind else { return }
                self.lastLoadFailed = true
                if self.snapshot != nil {
                    BottomToast.show(HotListL10n.text("更新失败，显示的是上次的数据"), style: .failure, in: self.view)
                }
                self.renderFailure(error)
            }
            self.tableView.refreshControl?.endRefreshing()
            self.loadTask = nil
        }
        if snapshot == nil { renderBackground() }
    }

    private func apply(_ newSnapshot: HotListSnapshot?) {
        snapshot = newSnapshot
        entries = newSnapshot?.response.entries ?? []
        tableView.reloadData()
        if !entries.isEmpty {
            tableView.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top), animated: false)
        }
        renderStrip()
        renderBackground()
    }

    private func renderStrip() {
        rangeLabel.text = selectedKind.rangeDescription
        if lastLoadFailed {
            updatedLabel.text = HotListL10n.text("更新失败")
        } else if let snapshot {
            let date = snapshot.response.updatedAt ?? snapshot.fetchedAt
            updatedLabel.text = HotListL10n.format("%@更新", relativeText(for: date))
        } else {
            updatedLabel.text = loadTask == nil ? nil : HotListL10n.text("正在加载…")
        }
    }

    private var failureError: Error?

    private func renderFailure(_ error: Error) {
        failureError = error
        renderStrip()
        renderBackground()
    }

    private func renderBackground() {
        guard entries.isEmpty else {
            tableView.backgroundView = nil
            failureError = nil
            return
        }
        if snapshot == nil, lastLoadFailed {
            let message = failureError is HotListDecodingError
                ? HotListL10n.text("热榜数据格式不正确")
                : HotListL10n.text("网络不可用或热榜服务暂时无法访问")
            tableView.backgroundView = HotListStateView.message(
                symbolName: "wifi.exclamationmark",
                title: HotListL10n.text("热榜加载失败"),
                body: message,
                retryTitle: HotListL10n.text("重试")
            ) { [weak self] in
                self?.lastLoadFailed = false
                self?.load(userInitiated: false)
            }
        } else if snapshot == nil {
            tableView.backgroundView = HotListStateView.loading(text: HotListL10n.text("正在加载…"))
            renderStrip()
        } else {
            tableView.backgroundView = HotListStateView.message(
                symbolName: "flame",
                title: HotListL10n.text("暂时没有热门帖子"),
                body: HotListL10n.text("下拉可以刷新，稍后再来看看"),
                retryTitle: nil,
                onRetry: nil
            )
        }
    }

    private func relativeText(for date: Date) -> String {
        relativeFormatter.localizedString(for: min(date, Date()), relativeTo: Date())
    }

    // MARK: - Actions

    @objc private func pullToRefresh() {
        load(userInitiated: true)
    }

    @objc private func settingsTapped() {
        navigationController?.pushViewController(HotListSettingsViewController(repository: repository), animated: true)
    }

    @objc private func sourceSettingsChanged() {
        snapshot = nil
        entries = []
        lastLoadFailed = false
        tableView.reloadData()
        load(userInitiated: false)
    }

    @objc private func appTextSizeDidChange() {
        rangeLabel.font = Self.stripFont()
        updatedLabel.font = Self.stripFont()
        tableView.reloadData()
    }

    // MARK: - Table

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        entries.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: HotListCell.reuseIdentifier, for: indexPath)
        let entry = entries[indexPath.row]
        (cell as? HotListCell)?.configure(
            rank: indexPath.row + 1,
            entry: entry,
            timeText: entry.postedAt.map(relativeText(for:))
        )
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard entries.indices.contains(indexPath.row) else { return }
        onSelectPost?(entries[indexPath.row].postSummary)
    }

    private static func stripFont() -> UIFont {
        AppTypography.font(basePointSize: 12)
    }

    private static func makeStripLabel() -> UILabel {
        let label = UILabel()
        label.font = stripFont()
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        return label
    }
}
