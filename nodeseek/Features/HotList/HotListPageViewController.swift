//
//  HotListPageViewController.swift
//  nodeseek
//

import UIKit

/// 单个榜单的列表页，三个榜单各自一页，左右滑动切换。失败时保留上次结果。
final class HotListPageViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    let kind: HotListKind
    var onSelectPost: ((PostSummary) -> Void)?

    private let repository: HotListRepository
    /// 与首页列表共用已读记录，点过的帖子在两处都显示为已读。
    private let visitedStore: VisitedPostStoreProtocol
    private var entries: [HotListEntry] = []
    private var snapshot: HotListSnapshot?
    private var lastLoadFailed = false
    private var failureError: Error?
    private var loadTask: Task<Void, Never>?

    private let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private let rangeLabel = HotListPageViewController.makeStripLabel()
    private let updatedLabel = HotListPageViewController.makeStripLabel()
    private let stripView: UIView = {
        let view = UIView()
        view.backgroundColor = .secondarySystemBackground
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    let tableView = UITableView(frame: .zero, style: .plain)

    init(kind: HotListKind, repository: HotListRepository, visitedStore: VisitedPostStoreProtocol = VisitedPostStore.shared) {
        self.kind = kind
        self.repository = repository
        self.visitedStore = visitedStore
        super.init(nibName: nil, bundle: nil)
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
        renderStrip()
        renderBackground()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 首次显示或缓存过期后才真正请求；未滑到的榜单不提前请求
        if loadTask == nil {
            load(userInitiated: false)
        }
        renderStrip()
        // 从首页或详情返回时，同步其他地方新读过的帖子
        if let visible = tableView.indexPathsForVisibleRows, !visible.isEmpty {
            tableView.reloadRows(at: visible, with: .none)
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // 统计图标是带颜色的图片，切换深浅色后需重新生成
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            tableView.reloadData()
        }
    }

    func scrollToTop() {
        guard !entries.isEmpty else { return }
        tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: true)
    }

    // MARK: - Setup

    private func setupStrip() {
        updatedLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        rangeLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let stack = UIStackView(arrangedSubviews: [rangeLabel, UIView(), updatedLabel])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        stripView.addSubview(stack)
        view.addSubview(stripView)
        NSLayoutConstraint.activate([
            stripView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
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
        tableView.accessibilityIdentifier = "hot-list-table-\(kind.rawValue)"
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

    private func load(userInitiated: Bool) {
        let kind = kind
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            // 先显示缓存，避免切回本页时闪一下加载状态
            if self.snapshot == nil, let cached = await self.repository.cachedSnapshot(for: kind) {
                self.apply(cached)
            }
            do {
                let result = try await self.repository.load(kind, userInitiated: userInitiated)
                guard !Task.isCancelled else { return }
                self.lastLoadFailed = false
                if result != self.snapshot { self.apply(result) }
            } catch {
                guard !Task.isCancelled, !UserFacingError.isCancellation(error) else { return }
                self.lastLoadFailed = true
                self.failureError = error
                if self.snapshot != nil, self.view.window != nil {
                    BottomToast.show(HotListL10n.text("更新失败，显示的是上次的数据"), style: .failure, in: self.view)
                }
            }
            self.loadTask = nil
            self.tableView.refreshControl?.endRefreshing()
            self.renderStrip()
            self.renderBackground()
        }
        renderStrip()
        renderBackground()
    }

    private func apply(_ newSnapshot: HotListSnapshot) {
        snapshot = newSnapshot
        entries = newSnapshot.response.entries
        tableView.reloadData()
        renderStrip()
        renderBackground()
    }

    private func renderStrip() {
        rangeLabel.text = kind.rangeDescription
        if lastLoadFailed {
            updatedLabel.text = HotListL10n.text("更新失败")
        } else if let snapshot {
            let date = snapshot.response.updatedAt ?? snapshot.fetchedAt
            updatedLabel.text = HotListL10n.format("%@更新", relativeText(for: date))
        } else {
            updatedLabel.text = loadTask == nil ? nil : HotListL10n.text("正在加载…")
        }
    }

    private func renderBackground() {
        guard entries.isEmpty else {
            tableView.backgroundView = nil
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
            // 已在显示骨架屏时不重建，避免呼吸动画重新开始
            if !(tableView.backgroundView is HotListSkeletonView) {
                tableView.backgroundView = HotListSkeletonView()
            }
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

    @objc private func sourceSettingsChanged() {
        loadTask?.cancel()
        loadTask = nil
        snapshot = nil
        entries = []
        lastLoadFailed = false
        tableView.reloadData()
        // 不在屏幕上的榜单等下次显示时再请求
        if view.window != nil {
            load(userInitiated: false)
        } else {
            renderStrip()
            renderBackground()
        }
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
            timeText: entry.postedAt.map(relativeText(for:)),
            isVisited: visitedStore.isVisited(postID: String(entry.postID))
        )
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard entries.indices.contains(indexPath.row) else { return }
        let post = entries[indexPath.row].postSummary
        // 点击即记为已读，和首页一样不等详情加载完成
        visitedStore.markVisited(post: post, visitedAt: Date())
        tableView.reloadRows(at: [indexPath], with: .none)
        onSelectPost?(post)
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
