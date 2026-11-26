import UIKit

final class DetailIFrameLinkView: UIControl {
    private let iframeBlock: RenderedIFrameLinkBlock
    private let onTapped: () -> Void
    private let titleLabel = UILabel()
    private let sourceLabel = UILabel()

    init(
        iframeBlock: RenderedIFrameLinkBlock,
        onTapped: @escaping () -> Void
    ) {
        self.iframeBlock = iframeBlock
        self.onTapped = onTapped
        super.init(frame: .zero)
        configureView()
        configureLabels()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            alpha = isHighlighted ? 0.72 : 1
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let frames = DetailIFrameLinkLayout.frames(
            iframeBlock: iframeBlock,
            bounds: bounds
        )
        titleLabel.frame = frames.title
        sourceLabel.frame = frames.source
    }

    private func configureView() {
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 8
        layer.masksToBounds = true
        isAccessibilityElement = true
        accessibilityTraits = [.button, .link]
        accessibilityLabel = "嵌入内容 \(iframeBlock.displayDomain) \(iframeBlock.source)"
        addTarget(self, action: #selector(handleTap), for: .touchUpInside)
    }

    private func configureLabels() {
        titleLabel.font = DetailIFrameLinkLayout.titleFont
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 1
        titleLabel.text = DetailIFrameLinkLayout.titleText(displayDomain: iframeBlock.displayDomain)
        addSubview(titleLabel)

        sourceLabel.font = DetailIFrameLinkLayout.sourceFont
        sourceLabel.textColor = .secondaryLabel
        sourceLabel.numberOfLines = 2
        sourceLabel.lineBreakMode = .byTruncatingMiddle
        sourceLabel.text = iframeBlock.source
        addSubview(sourceLabel)
    }

    @objc
    private func handleTap() {
        onTapped()
    }
}

enum DetailIFrameLinkLayout {
    static let titleFont = UIFont.preferredFont(forTextStyle: .subheadline)
    static let sourceFont = UIFont.preferredFont(forTextStyle: .footnote)
    private static let fallbackWidth: CGFloat = 320
    private static let horizontalInset: CGFloat = 14
    private static let verticalInset: CGFloat = 12
    private static let labelSpacing: CGFloat = 4

    static func measure(
        iframeBlock: RenderedIFrameLinkBlock,
        constrainedSize: CGSize
    ) -> CGSize {
        let width = resolvedWidth(constrainedSize.width)
        let textWidth = max(width - horizontalInset * 2, 1)
        let titleHeight = ceil(titleText(displayDomain: iframeBlock.displayDomain).height(
            font: titleFont,
            width: textWidth,
            maximumNumberOfLines: 1
        ))
        let sourceHeight = ceil(iframeBlock.source.height(
            font: sourceFont,
            width: textWidth,
            maximumNumberOfLines: 2
        ))
        return CGSize(
            width: width,
            height: verticalInset * 2 + titleHeight + labelSpacing + sourceHeight
        )
    }

    static func frames(
        iframeBlock: RenderedIFrameLinkBlock,
        bounds: CGRect
    ) -> (title: CGRect, source: CGRect) {
        let textWidth = max(bounds.width - horizontalInset * 2, 1)
        let titleHeight = ceil(titleText(displayDomain: iframeBlock.displayDomain).height(
            font: titleFont,
            width: textWidth,
            maximumNumberOfLines: 1
        ))
        let sourceHeight = ceil(iframeBlock.source.height(
            font: sourceFont,
            width: textWidth,
            maximumNumberOfLines: 2
        ))
        let titleFrame = CGRect(
            x: horizontalInset,
            y: verticalInset,
            width: textWidth,
            height: titleHeight
        )
        let sourceFrame = CGRect(
            x: horizontalInset,
            y: titleFrame.maxY + labelSpacing,
            width: textWidth,
            height: sourceHeight
        )
        return (titleFrame, sourceFrame)
    }

    static func titleText(displayDomain: String) -> String {
        "嵌入内容 · \(displayDomain) · 点击查看"
    }

    private static func resolvedWidth(_ width: CGFloat) -> CGFloat {
        guard width.isFinite, width > 0 else { return fallbackWidth }
        return width
    }
}

private extension String {
    func height(font: UIFont, width: CGFloat, maximumNumberOfLines: Int) -> CGFloat {
        let lineHeight = font.lineHeight * CGFloat(max(maximumNumberOfLines, 1))
        let measured = (self as NSString).boundingRect(
            with: CGSize(width: width, height: lineHeight),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return min(ceil(measured.height), lineHeight)
    }
}
