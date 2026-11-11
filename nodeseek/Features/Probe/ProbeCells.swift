import UIKit

/// 卡片 / 紧凑两种行共用的显示文案。
struct ProbeRowContent {
    let entry: ProbeListEntry
    let trend: [Double]?

    var metrics: ProbeMetrics? { entry.server.status?.metrics }
    var availability: ProbeAvailability { entry.server.availability }
    /// 离线和过期时指标是旧值，统一灰显。
    var isDimmed: Bool { entry.isStale || availability != .online }

    var title: String {
        [entry.server.node.region, entry.displayName].compactMap { $0 }.joined(separator: " ")
    }

    /// 右上角的元信息：运行时间，或者说明数据为什么不是实时的。
    func meta(now: Date = Date()) -> String {
        switch availability {
        case .unknown: return "暂无数据"
        case .offline: return "最后上报 · \(ProbeFormat.relative(entry.server.status?.sampledAt, now: now))"
        case .online:
            if entry.isStale { return "缓存 · \(ProbeFormat.relative(entry.server.status?.sampledAt, now: now))" }
            return ProbeFormat.uptime(metrics?.uptime)
        }
    }

    var plan: ProbePlanSummary? {
        ProbePlanSummary(plan: entry.server.node.plan, metrics: metrics)
    }

    /// 列表卡片底部的套餐行。只有快到期、过期、流量超额时才着色。
    var planLine: NSAttributedString? {
        let summary = plan
        let tags = entry.server.node.tags ?? []
        guard summary != nil || !tags.isEmpty else { return nil }
        let text = NSMutableAttributedString()
        func add(_ string: String, _ color: UIColor = .secondaryLabel, bold: Bool = false) {
            if text.length > 0 {
                text.append(NSAttributedString(string: " · ", attributes: [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.tertiaryLabel]))
            }
            text.append(NSAttributedString(string: string, attributes: [
                .font: UIFont.systemFont(ofSize: 12, weight: bold ? .semibold : .regular), .foregroundColor: color,
            ]))
        }
        if let expiry = summary?.expiry {
            add(expiry, ProbePlanStyle.color(summary?.expiryLevel ?? .normal), bold: summary?.expiryLevel != .normal)
        }
        if let price = summary?.price { add(price) }
        if let traffic = summary?.traffic {
            let line = traffic.isOver ? "流量超出 \(ProbeFormat.bytes(traffic.used - traffic.limit))" : "流量 \(ProbeFormat.percent(traffic.percent, decimals: 0))%"
            let level = summary?.trafficLevel ?? .normal
            add(line, ProbePlanStyle.color(level), bold: level != .normal)
        }
        tags.prefix(3).forEach { add($0, .label) }
        return text
    }

    var accessibilityText: String {
        var parts = [entry.displayName]
        switch availability {
        case .online: parts.append(entry.isStale ? "缓存数据" : "在线")
        case .offline: parts.append("离线")
        case .unknown: parts.append("暂无数据")
        }
        if let metrics {
            parts.append("CPU \(ProbeFormat.percent(metrics.cpuPercent))%")
            parts.append("内存 \(ProbeFormat.percent(metrics.memPercent))%")
            parts.append("硬盘 \(ProbeFormat.percent(metrics.diskPercent))%")
        }
        if let plan { parts += plan.compact }
        return parts.joined(separator: "，")
    }
}

/// 卡片容器：圆角卡片，过期时改为虚线边框。
class ProbeCardContainerCell: UITableViewCell {
    let card = UIView()
    private let dashedBorder = CAShapeLayer()

    var isStaleStyle = false {
        didSet { dashedBorder.isHidden = !isStaleStyle }
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none
        card.backgroundColor = ProbeStyle.card
        card.layer.cornerRadius = ProbeStyle.cardRadius
        card.layer.cornerCurve = .continuous
        card.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(card)
        dashedBorder.fillColor = nil
        dashedBorder.lineWidth = 1
        dashedBorder.lineDashPattern = [4, 3]
        dashedBorder.isHidden = true
        card.layer.addSublayer(dashedBorder)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5),
            card.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        dashedBorder.frame = card.bounds
        dashedBorder.path = UIBezierPath(roundedRect: card.bounds.insetBy(dx: 0.5, dy: 0.5), cornerRadius: card.layer.cornerRadius).cgPath
        dashedBorder.strokeColor = UIColor.separator.resolvedColor(with: traitCollection).cgColor
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        UIView.animate(withDuration: animated ? 0.15 : 0) {
            self.card.transform = highlighted ? CGAffineTransform(scaleX: 0.98, y: 0.98) : .identity
        }
    }
}

