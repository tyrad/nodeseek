import UIKit

/// 单台服务器详情：CPU 历史曲线、内存 / 硬盘 / 网络 / 负载四宫格、运行信息。
final class ProbeServerDetailViewController: UIViewController, UIGestureRecognizerDelegate {
    private enum Range: Int, CaseIterable {
        case hour, sixHours, day

        var hours: Int { [1, 6, 24][rawValue] }
        var title: String { ["1H", "6H", "24H"][rawValue] }
    }

    private let entryID: String
    private let viewModel: ProbeMonitorViewModel
    private var range = Range.hour
    private var historyTask: Task<Void, Never>?

    private let scrollView = UIScrollView()
    private let titleLabel = ProbeStyle.label(.systemFont(ofSize: 28, weight: .heavy), lines: 2)
    private let statusView = ProbeStatusView()
    private let metaLabel = ProbeStyle.label(ProbeStyle.mono(11), .secondaryLabel, lines: 0)
    private let staleLabel = ProbeStyle.label(.systemFont(ofSize: 12, weight: .medium), .secondaryLabel, lines: 0)
    private let cpuValueLabel = UILabel()
    private let cpuCaptionLabel = ProbeStyle.label(ProbeStyle.mono(10.5, .medium), .secondaryLabel)
    /// 当前曲线的采样，和 chart.values 一一对应。
    private var chartSamples: [(date: Date, value: Double)] = []
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private var hideHighlightWork: DispatchWorkItem?
    private let chart = ProbeSparklineView()
    private let chartStartLabel = ProbeStyle.label(ProbeStyle.mono(10), .tertiaryLabel)
    private let chartEndLabel = ProbeStyle.label(ProbeStyle.mono(10), .tertiaryLabel)
    private let chartScaleLabel = ProbeStyle.label(ProbeStyle.mono(10), .tertiaryLabel)
    private let chartMessageLabel = ProbeStyle.label(.systemFont(ofSize: 12), .secondaryLabel)
    private let rangeControl = UISegmentedControl(items: Range.allCases.map(\.title))
    private let memoryTile = ProbeDetailTile(title: "内存", metric: .memory)
    private let diskTile = ProbeDetailTile(title: "硬盘", metric: .disk)
    private let networkTile = ProbeDetailTile(title: "网络", metric: .network)
    private let loadTile = ProbeDetailTile(title: "负载", metric: .cpu)
    private let factsStack = UIStackView()
    private let footerLabel = ProbeStyle.label(ProbeStyle.mono(10.5), .tertiaryLabel, lines: 0)

