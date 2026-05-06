//
//  DetailTableNode.swift
//  nodeseek
//
//  Created by Codex on 2026/4/29.
//

import AsyncDisplayKit
import UIKit

final class DetailTableNode: ASDisplayNode {
    private let table: RenderedTableBlock

    init(
        table: RenderedTableBlock,
        onImageTapped: @escaping ([URL], Int) -> Void,
        onLinkTapped: @escaping (URL) -> Void = { _ in }
    ) {
        self.table = table
        super.init()
        setViewBlock {
            DetailTableScrollView(
                table: table,
                onImageTapped: onImageTapped,
                onLinkTapped: onLinkTapped
            )
        }
        style.flexGrow = 1
        style.flexShrink = 1
    }

    override func calculateSizeThatFits(_ constrainedSize: CGSize) -> CGSize {
        DetailTableLayout.measure(table: table, constrainedSize: constrainedSize)
    }

    func debugTapFirstLink() {
        (view as? DetailTableScrollView)?.debugTapFirstLink()
    }
}

enum DetailContentBlockNodeFactory {
    static func makeNodes(
        from blocks: [RenderedContentBlock],
        onImageTapped: @escaping ([URL], Int) -> Void,
        onLinkTapped: @escaping (URL) -> Void,
        onTextLayoutInvalidated: @escaping () -> Void,
        imageSizeProvider: @escaping (URL) -> CGSize? = { _ in nil },
        onImageSizeResolved: @escaping (URL, CGSize) -> Void = { _, _ in },
        onImageHeightReduced: @escaping () -> Void = {}
    ) -> [ASDisplayNode] {
        let imageURLs = blocks.compactMap { block -> URL? in
            guard case .image(let imageBlock) = block else { return nil }
            return imageBlock.url
        }
        var imageIndex = 0
        return blocks.compactMap { block -> ASDisplayNode? in
            switch block {
            case .text(let attributedText):
                guard attributedText.length > 0 else { return nil }
                return DetailRichTextNode(
                    attributedText: attributedText,
                    imageSizeProvider: imageSizeProvider,
                    onImageSizeResolved: onImageSizeResolved,
                    onImageTapped: onImageTapped,
                    onLinkTapped: onLinkTapped,
                    onLayoutInvalidated: onTextLayoutInvalidated
                )
            case .table(let table):
                guard table.rows.isEmpty == false else { return nil }
                return DetailTableNode(
                    table: table,
                    onImageTapped: onImageTapped,
                    onLinkTapped: onLinkTapped
                )
            case .codeBlock(let codeBlock):
                guard codeBlock.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                    return nil
                }
                return DetailCodeBlockNode(codeBlock: codeBlock)
            case .image(let imageBlock):
                let index = imageIndex
                imageIndex += 1
                return DetailImageBlockNode(
                    imageBlock: imageBlock,
                    imageURLs: imageURLs,
                    imageIndex: index,
                    initialImageSize: imageSizeProvider(imageBlock.url) ?? .zero,
                    onImageTapped: onImageTapped,
                    onImageSizeResolved: onImageSizeResolved,
                    onImageHeightReduced: onImageHeightReduced,
                    onLayoutInvalidated: onTextLayoutInvalidated
                )
            case .imagePlaceholder(let url):
                return plainTextNode(url?.absoluteString ?? "[图片]")
            case .unsupported(let reason):
                return plainTextNode(reason)
            }
        }
    }

    private static func plainTextNode(_ text: String) -> ASTextNode? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.isEmpty == false else { return nil }

        let node = ASTextNode()
        node.maximumNumberOfLines = 0
        node.attributedText = NSAttributedString(
            string: trimmedText,
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .body),
                .foregroundColor: UIColor.secondaryLabel
            ]
        )
        return node
    }
}

final class DetailCodeBlockNode: ASDisplayNode {
    private let codeBlock: RenderedCodeBlock

    init(codeBlock: RenderedCodeBlock) {
        self.codeBlock = codeBlock
        super.init()
        setViewBlock {
            DetailCodeBlockView(codeBlock: codeBlock)
        }
        style.flexGrow = 1
        style.flexShrink = 1
    }