/// 一行“标签 + 刻度条 + 百分比”。
final class ProbeMeterRow: UIView {
    private let titleLabel = ProbeStyle.label(ProbeStyle.mono(10.5, .medium), .secondaryLabel)
    private let meter = ProbeSegmentMeterView()
    private let valueLabel = ProbeStyle.label(ProbeStyle.digits(13, .bold))
    private let detailLabel = ProbeStyle.label(ProbeStyle.mono(10.5), .tertiaryLabel)

    init(title: String, metric: ProbeStyle.Metric) {
        super.init(frame: .zero)
        titleLabel.text = title
        meter.metric = metric
        valueLabel.textAlignment = .right
        detailLabel.textAlignment = .right
        detailLabel.adjustsFontSizeToFitWidth = true
        detailLabel.minimumScaleFactor = 0.8
        [titleLabel, meter, valueLabel, detailLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.widthAnchor.constraint(equalToConstant: 34),
            meter.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 6),
            meter.centerYAnchor.constraint(equalTo: centerYAnchor),
            meter.heightAnchor.constraint(equalToConstant: 9),
            detailLabel.leadingAnchor.constraint(equalTo: meter.trailingAnchor, constant: 8),
            detailLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            detailLabel.widthAnchor.constraint(equalToConstant: 76),
            valueLabel.leadingAnchor.constraint(equalTo: detailLabel.trailingAnchor, constant: 4),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueLabel.widthAnchor.constraint(equalToConstant: 48),
            heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(percent: Double?, used: Int64?, total: Int64?, dimmed: Bool) {
        meter.percent = percent
        meter.isDimmed = dimmed
        valueLabel.text = percent == nil ? "—" : ProbeFormat.percent(percent) + "%"
        valueLabel.textColor = dimmed ? .secondaryLabel : ProbeStyle.valueColor(percent: percent)
        detailLabel.text = total == nil ? nil : "\(ProbeFormat.bytes(used))/\(ProbeFormat.bytes(total))"
    }
}

/// 卡片模式：一台服务器一张卡，CPU 大数字加趋势线，内存和硬盘用刻度条。
final class ProbeServerCardCell: ProbeCardContainerCell {
    static let reuseIdentifier = "ProbeServerCardCell"

    private let titleLabel = ProbeStyle.label(.systemFont(ofSize: 16, weight: .semibold))
    private let statusView = ProbeStatusView()
    private let metaLabel = ProbeStyle.label(ProbeStyle.mono(11), .secondaryLabel)
    private let cpuCaption = ProbeStyle.label(ProbeStyle.mono(10.5, .medium), .secondaryLabel)
    private let cpuLabel = UILabel()
    private let sparkline = ProbeSparklineView()
    private let memoryRow = ProbeMeterRow(title: "内存", metric: .memory)
    private let diskRow = ProbeMeterRow(title: "硬盘", metric: .disk)
    private let networkLabel = UILabel()
    /// 到期 · 价格 · 流量 · 标签；面板没填时隐藏。
    private let planLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        planLabel.lineBreakMode = .byTruncatingTail
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        metaLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        statusView.setContentCompressionResistancePriority(.required, for: .horizontal)

        let header = UIStackView(arrangedSubviews: [titleLabel, statusView, UIView(), metaLabel])
        header.spacing = 8
        header.alignment = .center
        let cpuColumn = UIStackView(arrangedSubviews: [cpuCaption, cpuLabel])
        cpuColumn.axis = .vertical
        cpuColumn.spacing = 0
        cpuColumn.setContentHuggingPriority(.required, for: .horizontal)
        let cpuRow = UIStackView(arrangedSubviews: [cpuColumn, sparkline])
        cpuRow.spacing = 14
        cpuRow.alignment = .bottom
        let column = UIStackView(arrangedSubviews: [header, cpuRow, memoryRow, diskRow, networkLabel, planLabel])
        column.axis = .vertical
        column.spacing = 8
        column.setCustomSpacing(10, after: header)
        column.setCustomSpacing(12, after: cpuRow)
        column.setCustomSpacing(10, after: diskRow)
        column.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            column.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
            column.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            column.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            sparkline.heightAnchor.constraint(equalToConstant: 36),
            cpuColumn.widthAnchor.constraint(greaterThanOrEqualToConstant: 96),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ content: ProbeRowContent) {
        let metrics = content.metrics
        let dimmed = content.isDimmed
        isStaleStyle = content.entry.isStale
        titleLabel.text = content.title
        titleLabel.textColor = content.availability == .unknown ? .secondaryLabel : .label
        statusView.configure(availability: content.availability, isStale: content.entry.isStale)
        metaLabel.text = content.meta()
        let cores = content.entry.server.node.cpuCores.map { " · \($0)C" } ?? ""
        cpuCaption.text = "CPU" + cores
        let cpu = metrics?.cpuPercent
        cpuLabel.attributedText = ProbeStyle.number(
            ProbeFormat.percent(cpu), unit: "%", size: 30,
            color: dimmed ? .secondaryLabel : ProbeStyle.valueColor(percent: cpu)
        )
        sparkline.lineColor = dimmed ? .tertiaryLabel : ProbeStyle.color(for: .cpu, percent: cpu)
        sparkline.cutAtEnd = content.availability == .offline
        // 低负载时按峰值放大，避免曲线贴底成一条直线；下限 5% 防止噪声被放大成剧烈波动。
        sparkline.maximum = ProbeStyle.chartCeiling(content.trend?.max())
        sparkline.values = content.trend ?? []
        memoryRow.configure(percent: metrics?.memPercent, used: metrics?.memUsed, total: metrics?.memTotal, dimmed: dimmed)
        diskRow.configure(percent: metrics?.diskPercent, used: metrics?.diskUsed, total: metrics?.diskTotal, dimmed: dimmed)
        networkLabel.attributedText = Self.network(metrics, dimmed: dimmed)
        planLabel.attributedText = content.planLine
        planLabel.isHidden = planLabel.attributedText == nil
        accessibilityLabel = content.accessibilityText
    }

