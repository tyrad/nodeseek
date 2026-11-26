import UIKit

final class DetailCodeBlockView: UIView {
    private let codeBlock: RenderedCodeBlock
    private let pasteboardStringWriter: PasteboardStringWriter
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let codeLabel = UILabel()
    private let chromeDotsStack = UIStackView()
    private let copyButton = UIButton(type: .system)
    private var contentWidthConstraint: NSLayoutConstraint?
    private var copyResetWorkItem: DispatchWorkItem?

    init(
        codeBlock: RenderedCodeBlock,
        pasteboardStringWriter: @escaping PasteboardStringWriter = { UIPasteboard.general.string = $0 }
    ) {
        self.codeBlock = codeBlock
        self.pasteboardStringWriter = pasteboardStringWriter
        super.init(frame: .zero)
        configureView()
        configureChromeDots()
        configureCopyButton()
        configureScrollView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        copyResetWorkItem?.cancel()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentWidthConstraint?.constant = DetailCodeBlockLayout.contentWidth(
            for: codeBlock.text,
            viewportWidth: bounds.width
        )
    }

    private func configureView() {
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 8
        layer.masksToBounds = true
    }

    private func configureChromeDots() {
        chromeDotsStack.axis = .horizontal
        chromeDotsStack.alignment = .center
        chromeDotsStack.spacing = 7
        chromeDotsStack.isUserInteractionEnabled = false
        chromeDotsStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chromeDotsStack)

        [
            UIColor(red: 1, green: 95 / 255, blue: 101 / 255, alpha: 1),
            UIColor(red: 1, green: 204 / 255, blue: 41 / 255, alpha: 1),
            UIColor(red: 46 / 255, green: 204 / 255, blue: 84 / 255, alpha: 1)
        ].forEach { color in
            let dot = UIView()
            dot.backgroundColor = color
            dot.layer.cornerRadius = DetailCodeBlockLayout.chromeDotSize / 2
            dot.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: DetailCodeBlockLayout.chromeDotSize),
                dot.heightAnchor.constraint(equalToConstant: DetailCodeBlockLayout.chromeDotSize)
            ])
            chromeDotsStack.addArrangedSubview(dot)
        }

        NSLayoutConstraint.activate([
            chromeDotsStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            chromeDotsStack.centerYAnchor.constraint(equalTo: topAnchor, constant: DetailCodeBlockLayout.chromeHeight / 2)
        ])
    }

    private func configureCopyButton() {
        copyButton.accessibilityIdentifier = "detail-code-copy-button"
        copyButton.accessibilityLabel = "复制代码"
        copyButton.tintColor = .secondaryLabel
        copyButton.setImage(copyIcon(named: "doc.on.doc"), for: .normal)
        copyButton.addTarget(self, action: #selector(copyCode), for: .touchUpInside)
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(copyButton)

        NSLayoutConstraint.activate([
            copyButton.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            copyButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            copyButton.widthAnchor.constraint(equalToConstant: 30),
            copyButton.heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    private func configureScrollView() {
        scrollView.backgroundColor = .clear
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.alwaysBounceVertical = false
        scrollView.bounces = true
        scrollView.isDirectionalLockEnabled = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        contentView.backgroundColor = .clear
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)

        codeLabel.numberOfLines = 0
        codeLabel.lineBreakMode = .byClipping
        codeLabel.font = DetailCodeBlockLayout.codeFont
        codeLabel.textColor = .label
        codeLabel.text = codeBlock.text
        codeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        codeLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(codeLabel)

        let widthConstraint = contentView.widthAnchor.constraint(
            equalToConstant: DetailCodeBlockLayout.contentWidth(
                for: codeBlock.text,
                viewportWidth: DetailCodeBlockLayout.fallbackViewportWidth
            )
        )
        contentWidthConstraint = widthConstraint

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: DetailCodeBlockLayout.chromeHeight),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -DetailCodeBlockLayout.bottomInset),

            widthConstraint,
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),

            codeLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: DetailCodeBlockLayout.horizontalInset),
            codeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -DetailCodeBlockLayout.horizontalInset),
            codeLabel.topAnchor.constraint(equalTo: contentView.topAnchor),
            codeLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor)
        ])
    }

    @objc
    private func copyCode() {
        pasteboardStringWriter(codeBlock.text)
        showCopiedState()
    }

    private func showCopiedState() {
        copyResetWorkItem?.cancel()
        copyButton.setImage(copyIcon(named: "checkmark"), for: .normal)

        let workItem = DispatchWorkItem { [weak self] in
            self?.copyButton.setImage(self?.copyIcon(named: "doc.on.doc"), for: .normal)
        }
        copyResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: workItem)
    }

    private func copyIcon(named name: String) -> UIImage? {
        UIImage(
            systemName: name,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        )
    }
}

enum DetailCodeBlockLayout {
    static let codeFont = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    static let chromeHeight: CGFloat = 38
    static let bottomInset: CGFloat = 12
    static let horizontalInset: CGFloat = 12
    static let chromeDotSize: CGFloat = 10
    static let fallbackViewportWidth: CGFloat = 320

    private enum Layout {
        static let minHeight: CGFloat = 64
    }

    static func measure(codeBlock: RenderedCodeBlock, constrainedSize: CGSize) -> CGSize {
        let width = resolvedWidth(constrainedSize.width)
        let lineCount = max(codeBlock.text.components(separatedBy: .newlines).count, 1)
        let textHeight = CGFloat(lineCount) * max(codeFont.lineHeight, 1)
        let height = max(
            Layout.minHeight,
            chromeHeight + textHeight + bottomInset
        )
        return CGSize(width: width, height: ceil(height))
    }

    static func naturalCodeWidth(for text: String) -> CGFloat {
        let lines = text.components(separatedBy: .newlines)
        let maxLineWidth = lines.reduce(CGFloat(0)) { partialResult, line in
            let width = (line as NSString).size(withAttributes: [.font: codeFont]).width
            return max(partialResult, ceil(width))
        }
        return max(maxLineWidth + horizontalInset * 2, horizontalInset * 2)
    }

    static func contentWidth(for text: String, viewportWidth: CGFloat) -> CGFloat {
        max(naturalCodeWidth(for: text), resolvedWidth(viewportWidth))
    }

    private static func resolvedWidth(_ width: CGFloat) -> CGFloat {
        guard width.isFinite, width > 0 else {
            return fallbackViewportWidth
        }
        return width
    }
}