    override func calculateSizeThatFits(_ constrainedSize: CGSize) -> CGSize {
        DetailCodeBlockLayout.measure(codeBlock: codeBlock, constrainedSize: constrainedSize)
    }
}

final class DetailCodeBlockView: UIView {
    private let codeBlock: RenderedCodeBlock
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let codeLabel = UILabel()
    private let chromeDotsStack = UIStackView()
    private let copyButton = UIButton(type: .system)
    private var contentWidthConstraint: NSLayoutConstraint?
    private var copyResetWorkItem: DispatchWorkItem?

    init(codeBlock: RenderedCodeBlock) {
        self.codeBlock = codeBlock
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
        UIPasteboard.general.string = codeBlock.text
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

private final class DetailTableScrollView: UIScrollView {
    private let table: RenderedTableBlock
    private let tableImageURLs: [URL]
    private let onImageTapped: ([URL], Int) -> Void
    private let onLinkTapped: (URL) -> Void
    private let contentContainer = UIView()
    private let contentWidthConstraint: NSLayoutConstraint
    private var cellWidthConstraints: [[NSLayoutConstraint]] = []
    private var rowHeightConstraints: [NSLayoutConstraint] = []

    init(
        table: RenderedTableBlock,
        onImageTapped: @escaping ([URL], Int) -> Void,
        onLinkTapped: @escaping (URL) -> Void
    ) {
        self.table = table
        self.tableImageURLs = table.imageURLs
        self.onImageTapped = onImageTapped
        self.onLinkTapped = onLinkTapped
        self.contentWidthConstraint = contentContainer.widthAnchor.constraint(equalToConstant: 0)
        super.init(frame: .zero)
        configureScrollView()
        buildTable()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyTableLayout(for: bounds.width)
    }

    private func configureScrollView() {
        backgroundColor = .clear
        showsHorizontalScrollIndicator = true
        showsVerticalScrollIndicator = false
        alwaysBounceHorizontal = true
        alwaysBounceVertical = false
        bounces = true
        contentInsetAdjustmentBehavior = .never
        isDirectionalLockEnabled = true

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentContainer)
        NSLayoutConstraint.activate([
            contentContainer.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
            contentContainer.heightAnchor.constraint(equalTo: frameLayoutGuide.heightAnchor),
            contentWidthConstraint
        ])
    }

    private func buildTable() {
        let columnWidths = DetailTableLayout.columnWidths(for: table)
        let rowHeights = DetailTableLayout.rowHeights(for: table, columnWidths: columnWidths)
        contentWidthConstraint.constant = columnWidths.reduce(0, +)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: contentContainer.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])

        for (rowIndex, row) in table.rows.enumerated() {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = 0
            rowStack.alignment = .fill
            rowStack.distribution = .fill
            let rowHeightConstraint = rowStack.heightAnchor.constraint(
                equalToConstant: rowHeights[safe: rowIndex] ?? DetailTableLayout.defaultRowHeight
            )
            rowHeightConstraint.isActive = true
            rowHeightConstraints.append(rowHeightConstraint)

            var widthConstraints: [NSLayoutConstraint] = []
            for columnIndex in columnWidths.indices {
                let cell = row.cells[safe: columnIndex]
                let cellView = DetailTableCellView(
                    cell: cell,
                    columnWidth: columnWidths[columnIndex],
                    isHeader: row.isHeader || (cell?.isHeader == true),
                    tableImageURLs: tableImageURLs,
                    onImageTapped: onImageTapped,
                    onLinkTapped: onLinkTapped
                )
                let widthConstraint = cellView.widthAnchor.constraint(equalToConstant: columnWidths[columnIndex])
                widthConstraint.isActive = true
                widthConstraints.append(widthConstraint)
                rowStack.addArrangedSubview(cellView)
            }
            cellWidthConstraints.append(widthConstraints)
            stack.addArrangedSubview(rowStack)
        }
    }

    private func applyTableLayout(for viewportWidth: CGFloat) {
        let columnWidths = DetailTableLayout.columnWidths(for: table, fittingWidth: viewportWidth)
        let rowHeights = DetailTableLayout.rowHeights(for: table, columnWidths: columnWidths)
        contentWidthConstraint.constant = max(columnWidths.reduce(0, +), viewportWidth)

        for rowIndex in cellWidthConstraints.indices {
            for columnIndex in cellWidthConstraints[rowIndex].indices {
                guard let width = columnWidths[safe: columnIndex] else { continue }
                cellWidthConstraints[rowIndex][columnIndex].constant = width
            }
        }

        for rowIndex in rowHeightConstraints.indices {
            rowHeightConstraints[rowIndex].constant = rowHeights[safe: rowIndex] ?? DetailTableLayout.defaultRowHeight
        }
    }

    func debugTapFirstLink() {
        _ = contentContainer.debugTapFirstTableLink()
    }
}