    static func network(_ metrics: ProbeMetrics?, dimmed: Bool, size: CGFloat = 12) -> NSAttributedString {
        let arrowColor = dimmed ? UIColor.tertiaryLabel : ProbeStyle.Metric.network.color
        let textColor = dimmed ? UIColor.secondaryLabel : UIColor.label
        let text = NSMutableAttributedString()
        func add(_ arrow: String, _ value: Int64?) {
            text.append(NSAttributedString(string: arrow + " ", attributes: [.font: ProbeStyle.mono(size, .bold), .foregroundColor: arrowColor]))
            text.append(NSAttributedString(string: ProbeFormat.rate(value) + "/s", attributes: [.font: ProbeStyle.mono(size, .semibold), .foregroundColor: textColor]))
        }
        add("↑", metrics?.netOutRate)
        text.append(NSAttributedString(string: "    "))
        add("↓", metrics?.netInRate)
        if let totalIn = metrics?.netTotalIn, let totalOut = metrics?.netTotalOut {
            text.append(NSAttributedString(string: "    Σ \(ProbeFormat.bytes(totalIn + totalOut))", attributes: [
                .font: ProbeStyle.mono(size - 1), .foregroundColor: UIColor.tertiaryLabel,
            ]))
        }
        return text
    }
}

/// 紧凑模式：一行一台，适合服务器很多的时候快速扫一眼。
final class ProbeServerCompactCell: UITableViewCell {
    static let reuseIdentifier = "ProbeServerCompactCell"

    private final class Column: UIView {
        let value = ProbeStyle.label(ProbeStyle.digits(13, .bold))
        let meter = ProbeSegmentMeterView()

