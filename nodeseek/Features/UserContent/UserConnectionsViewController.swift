import UIKit

@MainActor
final class UserConnectionsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let model: UserConnectionsViewModel
    private var selectedKind: UserConnectionKind
    private let tabs = UISegmentedControl(items: UserConnectionKind.allCases.map(\.title))
    /// 横向分页容器：每个 Tab 一张独立表格，左右拖动时内容跟手，各自的滚动位置天然保留。
    private let pager = UIScrollView()
    private let tables: [UserConnectionKind: UITableView]
    private let skeletons = Dictionary(uniqueKeysWithValues: UserConnectionKind.allCases.map { ($0, UserListSkeletonView(style: .member)) })
    private var tasks: [UserConnectionKind: Task<Void, Never>] = [:]
    private var hasLinkedPopGesture = false

    init(initialKind: UserConnectionKind = .following, client: (any UserConnectionsLoading)? = nil) {
        selectedKind = initialKind
        model = UserConnectionsViewModel(client: client ?? NodeSeekUserContentClient())
        tables = Dictionary(uniqueKeysWithValues: UserConnectionKind.allCases.map { ($0, UITableView(frame: .zero, style: .insetGrouped)) })
        super.init(nibName: nil, bundle: nil)
        title = "关注与被关注"
        navigationItem.largeTitleDisplayMode = .never
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { tasks.values.forEach { $0.cancel() } }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        tabs.selectedSegmentIndex = pageIndex(of: selectedKind)
        tabs.accessibilityIdentifier = "connections-tabs"
        tabs.addTarget(self, action: #selector(tabChanged), for: .valueChanged)
        tabs.translatesAutoresizingMaskIntoConstraints = false
        pager.isPagingEnabled = true
        pager.bounces = false
        pager.showsHorizontalScrollIndicator = false
        pager.contentInsetAdjustmentBehavior = .never
        pager.accessibilityIdentifier = "connections-pager"
        pager.delegate = self
        pager.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tabs)
        view.addSubview(pager)
        NSLayoutConstraint.activate([
            tabs.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            tabs.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            tabs.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            tabs.heightAnchor.constraint(greaterThanOrEqualToConstant: 32),
            pager.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 12),
            pager.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pager.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pager.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        var previous: UITableView?
        for kind in UserConnectionKind.allCases {
            let table = tables[kind]!
            configure(table, kind: kind)
            pager.addSubview(table)
            NSLayoutConstraint.activate([
                table.topAnchor.constraint(equalTo: pager.contentLayoutGuide.topAnchor),
                table.bottomAnchor.constraint(equalTo: pager.contentLayoutGuide.bottomAnchor),
                table.leadingAnchor.constraint(equalTo: previous?.trailingAnchor ?? pager.contentLayoutGuide.leadingAnchor),
                table.widthAnchor.constraint(equalTo: pager.frameLayoutGuide.widthAnchor),
                table.heightAnchor.constraint(equalTo: pager.frameLayoutGuide.heightAnchor)
            ])
            previous = table
        }
        previous?.trailingAnchor.constraint(equalTo: pager.contentLayoutGuide.trailingAnchor).isActive = true
        model.onChange = { [weak self] kind in self?.render(kind) }
        UserConnectionKind.allCases.forEach(render)
        load(selectedKind)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 左边缘优先交给系统侧滑返回，分页拖动等它失败后才开始。
        if !hasLinkedPopGesture, let back = navigationController?.interactivePopGestureRecognizer {
            pager.panGestureRecognizer.require(toFail: back)
            hasLinkedPopGesture = true
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 首次布局和旋转后把分页对齐到当前 Tab
        guard !pager.isDragging, !pager.isDecelerating else { return }
        let target = CGPoint(x: CGFloat(pageIndex(of: selectedKind)) * pager.bounds.width, y: 0)
        if pager.contentOffset != target { pager.contentOffset = target }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent || navigationController?.isBeingDismissed == true {
            tasks.values.forEach { $0.cancel() }
        }
    }

    private func configure(_ table: UITableView, kind: UserConnectionKind) {
        table.backgroundColor = .systemGroupedBackground
        table.accessibilityIdentifier = "connections-list-\(kind)"
        table.dataSource = self
        table.delegate = self
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 116
        table.register(UserConnectionCell.self, forCellReuseIdentifier: "member")
        table.translatesAutoresizingMaskIntoConstraints = false
        let refreshControl = UIRefreshControl()
        refreshControl.addAction(UIAction { [weak self] _ in self?.load(kind, refresh: true) }, for: .valueChanged)
        table.refreshControl = refreshControl
    }

    private func pageIndex(of kind: UserConnectionKind) -> Int {
        UserConnectionKind.allCases.firstIndex(of: kind) ?? 0
    }

    private func kind(of tableView: UITableView) -> UserConnectionKind {
        tables.first { $0.value === tableView }?.key ?? selectedKind
    }

    @objc private func tabChanged() {
        let index = tabs.selectedSegmentIndex
        guard UserConnectionKind.allCases.indices.contains(index) else { return }
        pager.setContentOffset(CGPoint(x: CGFloat(index) * pager.bounds.width, y: 0), animated: true)
        select(UserConnectionKind.allCases[index])
    }

    private func select(_ kind: UserConnectionKind) {
        guard kind != selectedKind else { return }
        selectedKind = kind
        tabs.selectedSegmentIndex = pageIndex(of: kind)
        load(kind)
    }

    private func load(_ kind: UserConnectionKind, refresh: Bool = false) {
        let state = model.state(for: kind)
        guard refresh || (!state.isLoading && !state.hasLoaded) else { return }
        if refresh { tasks[kind]?.cancel() }
        let model = model
        tasks[kind] = Task { await model.load(kind, refresh: refresh) }
    }

    private func render(_ kind: UserConnectionKind) {
        guard let tableView = tables[kind], let refreshControl = tableView.refreshControl else { return }
        let state = model.state(for: kind)
        tableView.reloadData()
        if state.isLoading && state.hasLoaded { refreshControl.beginRefreshing() } else { refreshControl.endRefreshing() }
        tableView.backgroundView = !state.showsSkeleton && state.records.isEmpty ? messageView(kind: kind, error: state.errorMessage) : nil
        if let error = state.errorMessage, !state.records.isEmpty {
            let retry = UIButton(type: .system)
            retry.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 72)
            retry.titleLabel?.font = .preferredFont(forTextStyle: .footnote)
            retry.titleLabel?.adjustsFontForContentSizeCategory = true
            retry.titleLabel?.numberOfLines = 0
            retry.titleLabel?.textAlignment = .center
            retry.tintColor = .label
            retry.setTitle("\(error)\n点按重试", for: .normal)
            retry.addAction(UIAction { [weak self] _ in self?.load(kind, refresh: true) }, for: .touchUpInside)
            tableView.tableFooterView = retry
        } else {
            tableView.tableFooterView = nil
        }
    }

    private func messageView(kind: UserConnectionKind, error: String?) -> UIView {
        let container = UIView()
        let label = UILabel()
        label.text = error ?? kind.emptyText
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        let retry = UIButton(type: .system)
        retry.setTitle("重试", for: .normal)
        retry.tintColor = .label
        retry.isHidden = error == nil
        retry.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        retry.addAction(UIAction { [weak self] _ in self?.load(kind, refresh: true) }, for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [label, retry])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24)
        ])
        return container
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let state = model.state(for: kind(of: tableView))
        return state.showsSkeleton ? 0 : state.records.count
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        let kind = kind(of: tableView)
        return model.state(for: kind).showsSkeleton ? skeletons[kind] : nil
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        let kind = kind(of: tableView)
        guard model.state(for: kind).showsSkeleton, let skeleton = skeletons[kind] else { return UITableView.automaticDimension }
        return skeleton.systemLayoutSizeFitting(
            CGSize(width: tableView.bounds.width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let kind = kind(of: tableView)
        let state = model.state(for: kind)
        return state.hasLoaded ? "\(kind.title) · \(state.records.count) 人" : kind.title
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let state = model.state(for: kind(of: tableView))
        let cell = tableView.dequeueReusableCell(withIdentifier: "member", for: indexPath) as! UserConnectionCell
        cell.configure(state.records[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let state = model.state(for: kind(of: tableView))
        guard indexPath.row < state.records.count else { return }
        navigationController?.pushViewController(UserProfileViewController(uid: state.records[indexPath.row].uid), animated: true)
    }

    // 表格也会走这些回调，只处理分页容器
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === pager, pager.isTracking || pager.isDecelerating, let kind = currentPageKind() else { return }
        // 拖过一半就同步高亮 Tab，停稳后再切换数据
        tabs.selectedSegmentIndex = pageIndex(of: kind)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard scrollView === pager, !decelerate, let kind = currentPageKind() else { return }
        select(kind)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === pager, let kind = currentPageKind() else { return }
        select(kind)
    }

    private func currentPageKind() -> UserConnectionKind? {
        guard pager.bounds.width > 0 else { return nil }
        let index = Int((pager.contentOffset.x / pager.bounds.width).rounded())
        let kinds = UserConnectionKind.allCases
        return kinds.indices.contains(index) ? kinds[index] : nil
    }
}