private final class DetailTableCellView: UIView {
    private enum Layout {
        static let contentInsets = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
    }

    private var linkTapHandler: DetailTableLinkTapHandler?

    init(
        cell: RenderedTableBlock.Cell?,
        columnWidth: CGFloat,
        isHeader: Bool,
        tableImageURLs: [URL],
        onImageTapped: @escaping ([URL], Int) -> Void,
        onLinkTapped: @escaping (URL) -> Void
    ) {
        super.init(frame: .zero)
        backgroundColor = isHeader ? .secondarySystemBackground : .systemBackground
        layer.borderColor = UIColor.separator.cgColor
        layer.borderWidth = 1 / max(traitCollection.displayScale, 2)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 6
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        if let imageURL = cell?.imageURL {
            let imageView = DetailTableImageView(
                imageURL: imageURL,
                targetPixelWidth: max(columnWidth - Layout.contentInsets.left - Layout.contentInsets.right, 1),
                onTapped: {
                    guard let index = tableImageURLs.firstIndex(of: imageURL) else { return }
                    onImageTapped(tableImageURLs, index)
                }
            )
            imageView.heightAnchor.constraint(equalToConstant: DetailTableLayout.imageHeight).isActive = true
            stack.addArrangedSubview(imageView)
        }

        if let text = cell?.text, text.isEmpty == false {
            let label = UILabel()
            label.numberOfLines = 0
            label.lineBreakMode = .byCharWrapping
            let font = isHeader
                ? UIFont.preferredFont(forTextStyle: .subheadline).withWeight(.semibold)
                : UIFont.preferredFont(forTextStyle: .subheadline)
            let textColor = isHeader ? UIColor.label : UIColor.secondaryLabel
            if let links = cell?.links, links.isEmpty == false {
                label.attributedText = Self.attributedText(
                    text,
                    font: font,
                    textColor: textColor,
                    links: links
                )
                label.isUserInteractionEnabled = true
                let handler = DetailTableLinkTapHandler(label: label, links: links, onTapped: onLinkTapped)
                label.addGestureRecognizer(UITapGestureRecognizer(target: handler, action: #selector(DetailTableLinkTapHandler.handleTap(_:))))
                linkTapHandler = handler
            } else {
                label.font = font
                label.textColor = textColor
                label.text = text
            }
            stack.addArrangedSubview(label)
        }

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.contentInsets.left),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.contentInsets.right),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: Layout.contentInsets.top),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -Layout.contentInsets.bottom)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func attributedText(
        _ text: String,
        font: UIFont,
        textColor: UIColor,
        links: [RenderedTableBlock.Cell.Link]
    ) -> NSAttributedString {
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: textColor
            ]
        )
        for link in links where NSMaxRange(link.nsRange) <= attributed.length {
            attributed.addAttributes(NodeSeekLinkStyle.attributes(url: link.url), range: link.nsRange)
        }
        return attributed
    }
}

extension DetailTableCellView: DetailTableLinkDebugTappable {
    func debugTapFirstLink() -> Bool {
        guard let linkTapHandler else { return false }
        return linkTapHandler.debugTapFirstLink()
    }
}

