import UIKit

/// 地球页：上面是点阵地球，每个机房城市（认不出城市时按国家）一个状态点，允许定位时从“你”向各点拉弧线；
/// 下面按国家列出服务器，点开看这个国家的机器，再点进详情。范围与列表页一致，只看顶部轮播当前选中的探针。
final class ProbeGlobeViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private enum Row {
        case country(ProbeCountryGroup)
        case server(ProbeListEntry)
    }

    private let viewModel: ProbeMonitorViewModel
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let globeView = ProbeGlobeView()
    private let header = UIView()
    private var groups: [ProbeCountryGroup] = []
    private var rows: [Row] = []
    private var expandedID: String?
    private let directory: ProbeDatacenterDirectory
    private let locator: ProbeLocating
    let locateButton = UIButton(type: .system)
    private var isLocating = false
    /// 本次进入页面是否已自动定位过，避免每次刷新都重新定位。
    private var didAutoLocate = false

    init(viewModel: ProbeMonitorViewModel, locator: ProbeLocating = ProbeLocationProvider.shared,
         directory: ProbeDatacenterDirectory = .builtin) {
        self.viewModel = viewModel
        self.locator = locator
        self.directory = directory
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ProbeStyle.background
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.accessibilityIdentifier = "probe-globe-list"
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        globeView.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(globeView)
        NSLayoutConstraint.activate([
            globeView.topAnchor.constraint(equalTo: header.topAnchor),
            globeView.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            globeView.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            globeView.trailingAnchor.constraint(equalTo: header.trailingAnchor),
        ])
        globeView.onSelect = { [weak self] code in self?.expand(code, scroll: true) }
        configureLocateButton()
        locator.onAuthorizationChange = { [weak self] in self?.authorizationDidChange() }
        if let coordinate = locator.lastCoordinate, locator.authorization == .authorized {
            globeView.setUserLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        }

        NotificationCenter.default.addObserver(self, selector: #selector(viewModelDidUpdate), name: ProbeMonitorViewModel.didUpdateNotification, object: viewModel)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        reload()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 地球区域接近正方形，宽屏上封顶，免得把列表挤到屏幕外。
        let width = tableView.bounds.width
        let height = min(width, 440) * 0.92
        if tableView.tableHeaderView == nil || header.frame.size != CGSize(width: width, height: height) {
            header.frame = CGRect(x: 0, y: 0, width: width, height: height)
            tableView.tableHeaderView = header
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        globeView.setActive(true)
        viewModel.startAutoRefresh()
        autoLocateIfNeeded()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        globeView.setActive(false)
        viewModel.stopAutoRefresh()
        didAutoLocate = false
    }

    // MARK: - 数据

    @objc private func viewModelDidUpdate() { reload() }

    @objc private func appDidEnterBackground() { globeView.setActive(false) }

    @objc private func appWillEnterForeground() {
        if viewIfLoaded?.window != nil { globeView.setActive(true) }
    }

    private func reload() {
        title = viewModel.selectedInstance?.name ?? "地球"
        groups = ProbeCountryGroup.groups(from: viewModel.visibleEntries, directory: directory)
        if let expandedID, !groups.contains(where: { $0.id == expandedID }) { self.expandedID = nil }
        rebuildRows()
        tableView.reloadData()
        globeView.setMarkers(makeMarkers())
        tableView.backgroundView = groups.isEmpty ? makeEmptyView() : nil
    }

    /// 同一城市的机器合成一个点；只知道国家的机器合成国家中心那个点。
    private func makeMarkers() -> [ProbeGlobeView.Marker] {
        var buckets: [String: (country: String, coordinate: (latitude: Double, longitude: Double), entries: [ProbeListEntry])] = [:]
        var order: [String] = []
        for group in groups {
            guard let country = group.code else { continue }
            for entry in group.entries {
                let location = directory.locate(entry)
                guard let coordinate = location.coordinate ?? ProbeGeo.coordinate(for: country) else { continue }
                let id = location.city.map { "city:\($0.city)" } ?? "country:\(country)"
                if buckets[id] == nil {
                    buckets[id] = (country, coordinate, [])
                    order.append(id)
                }
                buckets[id]?.entries.append(entry)
            }
        }
        return order.compactMap { id in
            guard let bucket = buckets[id] else { return nil }
            let health = bucket.entries.map(ProbeCountryGroup.Health.init).min() ?? .unknown
            return ProbeGlobeView.Marker(id: id, country: bucket.country, latitude: bucket.coordinate.latitude,
                                         longitude: bucket.coordinate.longitude, count: bucket.entries.count, health: health)
        }
    }

    private func rebuildRows() {
        rows = groups.flatMap { group -> [Row] in
            guard group.id == expandedID else { return [.country(group)] }
            return [.country(group)] + group.entries.map { .server($0) }
        }
    }

    /// 展开一个国家（同时只展开一个）；从地球点进来时把这一行滚到可见处。
    // MARK: - 定位

    private enum LocateState: Equatable {
        case none, locating, located, denied

        var symbol: String {
            switch self {
            case .none, .locating: return "location"
            case .located: return "location.fill"
            case .denied: return "location.slash"
            }
        }

        var accessibilityValue: String {
            switch self {
            case .none: return "未定位"
            case .locating: return "定位中"
            case .located: return "已定位"
            case .denied: return "定位权限已关闭"
            }
        }
    }

    private var locateState: LocateState {
        if locator.authorization == .denied { return .denied }
        if isLocating { return .locating }
        return locator.authorization == .authorized && locator.lastCoordinate != nil ? .located : .none
    }

    private func configureLocateButton() {
        locateButton.accessibilityIdentifier = "probe-globe-locate"
        locateButton.accessibilityLabel = "定位"
        locateButton.addAction(UIAction { [weak self] _ in self?.locateTapped() }, for: .touchUpInside)
        locateButton.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(locateButton)
        NSLayoutConstraint.activate([
            locateButton.trailingAnchor.constraint(equalTo: header.layoutMarginsGuide.trailingAnchor),
            locateButton.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -8),
            locateButton.widthAnchor.constraint(equalToConstant: 40),
            locateButton.heightAnchor.constraint(equalToConstant: 40),
        ])
        updateLocateButton()
    }

    private func updateLocateButton() {
        let state = locateState
        var config: UIButton.Configuration
        if #available(iOS 26.0, *) {
            config = .glass()
        } else {
            config = .gray()
        }
        config.cornerStyle = .capsule
        config.baseForegroundColor = .label
        config.image = UIImage(systemName: state.symbol)
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        config.showsActivityIndicator = state == .locating
        locateButton.configuration = config
        locateButton.accessibilityValue = state.accessibilityValue
    }

    /// 第一次进地球页时请求授权；已授权时每次进入都自动定位一次。被拒绝时不再打扰。
    private func autoLocateIfNeeded() {
        guard !didAutoLocate else { return }
        didAutoLocate = true
        switch locator.authorization {
        case .notDetermined: locator.requestAuthorization()
        case .authorized: locate(focus: false)
        case .denied: globeView.clearUserLocation()
        }
        updateLocateButton()
    }

    func locateTapped() {
        switch locator.authorization {
        case .notDetermined: locator.requestAuthorization()
        case .authorized: locate(focus: true)
        case .denied: presentSettingsPrompt()
        }
        updateLocateButton()
    }

    private func authorizationDidChange() {
        switch locator.authorization {
        // 授权后（包括从系统设置回来）在页面可见时立刻定位。
        case .authorized where viewIfLoaded?.window != nil: locate(focus: true)
        case .denied: globeView.clearUserLocation()
        default: break
        }
        updateLocateButton()
    }

    private func locate(focus: Bool) {
        guard !isLocating else { return }
        isLocating = true
        updateLocateButton()
        locator.requestLocation { [weak self] result in
            guard let self else { return }
            isLocating = false
            switch result {
            case .success(let coordinate):
                globeView.setUserLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                if focus { globeView.focusOnUser() }
            case .failure:
                if focus { BottomToast.show("定位失败，请稍后重试", style: .failure, in: view) }
            }
            updateLocateButton()
        }
    }

    private func presentSettingsPrompt() {
        let alert = UIAlertController(title: "定位权限已关闭", message: "开启后可显示你到各服务器的连线。位置只在本机使用。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "去设置", style: .default) { _ in
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        })
        present(alert, animated: true)
    }

    // MARK: - 展开

    private func expand(_ id: String, scroll: Bool) {
        expandedID = id
        rebuildRows()
        tableView.reloadData()
        guard scroll, let index = rows.firstIndex(where: { if case .country(let group) = $0 { return group.id == id } else { return false } }) else { return }
        tableView.scrollToRow(at: IndexPath(row: index, section: 0), at: .top, animated: true)
    }

    // MARK: - UITableViewDataSource

    func numberOfSections(in tableView: UITableView) -> Int { groups.isEmpty ? 0 : 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "\(groups.filter { $0.code != nil }.count) 个国家和地区 · \(viewModel.visibleEntries.count) 台"
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        switch rows[indexPath.row] {
        case .country(let group): configureCountry(cell, group)
        case .server(let entry): configureServer(cell, entry)
        }
        return cell
    }

    private func configureCountry(_ cell: UITableViewCell, _ group: ProbeCountryGroup) {
        var content = UIListContentConfiguration.valueCell()
        content.image = UIImage(systemName: "circle.fill")
        content.imageProperties.tintColor = Self.color(for: group.health)
        content.imageProperties.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 9)
        content.text = group.code.map { "\(ProbeGeo.flag(for: $0)) \(ProbeGeo.displayName(for: $0))" } ?? "未知地区"
        var detail = "\(group.entries.count) 台"
        if group.offlineCount > 0 { detail += " · \(group.offlineCount) 台离线" }
        if group.alertCount > 0 { detail += " · \(group.alertCount) 台告警" }
        content.secondaryText = detail
        content.secondaryTextProperties.color = group.offlineCount > 0 ? .systemRed : group.alertCount > 0 ? .systemOrange : .secondaryLabel
        content.secondaryTextProperties.font = .monospacedDigitSystemFont(ofSize: 15, weight: .regular)
        cell.contentConfiguration = content
        let chevron = UIImageView(image: UIImage(systemName: group.id == expandedID ? "chevron.up" : "chevron.down"))
        chevron.tintColor = .tertiaryLabel
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        cell.accessoryView = chevron
        cell.accessoryType = .none
        cell.accessibilityIdentifier = "probe-globe-country-\(group.id)"
    }

    private func configureServer(_ cell: UITableViewCell, _ entry: ProbeListEntry) {
        var content = UIListContentConfiguration.valueCell()
        content.text = entry.displayName
        content.textProperties.font = .systemFont(ofSize: 15)
        let health = ProbeCountryGroup.Health(entry)
        switch health {
        case .offline: content.secondaryText = "离线"
        case .unknown: content.secondaryText = "暂无数据"
        case .alert: content.secondaryText = "告警 · \(ProbeFormat.percent(entry.alertPercent, decimals: 0))%"
        case .online:
            let cpu = entry.server.status?.metrics.cpuPercent
            content.secondaryText = cpu.map { "CPU \(ProbeFormat.percent($0, decimals: 0))%" } ?? "在线"
        }
        // 认出了机房城市就写在状态前面，例如“洛杉矶 · CPU 3%”。
        if let city = directory.locate(entry).city, let status = content.secondaryText {
            content.secondaryText = "\(city.city) · \(status)"
        }
        content.secondaryTextProperties.color = health == .online ? .secondaryLabel : Self.color(for: health)
        content.secondaryTextProperties.font = .monospacedDigitSystemFont(ofSize: 15, weight: .regular)
        // 缩进到国家名下面，看出层级。
        content.directionalLayoutMargins.leading = 40
        cell.contentConfiguration = content
        cell.accessoryView = nil
        cell.accessoryType = .disclosureIndicator
        cell.accessibilityIdentifier = "probe-globe-server-\(entry.displayName)"
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch rows[indexPath.row] {
        case .country(let group):
            if group.id == expandedID {
                expandedID = nil
                rebuildRows()
                tableView.reloadData()
            } else {
                expand(group.id, scroll: false)
                if let code = group.code { globeView.focus(country: code) }
            }
        case .server(let entry):
            navigationController?.pushViewController(ProbeServerDetailViewController(entryID: entry.id, viewModel: viewModel), animated: true)
        }
    }

    // MARK: - 辅助

    private static func color(for health: ProbeCountryGroup.Health) -> UIColor {
        switch health {
        case .online: return .systemGreen
        case .alert: return .systemOrange
        case .offline: return .systemRed
        case .unknown: return .systemGray
        }
    }

    private func makeEmptyView() -> UIView {
        let label = ProbeStyle.label(.systemFont(ofSize: 15), .secondaryLabel, lines: 0)
        label.text = "这个探针下还没有服务器"
        label.textAlignment = .center
        return label
    }
}
