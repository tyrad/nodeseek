import UIKit

/// 探针列表：一个探针一张汇总卡，下面只显示当前卡片的服务器。
final class ProbeMonitorViewController: UIViewController {
    let viewModel: ProbeMonitorViewModel
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let heroCarousel = ProbeHeroCarouselView()
    private let chipsView = ProbeFilterChipsView()
    private let errorLabel = ProbeStyle.label(.systemFont(ofSize: 12, weight: .medium), .systemRed, lines: 0)
    private let headerContainer = UIView()
    private let searchBar = ProbeSearchBarView()
    private lazy var emptyView = makeEmptyView()
    private var relativeTimer: Timer?

    init(viewModel: ProbeMonitorViewModel? = nil) {
        self.viewModel = viewModel ?? ProbeMonitorViewModel()
        super.init(nibName: nil, bundle: nil)
        title = "探针"
        hidesBottomBarWhenPushed = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ProbeStyle.background
        configureTable()
        configureHeader()
        configureSearch()
        viewModel.onChange = { [weak self] in self?.render() }
        viewModel.onTrendChange = { [weak self] id in self?.reloadVisibleRow(entryID: id) }
        NotificationCenter.default.addObserver(self, selector: #selector(instancesDidChange), name: ProbeInstanceStore.didChangeNotification, object: viewModel.store)
        render()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.startAutoRefresh()
        // 相对时间（“3 分钟前”）随时间变化，不依赖网络刷新。
        relativeTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.renderHeader() }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        viewModel.stopAutoRefresh()
        relativeTimer?.invalidate()
        relativeTimer = nil
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 表头不会继承列表的边距，手动对齐到下面卡片的左右边缘。
        let margins = tableView.layoutMargins
        if headerContainer.layoutMargins.left != margins.left || headerContainer.layoutMargins.right != margins.right {
            headerContainer.layoutMargins = UIEdgeInsets(top: 0, left: margins.left, bottom: 0, right: margins.right)
        }
        heroCarousel.setContainerWidth(tableView.bounds.width, margin: headerContainer.layoutMargins.left)
        sizeHeaderToFit()
        // 列表底部让出搜索框的位置。安全区由系统自动加，这里只补搜索框高出的部分。
        let bottom = searchBar.isHidden ? 0 : max(view.bounds.maxY - searchBar.frame.minY + 8 - view.safeAreaInsets.bottom, 0)
        if tableView.contentInset.bottom != bottom {
            tableView.contentInset.bottom = bottom
            tableView.verticalScrollIndicatorInsets.bottom = bottom
        }
    }

    // MARK: - 布局

