import UIKit

/// 服务器监控的视觉规范：框架黑白，指标各有一个系统色，用量到阈值统一变橙、变红。
enum ProbeStyle {
    enum Metric {
        case cpu, memory, disk, network

        var color: UIColor {
            switch self {
            case .cpu: return .systemBlue
            case .memory: return .systemIndigo
            case .disk: return .systemTeal
            case .network: return .systemPink
            }
        }
    }

    static func color(for metric: Metric, percent: Double?) -> UIColor {
        switch ProbeUsageLevel(percent: percent) {
        case .normal: return metric.color
        case .warning: return .systemOrange
        case .critical: return .systemRed
        }
    }

    /// 大号数字的颜色：正常时用主文字色，只有告警才变色。
    static func valueColor(percent: Double?) -> UIColor {
        switch ProbeUsageLevel(percent: percent) {
        case .normal: return .label
        case .warning: return .systemOrange
        case .critical: return .systemRed
        }
    }

    /// 百分比曲线的纵轴上限：取不小于峰值的整档（5/10/25/50/100）。
    static func chartCeiling(_ peak: Double?) -> Double {
        let peak = peak ?? 0
        return [5.0, 10, 25, 50].first { peak * 1.15 <= $0 } ?? 100
    }

    static let card = UIColor.secondarySystemGroupedBackground
    static let background = UIColor.systemGroupedBackground
    static let cardRadius: CGFloat = 20

    static func mono(_ size: CGFloat, _ weight: UIFont.Weight = .regular) -> UIFont {
        .monospacedSystemFont(ofSize: size, weight: weight)
    }

    static func digits(_ size: CGFloat, _ weight: UIFont.Weight = .heavy) -> UIFont {
        .monospacedDigitSystemFont(ofSize: size, weight: weight)
    }

    /// “0.9%” 这类数字加较小单位。
    static func number(_ value: String, unit: String, size: CGFloat, color: UIColor = .label) -> NSAttributedString {
        let text = NSMutableAttributedString(string: value, attributes: [
            .font: digits(size), .foregroundColor: color, .kern: -size * 0.035,
        ])
        if value != "—" {
            text.append(NSAttributedString(string: unit, attributes: [
                .font: UIFont.systemFont(ofSize: size * 0.45, weight: .bold), .foregroundColor: color,
            ]))
        }
        return text
    }

    static func label(_ font: UIFont, _ color: UIColor = .label, lines: Int = 1) -> UILabel {
        let label = UILabel()
        label.font = font
        label.textColor = color
        label.numberOfLines = lines
        label.adjustsFontForContentSizeCategory = false
        return label
    }
}

/// 趋势线：折线加浅色填充。`cutAtEnd` 表示数据在最后一个点之后中断（离线），后面画虚线。
final class ProbeSparklineView: UIView {
    var values: [Double] = [] { didSet { setNeedsLayout() } }
    /// 纵轴上限；nil 时按数据最大值自动留白。
    var maximum: Double?
    var cutAtEnd = false { didSet { setNeedsLayout() } }
    var lineColor: UIColor = .systemBlue { didSet { updateColors() } }
    var lineWidth: CGFloat = 1.6 { didSet { lineLayer.lineWidth = lineWidth } }
    /// 手指按住时高亮的采样点：画一条竖线和一个圆点。nil 时不显示。
    var highlightedIndex: Int? {
        didSet { if oldValue != highlightedIndex { updateHighlight() } }
    }