private protocol DetailTableLinkDebugTappable {
    func debugTapFirstLink() -> Bool
}

private final class DetailTableLinkTapHandler: NSObject {
    private weak var label: UILabel?
    private let links: [RenderedTableBlock.Cell.Link]
    private let onTapped: (URL) -> Void

    init(
        label: UILabel,
        links: [RenderedTableBlock.Cell.Link],
        onTapped: @escaping (URL) -> Void
    ) {
        self.label = label
        self.links = links
        self.onTapped = onTapped
    }

    @objc
    func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended,
              let label,
              let link = DetailTableLinkHitTester.link(
                at: recognizer.location(in: label),
                in: label,
                links: links
              ) else {
            return
        }
        onTapped(link.url)
    }

    func debugTapFirstLink() -> Bool {
        guard let link = links.first else { return false }
        onTapped(link.url)
        return true
    }
}

private enum DetailTableLinkHitTester {
    static func link(
        at point: CGPoint,
        in label: UILabel,
        links: [RenderedTableBlock.Cell.Link]
    ) -> RenderedTableBlock.Cell.Link? {
        guard let attributedText = label.attributedText,
              attributedText.length > 0,
              label.bounds.width > 0,
              label.bounds.height > 0 else {
            return nil
        }

        let textStorage = NSTextStorage(attributedString: attributedText)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: label.bounds.size)
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = label.numberOfLines
        textContainer.lineBreakMode = label.lineBreakMode
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        let usedRect = layoutManager.usedRect(for: textContainer)
        let horizontalOffset: CGFloat
        switch label.textAlignment {
        case .center:
            horizontalOffset = (label.bounds.width - usedRect.width) * 0.5 - usedRect.minX
        case .right:
            horizontalOffset = label.bounds.width - usedRect.width - usedRect.minX
        default:
            horizontalOffset = -usedRect.minX
        }
        let offset = CGPoint(
            x: horizontalOffset,
            y: (label.bounds.height - usedRect.height) * 0.5 - usedRect.minY
        )
        let textPoint = CGPoint(x: point.x - offset.x, y: point.y - offset.y)
        let index = layoutManager.characterIndex(
            for: textPoint,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )
        return links.first { NSLocationInRange(index, $0.nsRange) }
    }
}

private final class DetailTableImageView: UIImageView {
    private let imageURL: URL
    private let targetPixelWidth: CGFloat
    private let onTapped: () -> Void
    private var loadToken: UUID?

    init(
        imageURL: URL,
        targetPixelWidth: CGFloat,
        onTapped: @escaping () -> Void
    ) {
        self.imageURL = imageURL
        self.targetPixelWidth = targetPixelWidth
        self.onTapped = onTapped
        super.init(frame: .zero)
        backgroundColor = .secondarySystemBackground
        contentMode = .scaleAspectFit
        clipsToBounds = true
        isUserInteractionEnabled = true
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        guard superview != nil else {
            loadToken = nil
            image = nil
            return
        }
        guard loadToken == nil else { return }

        let token = UUID()
        loadToken = token
        DetailImageLoader.shared.loadImageForInline(
            imageURL,
            maxPixelWidth: targetPixelWidth * max(traitCollection.displayScale, 1),
            displayScale: max(traitCollection.displayScale, 1)
        ) { [weak self] image in
            DispatchQueue.main.async {
                guard let self, self.loadToken == token else { return }
                self.image = image
            }
        }
    }

    @objc
    private func handleTap() {
        onTapped()
    }
}

enum DetailTableLayout {
    static let defaultRowHeight: CGFloat = 38
    static let imageHeight: CGFloat = 150

    private enum Layout {
        static let fallbackWidth: CGFloat = 320
        static let minColumnWidth: CGFloat = 96
        static let maxColumnWidth: CGFloat = 220
        static let imageColumnWidth: CGFloat = 220
        static let horizontalPadding: CGFloat = 24
        static let verticalPadding: CGFloat = 18
        static let estimatedCharacterWidth: CGFloat = 7.5
        static let estimatedLineHeight: CGFloat = 19
    }