    init(entryID: String, viewModel: ProbeMonitorViewModel) {
        self.entryID = entryID
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
        navigationItem.largeTitleDisplayMode = .never
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ProbeStyle.background
        layout()
        NotificationCenter.default.addObserver(self, selector: #selector(viewModelDidUpdate), name: ProbeMonitorViewModel.didUpdateNotification, object: viewModel)
        render()
        loadHistory()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewModel.startAutoRefresh()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        viewModel.stopAutoRefresh()
    }

    private var entry: ProbeListEntry? { viewModel.entry(id: entryID) }

    // MARK: - 布局

    private func layout() {
        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let statusRow = UIStackView(arrangedSubviews: [statusView, UIView()])
        let header = UIStackView(arrangedSubviews: [titleLabel, statusRow, metaLabel, staleLabel])
        header.axis = .vertical
        header.spacing = 6

        rangeControl.selectedSegmentIndex = range.rawValue
        rangeControl.addAction(UIAction { [weak self] _ in
            guard let self, let range = Range(rawValue: rangeControl.selectedSegmentIndex) else { return }
            self.range = range
            loadHistory()
        }, for: .valueChanged)
        rangeControl.setContentHuggingPriority(.required, for: .horizontal)
        cpuCaptionLabel.text = "CPU"
        let cpuColumn = UIStackView(arrangedSubviews: [cpuCaptionLabel, cpuValueLabel])
        cpuColumn.axis = .vertical
        let chartTop = UIStackView(arrangedSubviews: [cpuColumn, UIView(), rangeControl])
        chartTop.alignment = .top
        chart.lineWidth = 2
        configureChartTouches()
        chartScaleLabel.textAlignment = .center
        let axis = UIStackView(arrangedSubviews: [chartStartLabel, chartScaleLabel, chartEndLabel])
        axis.distribution = .equalSpacing
        let chartStack = UIStackView(arrangedSubviews: [chartTop, chart, axis])
        chartStack.axis = .vertical
        chartStack.spacing = 10
        chartMessageLabel.textAlignment = .center
        let chartCard = Self.card(chartStack)
        chartMessageLabel.translatesAutoresizingMaskIntoConstraints = false
        chartCard.addSubview(chartMessageLabel)

        let topTiles = UIStackView(arrangedSubviews: [memoryTile, diskTile])
        let bottomTiles = UIStackView(arrangedSubviews: [networkTile, loadTile])
        [topTiles, bottomTiles].forEach {
            $0.spacing = 10
            $0.distribution = .fillEqually
        }
        factsStack.distribution = .fillEqually
        let column = UIStackView(arrangedSubviews: [header, chartCard, topTiles, bottomTiles, Self.card(factsStack), footerLabel])
        column.axis = .vertical
        column.spacing = 10
        column.setCustomSpacing(18, after: header)
        column.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(column)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            column.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
            column.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            column.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            chart.heightAnchor.constraint(equalToConstant: 132),
            chartMessageLabel.centerXAnchor.constraint(equalTo: chart.centerXAnchor),
            chartMessageLabel.centerYAnchor.constraint(equalTo: chart.centerYAnchor),
        ])
    }

    static func card(_ content: UIView) -> UIView {
        let card = UIView()
        card.backgroundColor = ProbeStyle.card
        card.layer.cornerRadius = ProbeStyle.cardRadius
        card.layer.cornerCurve = .continuous
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
        ])
        return card
    }

    // MARK: - 渲染

    @objc private func viewModelDidUpdate() {
        render()
    }

    private func render() {
        guard let entry else {
            // 服务器被隐藏或探针被删除。
            titleLabel.text = "服务器不可用"
            navigationItem.rightBarButtonItem = nil
            return
        }
        let content = ProbeRowContent(entry: entry, trend: nil)
        let node = entry.server.node
        let metrics = content.metrics
        let dimmed = content.isDimmed
        titleLabel.text = content.title
        statusView.configure(availability: content.availability, isStale: entry.isStale)
        metaLabel.text = [node.os, node.cpuCores.map { "\($0) 核" }, node.group, entry.instanceName]
            .compactMap { $0 }.joined(separator: " · ").uppercased()
        switch (content.availability, entry.isStale) {
        case (.unknown, _): staleLabel.text = "面板暂时没有这台服务器的数据，可能已离线。"
        case (.offline, _): staleLabel.text = "离线 · 以下是 \(ProbeFormat.relative(entry.server.status?.sampledAt)) 最后上报的数据"
        case (.online, true): staleLabel.text = "无法连接面板 · 以下是缓存数据"
        case (.online, false): staleLabel.text = nil
        }
        staleLabel.textColor = content.availability == .offline ? .systemRed : .secondaryLabel
        staleLabel.isHidden = staleLabel.text == nil

        let cpu = metrics?.cpuPercent
        // 手指正在看历史点时，不让自动刷新把数字换回当前值。
        if chart.highlightedIndex == nil {
            cpuValueLabel.attributedText = ProbeStyle.number(ProbeFormat.percent(cpu), unit: "%", size: 36,
                                                             color: dimmed ? .secondaryLabel : ProbeStyle.valueColor(percent: cpu))
        }
        chart.lineColor = dimmed ? .tertiaryLabel : ProbeStyle.color(for: .cpu, percent: cpu)

        memoryTile.configurePercent(metrics?.memPercent, detail: "\(ProbeFormat.bytes(metrics?.memUsed)) / \(ProbeFormat.bytes(metrics?.memTotal))", dimmed: dimmed)
        diskTile.configurePercent(metrics?.diskPercent, detail: "\(ProbeFormat.bytes(metrics?.diskUsed)) / \(ProbeFormat.bytes(metrics?.diskTotal))", dimmed: dimmed)
        let totals = metrics?.netTotalIn.flatMap { totalIn in metrics?.netTotalOut.map { "累计 ↑\(ProbeFormat.bytes($0)) ↓\(ProbeFormat.bytes(totalIn))" } }
        networkTile.configureText(
            "↓\(ProbeFormat.rate(metrics?.netInRate))", secondary: "↑\(ProbeFormat.rate(metrics?.netOutRate))/s",
            detail: totals ?? "—", dimmed: dimmed
        )
        let load = metrics?.load1.map { String(format: "%.2f", $0) } ?? "—"
        let load5 = [metrics?.load5, metrics?.load15].map { $0.map { String(format: "%.2f", $0) } ?? "—" }.joined(separator: " · ")
        // 负载按核数换算成百分比，超过核数的 70% / 90% 时变色。
        var loadPercent: Double?
        if let load1 = metrics?.load1, let cores = node.cpuCores, cores > 0 { loadPercent = load1 / Double(cores) * 100 }
        loadTile.configureText(load, secondary: nil, detail: "5 / 15 分钟 \(load5)", dimmed: dimmed,
                               color: dimmed ? .secondaryLabel : ProbeStyle.valueColor(percent: loadPercent))

        factsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let swap = metrics?.swapTotal.flatMap { $0 > 0 ? "\(ProbeFormat.bytes(metrics?.swapUsed))/\(ProbeFormat.bytes($0))" : nil } ?? "—"
        [("运行", ProbeFormat.uptime(metrics?.uptime)), ("进程", metrics?.processCount.map(String.init) ?? "—"),
         ("连接", metrics?.connectionCount.map(String.init) ?? "—"), ("交换", swap)].forEach {
            factsStack.addArrangedSubview(Self.fact($0.0, $0.1))
        }
        footerLabel.text = "数据来自 \(entry.instanceName) · 更新于 \(ProbeFormat.relative(viewModel.fetchedAt(for: entry.instanceID)))"
        configureMenu(entry)
    }

    private func configureMenu(_ entry: ProbeListEntry) {
        let menu = UIMenu(children: [
            UIAction(title: "重命名", image: UIImage(systemName: "pencil")) { [weak self] _ in
                guard let self else { return }
                ProbeAliasPrompt.present(on: self, entry: entry) { [weak self] alias in self?.viewModel.setAlias(alias, for: entry) }
            },
            UIAction(title: "隐藏这台服务器", image: UIImage(systemName: "eye.slash")) { [weak self] _ in
                self?.viewModel.hide(entry)
                self?.navigationController?.popViewController(animated: true)
            },
        ])
        if navigationItem.rightBarButtonItem == nil {
            navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), menu: menu)
            navigationItem.rightBarButtonItem?.accessibilityLabel = "更多"
        } else {
            navigationItem.rightBarButtonItem?.menu = menu
        }
    }

    private static func fact(_ title: String, _ value: String) -> UIView {
        let titleLabel = ProbeStyle.label(ProbeStyle.mono(10, .medium), .secondaryLabel)
        titleLabel.text = title
        let valueLabel = ProbeStyle.label(ProbeStyle.mono(13, .semibold))
        valueLabel.text = value
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.7
        let stack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        stack.axis = .vertical
        stack.spacing = 3
        stack.isAccessibilityElement = true
        stack.accessibilityLabel = "\(title) \(value)"
        return stack
    }

    // MARK: - 历史

    private func loadHistory() {
        guard let entry, entry.server.availability != .unknown else {
            chart.values = []
            chartMessageLabel.text = "暂无趋势数据"
            return
        }
        historyTask?.cancel()
        let range = range
        chartMessageLabel.text = "加载中…"
        historyTask = Task { [weak self] in
            guard let self else { return }
            let points: [ProbeHistoryPoint]
            do {
                points = try await viewModel.history(for: entry, hours: range.hours)
            } catch {
                guard !Task.isCancelled else { return }
                chartSamples = []
                clearHighlight()
                chart.values = []
                chartMessageLabel.text = ProbeFetchError.from(error).message
                return
            }
            guard !Task.isCancelled else { return }
            chartSamples = points.compactMap { point in point.metrics.cpuPercent.map { (point.date, $0) } }
            let values = chartSamples.map(\.value)
            clearHighlight()
            chart.cutAtEnd = entry.server.availability == .offline
            let ceiling = ProbeStyle.chartCeiling(values.max())
            chart.maximum = ceiling
            chart.values = values
            chartScaleLabel.text = values.count < 2 ? nil : "纵轴 0–\(Int(ceiling))%"
            chartMessageLabel.text = values.count < 2 ? "暂无趋势数据" : nil
            let formatter = DateFormatter()
            formatter.dateFormat = range == .day ? "MM-dd HH:mm" : "HH:mm"
            chartStartLabel.text = points.first.map { formatter.string(from: $0.date) }
            chartEndLabel.text = points.last.map { formatter.string(from: $0.date) }
            if let peak = values.max() {
                chart.accessibilityLabel = "最近 \(range.title) CPU 最高 \(ProbeFormat.percent(peak))%"
                chart.isAccessibilityElement = true
            }
        }
    }

    // MARK: - 图表触摸

    /// 横向滑动逐点查看，点一下查看单个点；竖向滑动仍交给页面滚动。
    private func configureChartTouches() {
        chart.isUserInteractionEnabled = true
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleChartPan(_:)))
        pan.delegate = self
        chart.addGestureRecognizer(pan)
        chart.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleChartTap(_:))))
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer, pan.view === chart else { return true }
        let velocity = pan.velocity(in: chart)
        return abs(velocity.x) > abs(velocity.y)
    }

    @objc private func handleChartPan(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            hideHighlightWork?.cancel()
            selectionFeedback.prepare()
            highlightSample(atX: pan.location(in: chart).x)
        case .changed:
            highlightSample(atX: pan.location(in: chart).x)
        default:
            clearHighlight()
        }
    }

    @objc private func handleChartTap(_ tap: UITapGestureRecognizer) {
        highlightSample(atX: tap.location(in: chart).x)
        // 点按查看的点停留一会儿再自动收起。
        hideHighlightWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.clearHighlight() }
        hideHighlightWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    private func highlightSample(atX x: CGFloat) {
        guard chartSamples.count >= 2, let index = chart.nearestIndex(toX: x), chartSamples.indices.contains(index) else { return }
        guard index != chart.highlightedIndex else { return }
        let changedFromPoint = chart.highlightedIndex != nil
        chart.highlightedIndex = index
        if changedFromPoint { selectionFeedback.selectionChanged() }
        let sample = chartSamples[index]
        let formatter = DateFormatter()
        formatter.dateFormat = range == .day ? "MM-dd HH:mm" : "HH:mm"
        cpuCaptionLabel.text = "CPU · \(formatter.string(from: sample.date))"
        cpuValueLabel.attributedText = ProbeStyle.number(ProbeFormat.percent(sample.value), unit: "%", size: 36,
                                                         color: ProbeStyle.valueColor(percent: sample.value))
    }

    private func clearHighlight() {
        hideHighlightWork?.cancel()
        hideHighlightWork = nil
        guard chart.highlightedIndex != nil else { return }
        chart.highlightedIndex = nil
        cpuCaptionLabel.text = "CPU"
        render()
    }
}