    private func configureTable() {
        tableView.backgroundColor = ProbeStyle.background
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.sectionHeaderTopPadding = 0
        tableView.keyboardDismissMode = .onDrag
        tableView.register(ProbeServerCardCell.self, forCellReuseIdentifier: ProbeServerCardCell.reuseIdentifier)
        tableView.register(ProbeServerCompactCell.self, forCellReuseIdentifier: ProbeServerCompactCell.reuseIdentifier)
        tableView.register(ProbeSectionHeaderView.self, forHeaderFooterViewReuseIdentifier: ProbeSectionHeaderView.reuseIdentifier)
        tableView.refreshControl = UIRefreshControl(frame: .zero, primaryAction: UIAction { [weak self] _ in
            Task { [weak self] in
                await self?.viewModel.refresh(reloadNodes: true)
                self?.tableView.refreshControl?.endRefreshing()
            }
        })
        tableView.accessibilityIdentifier = "probe-monitor-table"
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func configureHeader() {
        heroCarousel.onSelect = { [weak self] id in
            self?.viewModel.selectInstance(id)
        }
        heroCarousel.onOpenEntry = { [weak self] id in
            guard let self, let entry = viewModel.entry(id: id) else { return }
            showDetail(entry)
        }
        heroCarousel.manageMenu = { [weak self] id in
            guard let self else { return nil }
            let actions = self.manageActions(for: id, current: true)
            return actions.isEmpty ? nil : UIMenu(children: actions)
        }
        chipsView.onSelect = { [weak self] filter in
            guard let self else { return }
            viewModel.filter = viewModel.filter == filter ? .all : filter
            render()
        }
        chipsView.onSort = { [weak self] sort in
            self?.viewModel.sort = sort
            self?.render()
        }
        // 轮播占满整行，两侧卡片才能露出到屏幕边缘；其余内容按页面边距对齐。
        let stack = UIStackView(arrangedSubviews: [errorLabel, chipsView])
        stack.axis = .vertical
        stack.spacing = 12
        [heroCarousel, stack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            headerContainer.addSubview($0)
        }
        NSLayoutConstraint.activate([
            heroCarousel.topAnchor.constraint(equalTo: headerContainer.topAnchor, constant: 8),
            heroCarousel.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor),
            heroCarousel.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor),
            stack.topAnchor.constraint(equalTo: heroCarousel.bottomAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: headerContainer.bottomAnchor, constant: -4),
            stack.leadingAnchor.constraint(equalTo: headerContainer.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: headerContainer.layoutMarginsGuide.trailingAnchor),
        ])
    }

    private func configureSearch() {
        searchBar.onChange = { [weak self] text in
            guard let self, text != viewModel.query else { return }
            viewModel.query = text
            renderHeader()
            tableView.reloadData()
        }
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchBar)
        // 跟随键盘：键盘收起时贴在安全区底部，弹出时停在键盘上方。
        NSLayoutConstraint.activate([
            searchBar.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            searchBar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -8),
        ])
    }

    private func sizeHeaderToFit() {
        guard tableView.tableHeaderView === headerContainer else { return }
        let width = tableView.bounds.width
        let height = headerContainer.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel
        ).height
        if headerContainer.frame.height != height || headerContainer.frame.width != width {
            headerContainer.frame = CGRect(x: 0, y: 0, width: width, height: height)
            tableView.tableHeaderView = headerContainer
        }
    }

    // MARK: - 渲染

    private func render() {
        let hasInstances = !viewModel.instances.isEmpty
        tableView.backgroundView = hasInstances ? nil : emptyView
        tableView.tableHeaderView = hasInstances ? headerContainer : nil
        searchBar.isHidden = !hasInstances
        configureNavigationItems()
        renderHeader()
        tableView.reloadData()
        view.setNeedsLayout()
    }

    private func renderHeader() {
        heroCarousel.configure(viewModel.cards)
        chipsView.configure(selected: viewModel.filter, counts: viewModel.filterCounts, sort: viewModel.sort)
        errorLabel.text = viewModel.selectedErrorMessage
        errorLabel.isHidden = viewModel.selectedErrorMessage == nil
        let isEmptyResult = viewModel.sections.isEmpty && !viewModel.visibleEntries.isEmpty
        tableView.backgroundView = viewModel.instances.isEmpty ? emptyView : isEmptyResult ? makeNoResultView() : nil
    }

    private func configureNavigationItems() {
        guard !viewModel.instances.isEmpty else {
            navigationItem.rightBarButtonItems = []
            return
        }
        let compact = viewModel.usesCompactList
        let density = UIMenu(options: .displayInline, children: [
            UIAction(title: "卡片", image: UIImage(systemName: "rectangle.grid.1x2"), state: compact ? .off : .on) { [weak self] _ in self?.viewModel.setCompact(false) },
            UIAction(title: "紧凑", image: UIImage(systemName: "list.bullet"), state: compact ? .on : .off) { [weak self] _ in self?.viewModel.setCompact(true) },
        ])
        let current = viewModel.refreshInterval
        let intervals = ProbeInstanceStore.refreshIntervalOptions.map { seconds in
            UIAction(title: "\(Int(seconds)) 秒", state: seconds == current ? .on : .off) { [weak self] _ in
                self?.viewModel.setRefreshInterval(seconds)
            }
        }
        let refresh = UIMenu(title: "刷新频率", subtitle: "\(Int(current)) 秒", image: UIImage(systemName: "arrow.clockwise"), children: intervals)
        // 排序在筛选胶囊右侧。添加、编辑、删除放在最上面，连接失败、没有服务器时也能用。
        let addProbe = UIAction(title: "添加探针", image: UIImage(systemName: "plus")) { [weak self] _ in
            self?.presentEditor(for: nil)
        }
        var probeActions = [addProbe]
        if let id = viewModel.selectedInstance?.id {
            probeActions.append(contentsOf: manageActions(for: id, current: true))
        }
        let sections: [UIMenuElement] = [
            UIMenu(options: .displayInline, children: probeActions),
            density,
            UIMenu(options: .displayInline, children: [refresh]),
        ]
        let menu = UIMenu(children: sections)
        let more = UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), menu: menu)
        more.accessibilityLabel = "更多"
        more.accessibilityIdentifier = "probe-more-menu"
        let globe = UIBarButtonItem(image: UIImage(systemName: "globe.asia.australia"), primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            navigationController?.pushViewController(ProbeGlobeViewController(viewModel: viewModel), animated: true)
        })
        globe.accessibilityLabel = "地球"
        globe.accessibilityIdentifier = "probe-globe-button"
        // 从右往左依次是：更多、地球。添加探针在「⋯」里。
        navigationItem.rightBarButtonItems = [more, globe]
    }

    private func reloadVisibleRow(entryID: String) {
        guard let indexPath = tableView.indexPathsForVisibleRows?.first(where: { visibleEntry(at: $0)?.id == entryID }) else { return }
        if let cell = tableView.cellForRow(at: indexPath) as? ProbeServerCardCell, let entry = visibleEntry(at: indexPath) {
            cell.configure(ProbeRowContent(entry: entry, trend: viewModel.trends[entry.id]))
        }
    }

    private func visibleEntry(at indexPath: IndexPath) -> ProbeListEntry? {
        guard indexPath.section < viewModel.sections.count else { return nil }
        let section = viewModel.sections[indexPath.section]
        guard !isCollapsed(section), indexPath.row < section.entries.count else { return nil }
        return section.entries[indexPath.row]
    }

    private func isCollapsed(_ section: ProbeListSection) -> Bool {
        viewModel.collapsedSectionIDs.contains(section.id) && viewModel.sections.count > 1
    }

    // MARK: - 导航

    private func presentEditor(for instanceID: UUID?) {
        let editor = ProbeInstanceEditorViewController(instance: instanceID.flatMap(viewModel.instance(id:)), store: viewModel.store)
        present(UINavigationController(rootViewController: editor), animated: true)
    }

    /// 小组件点按：进探针列表，带服务器时再进它的详情。已经停在探针页时复用它，避免每点一次就多压一层。
    static func show(
        _ link: ProbeWidgetLink,
        in navigationController: UINavigationController,
        animated: Bool = true,
        makeMonitor: () -> ProbeMonitorViewController = { ProbeMonitorViewController() }
    ) {
        let monitor: ProbeMonitorViewController
        if let existing = navigationController.viewControllers.last(where: { $0 is ProbeMonitorViewController }) as? ProbeMonitorViewController {
            navigationController.popToViewController(existing, animated: false)
            monitor = existing
        } else {
            monitor = makeMonitor()
            navigationController.pushViewController(monitor, animated: animated && link.nodeID == nil)
        }
        if let instanceID = link.instanceID, let nodeID = link.nodeID {
            let detail = ProbeServerDetailViewController(entryID: "\(instanceID.uuidString)/\(nodeID)", viewModel: monitor.viewModel)
            navigationController.pushViewController(detail, animated: animated)
        }
    }

    /// 当前卡片用「当前探针」，分组标题用短标题。两组都是编辑和删除。
    private func manageActions(for id: UUID, current: Bool) -> [UIAction] {
        guard viewModel.instance(id: id) != nil else { return [] }
        let edit = UIAction(title: current ? "编辑当前探针" : "编辑探针", image: UIImage(systemName: "slider.horizontal.3")) { [weak self] _ in
            self?.presentEditor(for: id)
        }
        let delete = UIAction(title: current ? "删除当前探针" : "删除探针", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
            self?.confirmDelete(id: id)
        }
        return [edit, delete]
    }

    private func confirmDelete(id: UUID) {
        guard let instance = viewModel.instance(id: id) else { return }
        let alert = UIAlertController(title: "删除“\(instance.name)”？", message: "只删除本机的配置和缓存，不影响面板。", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "删除探针", style: .destructive) { [weak self] _ in
            guard let self else { return }
            Task { await self.viewModel.deleteInstance(id: id) }
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        present(alert, animated: true)
    }

    private func showDetail(_ entry: ProbeListEntry) {
        navigationController?.pushViewController(ProbeServerDetailViewController(entryID: entry.id, viewModel: viewModel), animated: true)
    }

    @objc private func instancesDidChange() {
        viewModel.reloadInstances()
        render()
        Task { await viewModel.refresh(reloadNodes: true) }
    }

    // MARK: - 空状态

    private func makeEmptyView() -> UIView {
        let icon = UIImageView(image: UIImage(systemName: "server.rack"))
        icon.tintColor = .secondaryLabel
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 40, weight: .light)
        let title = ProbeStyle.label(.systemFont(ofSize: 17, weight: .semibold))
        title.text = "还没有添加探针"
        let body = ProbeStyle.label(.systemFont(ofSize: 14), .secondaryLabel, lines: 0)
        body.text = "填入 Komari 或极简探针的面板地址，即可查看服务器的在线状态和负载。只读取游客可见的数据，不需要登录。"
        body.textAlignment = .center
        var config = UIButton.Configuration.filled()
        config.title = "添加探针"
        config.cornerStyle = .capsule
        config.baseBackgroundColor = .label
        config.baseForegroundColor = .systemBackground
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 22, bottom: 10, trailing: 22)
        let button = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in self?.presentEditor(for: nil) })
        button.accessibilityIdentifier = "probe-empty-add"
        let stack = UIStackView(arrangedSubviews: [icon, title, body, button])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        stack.setCustomSpacing(20, after: body)
        return centered(stack)
    }

    private func makeNoResultView() -> UIView {
        let label = ProbeStyle.label(.systemFont(ofSize: 15), .secondaryLabel)
        label.text = viewModel.query.isEmpty ? "没有\(viewModel.filter.title)的服务器" : "没有匹配的服务器"
        let container = UIView()
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: 80),
        ])
        return container
    }

    private func centered(_ content: UIView) -> UIView {
        let container = UIView()
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -40),
            content.leadingAnchor.constraint(equalTo: container.layoutMarginsGuide.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: container.layoutMarginsGuide.trailingAnchor, constant: -24),
        ])
        return container
    }
}