    private let fillLayer = CAShapeLayer()
    private let lineLayer = CAShapeLayer()
    private let dashLayer = CAShapeLayer()
    private let endLayer = CAShapeLayer()
    private let cursorLayer = CAShapeLayer()
    private let markerLayer = CAShapeLayer()
    /// 上一次布局时每个采样点的位置，用来把手指位置换算成采样点。
    private var plotted: [CGPoint] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        lineLayer.fillColor = nil
        lineLayer.lineWidth = lineWidth
        lineLayer.lineJoin = .round
        lineLayer.lineCap = .round
        dashLayer.fillColor = nil
        dashLayer.lineWidth = 1.2
        dashLayer.lineDashPattern = [3, 4]
        cursorLayer.lineWidth = 1
        cursorLayer.lineDashPattern = [2, 2]
        markerLayer.lineWidth = 2
        [fillLayer, lineLayer, dashLayer, endLayer, cursorLayer, markerLayer].forEach(layer.addSublayer)
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateColors()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        [fillLayer, lineLayer, dashLayer, endLayer, cursorLayer, markerLayer].forEach { $0.frame = bounds }
        let width = bounds.width, height = bounds.height
        guard values.count >= 2, width > 0, height > 0 else {
            plotted = []
            updateHighlight()
            [fillLayer, lineLayer, endLayer].forEach { $0.path = nil }
            // 没有数据时画一条底部虚线，表示“暂无趋势”。
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 0, y: height - 1))
            path.addLine(to: CGPoint(x: width, y: height - 1))
            dashLayer.path = values.isEmpty ? path.cgPath : nil
            return
        }
        let pad = lineWidth
        let top = max(maximum ?? (values.max() ?? 1) * 1.15, 0.0001)
        let span = cutAtEnd ? width * 0.55 : width
        let points = values.enumerated().map { index, value in
            CGPoint(x: CGFloat(index) / CGFloat(values.count - 1) * span,
                    y: height - pad - CGFloat(min(value, top) / top) * (height - pad * 2))
        }
        plotted = points
        updateHighlight()
        let line = UIBezierPath()
        line.move(to: points[0])
        points.dropFirst().forEach(line.addLine)
        lineLayer.path = line.cgPath
        if let last = points.last {
            let fill = line.copy() as! UIBezierPath
            fill.addLine(to: CGPoint(x: last.x, y: height))
            fill.addLine(to: CGPoint(x: 0, y: height))
            fill.close()
            fillLayer.path = fill.cgPath
        } else {
            fillLayer.path = nil
        }
        if cutAtEnd, let last = points.last {
            let dash = UIBezierPath()
            dash.move(to: CGPoint(x: last.x, y: height - pad))
            dash.addLine(to: CGPoint(x: width, y: height - pad))
            dashLayer.path = dash.cgPath
            endLayer.path = UIBezierPath(arcCenter: last, radius: 2.4, startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath
        } else {
            dashLayer.path = nil
            endLayer.path = nil
        }
    }

    /// 离手指横向最近的采样点。
    func nearestIndex(toX x: CGFloat) -> Int? {
        guard let last = plotted.last else { return nil }
        guard plotted.count > 1, last.x > 0 else { return 0 }
        let ratio = min(max(x / last.x, 0), 1)
        return Int((ratio * CGFloat(plotted.count - 1)).rounded())
    }

    private func updateHighlight() {
        guard let index = highlightedIndex, plotted.indices.contains(index) else {
            cursorLayer.path = nil
            markerLayer.path = nil
            return
        }
        let point = plotted[index]
        let cursor = UIBezierPath()
        cursor.move(to: CGPoint(x: point.x, y: 0))
        cursor.addLine(to: CGPoint(x: point.x, y: bounds.height))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cursorLayer.path = cursor.cgPath
        markerLayer.path = UIBezierPath(arcCenter: point, radius: 4.5, startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath
        CATransaction.commit()
    }

    private func updateColors() {
        let resolved = lineColor.resolvedColor(with: traitCollection)
        cursorLayer.strokeColor = UIColor.secondaryLabel.resolvedColor(with: traitCollection).cgColor
        markerLayer.fillColor = resolved.cgColor
        markerLayer.strokeColor = ProbeStyle.card.resolvedColor(with: traitCollection).cgColor
        lineLayer.strokeColor = resolved.cgColor
        fillLayer.fillColor = resolved.withAlphaComponent(0.14).cgColor
        dashLayer.strokeColor = UIColor.tertiaryLabel.resolvedColor(with: traitCollection).cgColor
        endLayer.fillColor = UIColor.systemRed.resolvedColor(with: traitCollection).cgColor
    }
}

/// 分段刻度条：比连续进度条更有“仪表”感。
final class ProbeSegmentMeterView: UIView {
    var segments = 24 { didSet { setNeedsDisplay() } }
    var percent: Double? { didSet { setNeedsDisplay() } }
    var metric: ProbeStyle.Metric = .memory { didSet { setNeedsDisplay() } }
    /// 过期数据显示为灰色。
    var isDimmed = false { didSet { setNeedsDisplay() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard segments > 0 else { return }
        let gap: CGFloat = segments > 12 ? 2.5 : 1.5
        let width = (bounds.width - gap * CGFloat(segments - 1)) / CGFloat(segments)
        let filled = percent.map { Int((min(max($0, 0), 100) / 100 * Double(segments)).rounded()) } ?? 0
        let on = isDimmed ? UIColor.tertiaryLabel : ProbeStyle.color(for: metric, percent: percent)
        for index in 0..<segments {
            let cell = CGRect(x: CGFloat(index) * (width + gap), y: 0, width: width, height: bounds.height)
            (index < filled ? on : UIColor.tertiarySystemFill).setFill()
            UIBezierPath(roundedRect: cell, cornerRadius: min(1.5, width / 2)).fill()
        }
    }
}

/// 在线 / 离线状态：小圆点加文字，圆点带一圈淡色光晕。
final class ProbeStatusView: UIView {
    private let dot = UIView()
    private let halo = UIView()
    private let label = ProbeStyle.label(.systemFont(ofSize: 12, weight: .semibold), .secondaryLabel)

