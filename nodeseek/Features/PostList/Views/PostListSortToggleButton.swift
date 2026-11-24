import UIKit

final class PostListSortToggleButton: UIButton {
    static let collapsedWidth: CGFloat = 44
    var expandedHeight: CGFloat { max(Self.collapsedWidth, ceil(titleFont.lineHeight) + 8) }

    private let handle = UIView()
    private var dockedEdge: FloatingAdsorbableEdges = .right

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        accessibilityIdentifier = "post-list-sort-toggle"
        handle.backgroundColor = .secondaryLabel
        handle.isUserInteractionEnabled = false
        handle.layer.cornerRadius = 2
        addSubview(handle)
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 3)
        applyDockedEdge(.right)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func expandedWidth(for title: String, maxWidth: CGFloat? = nil) -> CGFloat {
        let measured = max(
            Self.collapsedWidth,
            ceil((title as NSString).size(withAttributes: [.font: titleFont]).width) + 28
        )
        guard let maxWidth else { return measured }
        return min(measured, max(Self.collapsedWidth, maxWidth))
    }

    private var titleFont: UIFont {
        .preferredFont(forTextStyle: .footnote, compatibleWith: traitCollection)
    }

    func apply(sortMode: PostListSortMode, expanded: Bool) {
        let title = sortMode.accessibilityTitle
        var configuration = UIButton.Configuration.plain()
        configuration.baseForegroundColor = .label
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
        configuration.title = expanded ? title : nil
        configuration.titleLineBreakMode = .byTruncatingTail
        let font = titleFont
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var attributes = incoming
            attributes.font = font
            return attributes
        }
        self.configuration = configuration
        titleLabel?.alpha = expanded ? 1 : 0
        backgroundColor = expanded ? .secondarySystemBackground : .clear
        layer.borderWidth = expanded ? 1 / UIScreen.main.scale : 0
        layer.borderColor = UIColor.separator.resolvedColor(with: traitCollection).cgColor
        layer.shadowOpacity = expanded ? 0.12 : 0
        handle.alpha = expanded ? 0 : 1
        accessibilityLabel = NSLocalizedString("sort.title", tableName: "PostList", comment: "")
        accessibilityValue = title
        setNeedsLayout()
    }

    /// 收起动画期间同步淡出展开气泡并显现边缘短线，避免动画前内容瞬间跳变。
    func applyCollapsedVisuals() {
        titleLabel?.alpha = 0
        backgroundColor = .clear
        layer.borderWidth = 0
        layer.shadowOpacity = 0
        handle.alpha = 1
    }

    func applyDockedEdge(_ edge: FloatingAdsorbableEdges) {
        dockedEdge = edge
        applyFloatingDockedCorners(for: edge)
        setNeedsLayout()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        layer.borderColor = UIColor.separator.resolvedColor(with: traitCollection).cgColor
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let x = dockedEdge == .left ? bounds.minX + 3 : bounds.maxX - 7
        handle.frame = CGRect(x: x, y: bounds.midY - 12, width: 4, height: 24)
        layer.shadowPath = layer.shadowOpacity > 0
            ? UIBezierPath(
                roundedRect: bounds,
                byRoundingCorners: roundedRectCorners(for: layer.maskedCorners),
                cornerRadii: CGSize(width: layer.cornerRadius, height: layer.cornerRadius)
            ).cgPath
            : nil
    }

    private func roundedRectCorners(for maskedCorners: CACornerMask) -> UIRectCorner {
        var corners: UIRectCorner = []
        if maskedCorners.contains(.layerMinXMinYCorner) { corners.insert(.topLeft) }
        if maskedCorners.contains(.layerMaxXMinYCorner) { corners.insert(.topRight) }
        if maskedCorners.contains(.layerMinXMaxYCorner) { corners.insert(.bottomLeft) }
        if maskedCorners.contains(.layerMaxXMaxYCorner) { corners.insert(.bottomRight) }
        return corners
    }
}