extension ProbeMonitorViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        viewModel.sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let section = viewModel.sections[section]
        return isCollapsed(section) ? 0 : section.entries.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let entry = viewModel.sections[indexPath.section].entries[indexPath.row]
        let content = ProbeRowContent(entry: entry, trend: viewModel.trends[entry.id])
        if viewModel.usesCompactList {
            let cell = tableView.dequeueReusableCell(withIdentifier: ProbeServerCompactCell.reuseIdentifier, for: indexPath) as! ProbeServerCompactCell
            cell.configure(content)
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: ProbeServerCardCell.reuseIdentifier, for: indexPath) as! ProbeServerCardCell
        cell.configure(content)
        return cell
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        // 只有卡片模式显示趋势线，紧凑模式不请求历史。
        guard !viewModel.usesCompactList, let entry = visibleEntry(at: indexPath), entry.server.availability != .unknown else { return }
        viewModel.loadTrend(for: entry)
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let header = tableView.dequeueReusableHeaderFooterView(withIdentifier: ProbeSectionHeaderView.reuseIdentifier) as! ProbeSectionHeaderView
        let model = viewModel.sections[section]
        let collapsible = viewModel.sections.count > 1
        var menu: UIMenu?
        if let instanceID = viewModel.instanceID(forSection: model), viewModel.filter == .all, viewModel.query.isEmpty {
            let actions = manageActions(for: instanceID, current: false)
            if !actions.isEmpty { menu = UIMenu(children: actions) }
        }
        header.configure(section: model, collapsed: isCollapsed(model), collapsible: collapsible, menu: menu)
        header.onToggle = { [weak self] in
            guard collapsible else { return }
            self?.viewModel.toggleSection(model.id)
        }
        return header
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        40
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if let entry = visibleEntry(at: indexPath) { showDetail(entry) }
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard let entry = visibleEntry(at: indexPath) else { return nil }
        return UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            UIMenu(children: [
                UIAction(title: "重命名", image: UIImage(systemName: "pencil")) { _ in self?.promptAlias(for: entry) },
                UIAction(title: "隐藏这台服务器", image: UIImage(systemName: "eye.slash")) { _ in self?.viewModel.hide(entry) },
            ])
        })
    }

    func promptAlias(for entry: ProbeListEntry) {
        ProbeAliasPrompt.present(on: self, entry: entry) { [weak self] alias in
            self?.viewModel.setAlias(alias, for: entry)
        }
    }
}

/// 重命名弹窗：只改本机显示的名称，留空恢复面板名称。
enum ProbeAliasPrompt {
    @MainActor
    static func present(on viewController: UIViewController, entry: ProbeListEntry, completion: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: "重命名", message: "只在本机显示，不会修改面板上的名称。留空则恢复为“\(entry.server.node.name)”。", preferredStyle: .alert)
        alert.addTextField { field in
            field.text = entry.displayName
            field.placeholder = entry.server.node.name
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { _ in completion(alert.textFields?.first?.text) })
        viewController.present(alert, animated: true)
    }
}