    static func measure(table: RenderedTableBlock, constrainedSize: CGSize) -> CGSize {
        let width = resolvedWidth(constrainedSize.width)
        let columnWidths = columnWidths(for: table, fittingWidth: width)
        let rowHeights = rowHeights(for: table, columnWidths: columnWidths)
        let height = max(rowHeights.reduce(0, +), defaultRowHeight)
        return CGSize(width: width, height: ceil(height))
    }

    static func columnWidths(for table: RenderedTableBlock, fittingWidth width: CGFloat? = nil) -> [CGFloat] {
        let columnCount = table.rows.map(\.cells.count).max() ?? 0
        guard columnCount > 0 else { return [] }

        let naturalWidths = (0..<columnCount).map { columnIndex in
            let maxTextLength = table.rows
                .compactMap { $0.cells[safe: columnIndex]?.text.count }
                .max() ?? 0
            let estimatedWidth = CGFloat(maxTextLength) * Layout.estimatedCharacterWidth + Layout.horizontalPadding
            let containsImage = table.rows.contains { $0.cells[safe: columnIndex]?.imageURL != nil }
            let minimumWidth = containsImage ? Layout.imageColumnWidth : Layout.minColumnWidth
            return min(max(estimatedWidth, minimumWidth), Layout.maxColumnWidth)
        }
        guard let width, width.isFinite, width > 0 else { return naturalWidths }

        let naturalTotal = naturalWidths.reduce(0, +)
        guard naturalTotal > 0, naturalTotal < width else { return naturalWidths }

        let extraWidth = width - naturalTotal
        return naturalWidths.map { columnWidth in
            columnWidth + extraWidth * (columnWidth / naturalTotal)
        }
    }

    static func rowHeights(for table: RenderedTableBlock, columnWidths: [CGFloat]) -> [CGFloat] {
        table.rows.map { row in
            let estimatedHeight = row.cells.enumerated().map { columnIndex, cell in
                let textHeight = measuredTextHeight(
                    for: cell.text,
                    isHeader: row.isHeader || cell.isHeader,
                    columnWidth: columnWidths[safe: columnIndex] ?? Layout.minColumnWidth
                )
                if cell.imageURL != nil {
                    let textSpacing: CGFloat = cell.text.isEmpty ? 0 : 6
                    return imageHeight + textSpacing + textHeight + Layout.verticalPadding
                }

                return textHeight + Layout.verticalPadding
            }.max() ?? defaultRowHeight

            return ceil(max(estimatedHeight, row.isHeader ? 42 : defaultRowHeight))
        }
    }

    private static func measuredTextHeight(for text: String, isHeader: Bool, columnWidth: CGFloat) -> CGFloat {
        guard text.isEmpty == false else { return 0 }

        let usableWidth = max(columnWidth - Layout.horizontalPadding, 1)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byCharWrapping
        let font = isHeader
            ? UIFont.preferredFont(forTextStyle: .subheadline).withWeight(.semibold)
            : UIFont.preferredFont(forTextStyle: .subheadline)
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: usableWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: font,
                .paragraphStyle: paragraphStyle
            ],
            context: nil
        )
        return max(ceil(bounds.height), Layout.estimatedLineHeight)
    }

    private static func resolvedWidth(_ width: CGFloat) -> CGFloat {
        guard width.isFinite, width > 0 else { return Layout.fallbackWidth }
        return width
    }
}

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        UIFont.systemFont(ofSize: pointSize, weight: weight)
    }
}

private extension UIView {
    func debugTapFirstTableLink() -> Bool {
        if let tappable = self as? DetailTableLinkDebugTappable,
           tappable.debugTapFirstLink() {
            return true
        }
        for subview in subviews {
            if subview.debugTapFirstTableLink() {
                return true
            }
        }
        return false
    }
}

private extension RenderedTableBlock {
    var imageURLs: [URL] {
        rows.flatMap { row in
            row.cells.compactMap(\.imageURL)
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