        init(metric: ProbeStyle.Metric) {
            super.init(frame: .zero)
            meter.metric = metric
            meter.segments = 8
            value.textAlignment = .right
            [value, meter].forEach {
                $0.translatesAutoresizingMaskIntoConstraints = false
                addSubview($0)
            }
            NSLayoutConstraint.activate([
                widthAnchor.constraint(equalToConstant: 44),
                value.topAnchor.constraint(equalTo: topAnchor),
                value.leadingAnchor.constraint(equalTo: leadingAnchor),
                value.trailingAnchor.constraint(equalTo: trailingAnchor),
                meter.topAnchor.constraint(equalTo: value.bottomAnchor, constant: 3),
                meter.leadingAnchor.constraint(equalTo: leadingAnchor),
                meter.trailingAnchor.constraint(equalTo: trailingAnchor),
                meter.heightAnchor.constraint(equalToConstant: 3),
                meter.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func configure(_ percent: Double?, dimmed: Bool) {
            value.text = percent == nil ? "—" : ProbeFormat.percent(percent, decimals: 0) + "%"
            value.textColor = dimmed ? .secondaryLabel : ProbeStyle.valueColor(percent: percent)
            meter.percent = percent
            meter.isDimmed = dimmed
        }
    }

    private let dot = UIView()
    private let titleLabel = ProbeStyle.label(.systemFont(ofSize: 15, weight: .semibold))
    private let metaLabel = ProbeStyle.label(ProbeStyle.mono(10), .secondaryLabel)
    private let cpu = Column(metric: .cpu)
    private let memory = Column(metric: .memory)
    private let disk = Column(metric: .disk)
    private let upLabel = ProbeStyle.label(ProbeStyle.mono(10.5, .semibold))
    private let downLabel = ProbeStyle.label(ProbeStyle.mono(10.5, .semibold))

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = ProbeStyle.card
        dot.layer.cornerRadius = 3.5
        titleLabel.lineBreakMode = .byTruncatingTail
        upLabel.textAlignment = .right
        downLabel.textAlignment = .right
        let names = UIStackView(arrangedSubviews: [titleLabel, metaLabel])
        names.axis = .vertical
        names.spacing = 1
        let network = UIStackView(arrangedSubviews: [upLabel, downLabel])
        network.axis = .vertical
        network.spacing = 1
        let row = UIStackView(arrangedSubviews: [dot, names, cpu, memory, disk, network])
        row.alignment = .center
        row.spacing = 10
        row.setCustomSpacing(8, after: dot)
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 9),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -9),
            row.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            dot.widthAnchor.constraint(equalToConstant: 7),
            dot.heightAnchor.constraint(equalToConstant: 7),
            network.widthAnchor.constraint(equalToConstant: 58),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ content: ProbeRowContent) {
        let metrics = content.metrics
        let dimmed = content.isDimmed
        switch (content.entry.isStale, content.availability) {
        case (_, .offline): dot.backgroundColor = .systemRed
        case (true, _), (_, .unknown): dot.backgroundColor = .tertiaryLabel
        case (_, .online): dot.backgroundColor = .systemGreen
        }
        titleLabel.text = content.title
        titleLabel.textColor = content.availability == .unknown ? .secondaryLabel : .label
        metaLabel.text = content.meta()
        metaLabel.textColor = content.availability == .offline ? .systemRed : .secondaryLabel
        cpu.configure(metrics?.cpuPercent, dimmed: dimmed)
        memory.configure(metrics?.memPercent, dimmed: dimmed)
        disk.configure(metrics?.diskPercent, dimmed: dimmed)
        let color: UIColor = dimmed ? .secondaryLabel : .label
        upLabel.text = "↑" + ProbeFormat.rate(metrics?.netOutRate)
        downLabel.text = "↓" + ProbeFormat.rate(metrics?.netInRate)
        upLabel.textColor = color
        downLabel.textColor = color
        accessibilityLabel = content.accessibilityText
    }
}

/// 分组头：标题、在线数、折叠箭头；分组只属于一个探针时带编辑和删除。
final class ProbeSectionHeaderView: UITableViewHeaderFooterView {
    static let reuseIdentifier = "ProbeSectionHeaderView"

    var onToggle: (() -> Void)?
    private let titleLabel = ProbeStyle.label(.systemFont(ofSize: 13, weight: .semibold), .secondaryLabel)
    private let countLabel = ProbeStyle.label(ProbeStyle.mono(11), .tertiaryLabel)
    private let chevron = UIImageView()
    let menuButton = UIButton(type: .system)

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        var background = UIBackgroundConfiguration.clear()
        background.backgroundColor = ProbeStyle.background
        backgroundConfiguration = background
        chevron.tintColor = .tertiaryLabel
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 10, weight: .bold)
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        menuButton.setImage(UIImage(systemName: "ellipsis.circle"), for: .normal)
        menuButton.tintColor = .secondaryLabel
        menuButton.showsMenuAsPrimaryAction = true
        menuButton.accessibilityLabel = "探针操作"
        let row = UIStackView(arrangedSubviews: [titleLabel, countLabel, chevron, UIView(), menuButton])
        row.spacing = 6
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2),
            row.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor, constant: 4),
            row.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            menuButton.heightAnchor.constraint(equalToConstant: 28),
        ])
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggle)))
        titleLabel.isAccessibilityElement = false
        countLabel.isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(section: ProbeListSection, collapsed: Bool, collapsible: Bool, menu: UIMenu?) {
        titleLabel.text = section.title
        var count = "\(section.onlineCount)/\(section.entries.count)"
        if section.offlineCount > 0 { count += " · 离线 \(section.offlineCount)" }
        countLabel.text = count
        countLabel.textColor = section.offlineCount > 0 ? .systemRed : .tertiaryLabel
        chevron.isHidden = !collapsible
        chevron.image = UIImage(systemName: collapsed ? "chevron.right" : "chevron.down")
        menuButton.menu = menu
        menuButton.isHidden = menu == nil
        isAccessibilityElement = false
        accessibilityElements = [menuButton]
        accessibilityLabel = "\(section.title)，\(count)"
    }

    @objc private func toggle() { onToggle?() }
}