/// 详情页四宫格的单个格子。
final class ProbeDetailTile: UIView {
    private let titleLabel = ProbeStyle.label(ProbeStyle.mono(10.5, .medium), .secondaryLabel)
    private let valueLabel = UILabel()
    private let meter = ProbeSegmentMeterView()
    private let detailLabel = ProbeStyle.label(ProbeStyle.mono(10.5), .secondaryLabel)
    private let metric: ProbeStyle.Metric

    init(title: String, metric: ProbeStyle.Metric) {
        self.metric = metric
        super.init(frame: .zero)
        backgroundColor = ProbeStyle.card
        layer.cornerRadius = ProbeStyle.cardRadius
        layer.cornerCurve = .continuous
        titleLabel.text = title
        meter.metric = metric
        meter.segments = 16
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.6
        detailLabel.adjustsFontSizeToFitWidth = true
        detailLabel.minimumScaleFactor = 0.7
        let stack = UIStackView(arrangedSubviews: [titleLabel, valueLabel, meter, detailLabel])
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            meter.heightAnchor.constraint(equalToConstant: 6),
        ])
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configurePercent(_ percent: Double?, detail: String, dimmed: Bool) {
        valueLabel.attributedText = ProbeStyle.number(ProbeFormat.percent(percent), unit: "%", size: 26,
                                                      color: dimmed ? .secondaryLabel : ProbeStyle.valueColor(percent: percent))
        meter.isHidden = false
        meter.percent = percent
        meter.isDimmed = dimmed
        detailLabel.text = detail
        accessibilityLabel = "\(titleLabel.text ?? "") \(ProbeFormat.percent(percent))%，\(detail)"
    }

    func configureText(_ value: String, secondary: String?, detail: String, dimmed: Bool, color: UIColor? = nil) {
        let text = NSMutableAttributedString(string: value, attributes: [
            .font: ProbeStyle.digits(22), .foregroundColor: color ?? (dimmed ? .secondaryLabel : .label),
        ])
        if metric == .network, value != "—" {
            text.append(NSAttributedString(string: "/s", attributes: [.font: UIFont.systemFont(ofSize: 11, weight: .bold), .foregroundColor: UIColor.secondaryLabel]))
        }
        valueLabel.attributedText = text
        meter.isHidden = true
        detailLabel.text = [secondary, detail].compactMap { $0 }.joined(separator: "\n")
        detailLabel.numberOfLines = 2
        accessibilityLabel = "\(titleLabel.text ?? "") \(value) \(secondary ?? "")，\(detail)"
    }
}