    override init(frame: CGRect) {
        super.init(frame: frame)
        [halo, dot, label].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        halo.layer.cornerRadius = 6.5
        dot.layer.cornerRadius = 3.5
        NSLayoutConstraint.activate([
            halo.leadingAnchor.constraint(equalTo: leadingAnchor),
            halo.centerYAnchor.constraint(equalTo: centerYAnchor),
            halo.widthAnchor.constraint(equalToConstant: 13),
            halo.heightAnchor.constraint(equalToConstant: 13),
            dot.centerXAnchor.constraint(equalTo: halo.centerXAnchor),
            dot.centerYAnchor.constraint(equalTo: halo.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 7),
            dot.heightAnchor.constraint(equalToConstant: 7),
            label.leadingAnchor.constraint(equalTo: halo.trailingAnchor, constant: 3),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 过期或暂无数据时隐藏圆点，避免把旧数据误认为当前状态。
    func configure(availability: ProbeAvailability, isStale: Bool, showsText: Bool = true) {
        let color: UIColor
        switch (isStale, availability) {
        case (true, _), (_, .unknown):
            isHidden = true
            return
        case (_, .online):
            color = .systemGreen
            label.text = showsText ? "在线" : nil
            label.textColor = .secondaryLabel
        case (_, .offline):
            color = .systemRed
            label.text = showsText ? "离线" : nil
            label.textColor = .systemRed
        }
        isHidden = false
        dot.backgroundColor = color
        halo.backgroundColor = color.withAlphaComponent(0.22)
        accessibilityLabel = availability == .online ? "在线" : "离线"
        isAccessibilityElement = true
    }
}

/// 筛选胶囊：选中项反色。最右侧是排序按钮，点开选择排序方式。
final class ProbeFilterChipsView: UIView {
    var onSelect: ((ProbeListFilter) -> Void)?
    var onSort: ((ProbeListSort) -> Void)?
    private let stack = UIStackView()
    private var buttons: [ProbeListFilter: UIButton] = [:]
    private let sortButton = UIButton(type: .system)
    private var sort: ProbeListSort = .problemsFirst
    /// 一行放不下时排序按钮只显示图标（例如调大字号后）。
    private var sortShowsTitle = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        stack.axis = .horizontal
        stack.spacing = 6
        [stack, sortButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            sortButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            sortButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            sortButton.leadingAnchor.constraint(greaterThanOrEqualTo: stack.trailingAnchor, constant: 8),
        ])
        sortButton.showsMenuAsPrimaryAction = true
        sortButton.accessibilityIdentifier = "probe-sort-menu"
        sortButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        for filter in ProbeListFilter.allCases {
            let button = UIButton(type: .system)
            button.addAction(UIAction { [weak self] _ in self?.onSelect?(filter) }, for: .touchUpInside)
            button.accessibilityIdentifier = "probe-filter-\(filter.rawValue)"
            buttons[filter] = button
            stack.addArrangedSubview(button)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 1 else { return }
        // 按带文字的宽度判断，避免在两种状态之间来回切换。
        let titled = makeSortConfiguration(showsTitle: true)
        let probe = UIButton(configuration: titled)
        let fits = stack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width + 8
            + probe.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width <= bounds.width
        guard fits != sortShowsTitle else { return }
        sortShowsTitle = fits
        updateSortButton()
    }

    func configure(selected: ProbeListFilter, counts: [ProbeListFilter: Int], sort: ProbeListSort) {
        self.sort = sort
        updateSortButton()
        for (filter, button) in buttons {
            let isOn = filter == selected
            var config = UIButton.Configuration.filled()
            config.cornerStyle = .capsule
            config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
            config.baseBackgroundColor = isOn ? .label : ProbeStyle.card
            let title = NSMutableAttributedString(string: filter.title, attributes: [
                .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: isOn ? UIColor.systemBackground : UIColor.label,
            ])
            title.append(NSAttributedString(string: " \(counts[filter] ?? 0)", attributes: [
                .font: ProbeStyle.mono(11, .medium),
                .foregroundColor: isOn ? UIColor.systemBackground.withAlphaComponent(0.65) : UIColor.secondaryLabel,
            ]))
            config.attributedTitle = AttributedString(title)
            button.configuration = config
            button.accessibilityTraits = isOn ? [.button, .selected] : .button
        }
    }

    private func updateSortButton() {
        sortButton.configuration = makeSortConfiguration(showsTitle: sortShowsTitle)
        sortButton.accessibilityLabel = "排序：\(sort.title)"
        sortButton.menu = UIMenu(title: "排序", children: ProbeListSort.allCases.map { option in
            UIAction(title: option.title, state: option == sort ? .on : .off) { [weak self] _ in self?.onSort?(option) }
        })
    }

    private func makeSortConfiguration(showsTitle: Bool) -> UIButton.Configuration {
        // 排序是次要操作：不加底色，灰字 + 小箭头，和左边的筛选胶囊区分开。
        var config = UIButton.Configuration.plain()
        config.baseForegroundColor = .secondaryLabel
        config.image = UIImage(systemName: "chevron.up.chevron.down")
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        config.imagePlacement = .trailing
        config.imagePadding = 3
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 4, bottom: 6, trailing: 0)
        if showsTitle {
            config.attributedTitle = AttributedString(sort.title, attributes: AttributeContainer([
                .font: UIFont.systemFont(ofSize: 13, weight: .medium),
            ]))
        } else {
            config.image = UIImage(systemName: "arrow.up.arrow.down")
        }
        return config
    }
}
