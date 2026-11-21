import UIKit

/// 原型与列表共用同一套内容块视图。排版任务只持有快照，媒体和选区属于当前视图。
final class DetailBlockStack: UIStackView {
    var renderer = DetailFloorRenderer()
    var appearance: DetailTextAppearance?
    var voteService: NodeSeekVoteServing?
    var onLink: ((URL) -> Void)?
    var onSignatureLinks: (([DetailLinkCandidate]) -> Void)?
    var onPhotos: (([URL], Int) -> Void)?
    var onStickerSizeChange: (() -> Void)?
    var onSizeChange: (() -> Void)?
    weak var viewport: UIView?

    func refreshPlayback() {
        guard let viewport else { return }
        func visit(_ view: UIView) {
            switch view {
            case let text as DetailSelectableTextView: text.updatePlayback(in: viewport)
            case let image as DetailImageBlockView: image.setPlaybackVisible(viewport.bounds.intersects(image.convert(image.bounds, to: viewport)))
            case let rich as DetailRichTextView: rich.setPlaybackVisible(viewport.bounds.intersects(rich.convert(rich.bounds, to: viewport)))
            default: view.subviews.forEach(visit)
            }
        }
        visit(self)
    }

    func append(_ blocks: [DetailLayoutBlock], to stack: UIStackView, width: CGFloat) {
        for block in blocks {
            switch block {
            case .text(let snapshot):
                let text = DetailSelectableTextView(snapshot: snapshot, scale: traitCollection.displayScale,
                    onLink: { [weak self] in self?.onLink?($0) }, stickerSizeChanged: { [weak self] in self?.onStickerSizeChange?() })
                stack.addArrangedSubview(text.accessibleContainer())
            case .quote(let children):
                append(children, to: quote(in: stack), width: DetailQuoteLayout.contentWidth(width))
            case .tabs(let sections, let firstPage):
                tabs(sections.map(\.title), in: stack, initial: { page in
                    self.append(firstPage, to: page, width: width)
                }) { [weak self] index, page, ready in
                    guard let self, let appearance = self.appearance else { return }
                    page.layoutTask = self.renderer.startTab(sections[index], appearance: appearance, width: width) { [weak self, weak page] blocks in
                        guard !Task.isCancelled, let self, let page else { return }
                        self.append(blocks, to: page, width: width)
                        ready()
                        self.refreshPlayback()
                    }
                }
            case .widget(let block):
                switch block {
                case let .image(alt, url): appendLegacy([.image(.init(url: url, altText: alt))], to: stack, width: width)
                case .vote(let id): appendLegacy([.vote(id)], to: stack, width: width)
                case .terminal(let ansi): appendLegacy([.terminal(.init(ansi: ansi))], to: stack, width: width)
                case .code(_, let text): appendLegacy([.codeBlock(.init(text: text))], to: stack, width: width)
                case .table(let rows): appendLegacy([.table(Self.table(rows))], to: stack, width: width)
                case .divider:
                    let line = UIView()
                    line.backgroundColor = .separator
                    attach(line, to: stack, height: 1)
                default: assertionFailure("Unexpected text block")
                }
            }
        }
    }

    private static func table(_ rows: [[[DetailDocument.Inline]]]) -> RenderedTableBlock {
        .init(rows: rows.enumerated().map { row, cells in
            .init(cells: cells.map { runs in
                var string = ""
                var links: [RenderedTableBlock.Cell.Link] = []
                var image: URL?
                for run in runs {
                    switch run {
                    case let .text(text, _, url):
                        if let url { links.append(.init(location: string.utf16.count, length: text.utf16.count, url: url)) }
                        string += text
                    case .sticker(_, let url): image = url
                    }
                }
                return .init(text: string, links: links, imageURL: image, isHeader: row == 0)
            }, isHeader: row == 0)
        })
    }

    private func quote(in parent: UIStackView) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = DetailQuoteLayout.blockSpacing
        stack.isLayoutMarginsRelativeArrangement = true
        let inset = DetailQuoteLayout.insets
        stack.directionalLayoutMargins = .init(top: inset.top, leading: DetailQuoteLayout.borderWidth + inset.left, bottom: inset.bottom, trailing: inset.right)
        stack.layer.cornerRadius = DetailQuoteLayout.cornerRadius
        stack.clipsToBounds = true
        let border = UIView()
        border.backgroundColor = .separator
        border.isUserInteractionEnabled = false
        border.translatesAutoresizingMaskIntoConstraints = false
        stack.addSubview(border)
        NSLayoutConstraint.activate([
            border.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            border.topAnchor.constraint(equalTo: stack.topAnchor),
            border.bottomAnchor.constraint(equalTo: stack.bottomAnchor),
            border.widthAnchor.constraint(equalToConstant: DetailQuoteLayout.borderWidth)
        ])
        stack.backgroundColor = .secondarySystemBackground
        parent.addArrangedSubview(stack)
        return stack
    }

    private final class TabPage: UIStackView {
        var layoutTask: Task<Void, Never>?
        deinit { layoutTask?.cancel() }
    }

    /// 文字标签条，样式同 Texture 版 `DetailMagicTabsNode`：选中项加粗、加下划线，其余用次级文字色。
    private final class TabStrip: UIScrollView {
        private let row = UIStackView()
        private(set) var buttons: [UIButton] = []
        private(set) var selectedIndex = 0
        var onSelect: ((Int) -> Void)?

        init(titles: [String]) {
            super.init(frame: .zero)
            showsHorizontalScrollIndicator = false
            row.spacing = 4
            row.translatesAutoresizingMaskIntoConstraints = false
            addSubview(row)
            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
                row.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
                row.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
                row.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
                row.heightAnchor.constraint(equalTo: frameLayoutGuide.heightAnchor)
            ])
            for (index, title) in titles.enumerated() {
                var config = UIButton.Configuration.plain()
                config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
                let button = UIButton(configuration: config)
                button.accessibilityIdentifier = "detail-magic-tab-\(index)"
                button.accessibilityLabel = title
                button.addAction(UIAction { [weak self] _ in self?.onSelect?(index) }, for: .touchUpInside)
                // 按文字自身宽度排列，不被栈视图拉伸，间距与 Texture 版一致。
                button.setContentHuggingPriority(.required, for: .horizontal)
                button.setContentCompressionResistancePriority(.required, for: .horizontal)
                button.titleLabel?.numberOfLines = 1
                buttons.append(button)
                row.addArrangedSubview(button)
            }
            select(0)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func select(_ index: Int) {
            selectedIndex = index
            for (offset, button) in buttons.enumerated() {
                let selected = offset == index
                button.setAttributedTitle(NSAttributedString(string: button.accessibilityLabel ?? "", attributes: [
                    .font: UIFont.systemFont(ofSize: 15, weight: selected ? .semibold : .regular),
                    .foregroundColor: selected ? UIColor.label : UIColor.secondaryLabel,
                    .underlineStyle: selected ? NSUnderlineStyle.single.rawValue : 0
                ]), for: .normal)
                button.accessibilityTraits = selected ? [.button, .selected] : [.button]
            }
        }
    }

    /// 标签页与 Texture 版一致：内容区高度以第一栏为准，较长的栏在区内滚动，切换时楼层高度不变；
    /// 新栏排好后才替换旧栏，避免切换瞬间出现空白。只保留当前栏，未选中的栏不占用正文位图。
    private func tabs(_ titles: [String], in parent: UIStackView, initial: ((TabPage) -> Void)? = nil,
                      show: @escaping (Int, TabPage, @escaping () -> Void) -> Void) {
        guard !titles.isEmpty else { return }
        let strip = TabStrip(titles: titles)
        let viewport = UIScrollView()
        viewport.accessibilityIdentifier = "detail-magic-tab-content"
        viewport.contentInsetAdjustmentBehavior = .never
        viewport.alwaysBounceVertical = false
        attach(strip, to: parent, height: 46)
        parent.addArrangedSubview(viewport)
        parent.setCustomSpacing(10, after: strip)
        // 第一栏显示时高度跟随它（图片回填也会同步）；离开第一栏时冻结为当时的高度。
        viewport.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        let frozen = viewport.heightAnchor.constraint(equalToConstant: 44)
        var followFirst: NSLayoutConstraint?
        var current: TabPage?
        var pending: TabPage?

        func install(_ page: TabPage, index: Int) {
            if let current, current !== page {
                if let followFirst, followFirst.isActive {
                    frozen.constant = max(44, ceil(current.bounds.height))
                    followFirst.isActive = false
                    frozen.isActive = true
                }
                current.layoutTask?.cancel()
                current.removeFromSuperview()
            }
            page.translatesAutoresizingMaskIntoConstraints = false
            viewport.addSubview(page)
            NSLayoutConstraint.activate([
                page.leadingAnchor.constraint(equalTo: viewport.contentLayoutGuide.leadingAnchor),
                page.trailingAnchor.constraint(equalTo: viewport.contentLayoutGuide.trailingAnchor),
                page.topAnchor.constraint(equalTo: viewport.contentLayoutGuide.topAnchor),
                page.bottomAnchor.constraint(equalTo: viewport.contentLayoutGuide.bottomAnchor),
                page.widthAnchor.constraint(equalTo: viewport.frameLayoutGuide.widthAnchor)
            ])
            if index == 0 {
                frozen.isActive = false
                let follow = viewport.heightAnchor.constraint(equalTo: page.heightAnchor)
                follow.priority = .defaultHigh
                follow.isActive = true
                followFirst = follow
            }
            viewport.contentOffset = .zero
            current = page
        }

        func makePage() -> TabPage {
            let page = TabPage()
            page.axis = .vertical
            page.spacing = 10
            return page
        }

        strip.onSelect = { [weak self, weak strip] index in
            guard let strip, titles.indices.contains(index), index != strip.selectedIndex else { return }
            strip.select(index)
            pending?.layoutTask?.cancel()
            let page = makePage()
            pending = page
            show(index, page) { [weak self, weak page] in
                guard let page, pending === page else { return }
                pending = nil
                install(page, index: index)
                self?.onSizeChange?()
            }
        }
        let first = makePage()
        install(first, index: 0)
        if let initial { initial(first) } else { show(0, first) {} }
    }

    @discardableResult
    private func attach(_ view: UIView, to stack: UIStackView, height: CGFloat) -> NSLayoutConstraint {
        stack.addArrangedSubview(view)
        let constraint = view.heightAnchor.constraint(equalToConstant: max(1, ceil(height)))
        constraint.isActive = true
        return constraint
    }

    func appendLegacy(_ blocks: [RenderedContentBlock], to stack: UIStackView, width: CGFloat) {
        let size = CGSize(width: max(1, width), height: .greatestFiniteMagnitude)
        let open: (URL) -> Void = { [weak self] in self?.onLink?($0) }
        let photos: ([URL], Int) -> Void = { [weak self] in self?.onPhotos?($0, $1) }
        for block in blocks {
            switch block {
            case .text(let text):
                let rich = DetailRichTextView(frame: CGRect(origin: .zero, size: CGSize(width: width, height: 1)))
                rich.configure(text, onImageTapped: photos, onLinkTapped: open, onSignatureLinkCandidatesTapped: onSignatureLinks, onLayoutInvalidated: { [weak self, weak rich] in rich?.invalidateIntrinsicContentSize(); self?.onSizeChange?() })
                stack.addArrangedSubview(rich)
            case .quote(let children): appendLegacy(children.children, to: quote(in: stack), width: DetailQuoteLayout.contentWidth(width))
            case .tabs(let content):
                tabs(content.sections.map(\.title), in: stack) { [weak self] index, page, ready in
                    self?.appendLegacy(content.sections[index].blocks, to: page, width: width)
                    ready()
                }
            case .table(let table):
                attach(DetailTableScrollView(table: table, onImageTapped: photos, onLinkTapped: open), to: stack,
                       height: DetailTableLayout.measure(table: table, constrainedSize: size).height)
            case .codeBlock(let code):
                attach(DetailCodeBlockView(codeBlock: code), to: stack, height: DetailCodeBlockLayout.measure(codeBlock: code, constrainedSize: size).height)
            case .vote(let id):
                weak var height: NSLayoutConstraint?
                let view = DetailVoteView(id: id, service: voteService) { [weak self] value in height?.constant = value; self?.onSizeChange?() }
                height = attach(view, to: stack, height: 65)
            case .terminal(let terminal):
                weak var height: NSLayoutConstraint?
                let view = DetailTerminalView(terminal: terminal, onImageTapped: photos) { [weak self] original in
                    height?.constant = DetailImageLayout.presentation(for: original, maxWidth: width, kind: .report).size.height
                    self?.onSizeChange?()
                }
                height = attach(view, to: stack, height: DetailImageLayout.reportPlaceholderSize(maxWidth: width).height)
            case .image(let image):
                weak var height: NSLayoutConstraint?
                let view = DetailImageBlockView(imageBlock: image, imageKind: .normal, onImageLoaded: { [weak self] original, kind in
                    height?.constant = DetailImageLayout.presentation(for: original, maxWidth: width, kind: kind ?? .normal).size.height
                    self?.onSizeChange?()
                }, onImageTapped: { photos([image.url], 0) })
                height = attach(view, to: stack, height: DetailImageLayout.normalPlaceholderSize(maxWidth: width).height)
            case .iframeLink(let link):
                let button = UIButton(type: .system)
                button.setTitle(link.displayDomain, for: .normal)
                button.addAction(UIAction { _ in open(link.openURL) }, for: .touchUpInside)
                stack.addArrangedSubview(button)
            case .imagePlaceholder(let url): appendLegacy([.text(NSAttributedString(string: url?.absoluteString ?? "🖼"))], to: stack, width: width)
            case .unsupported(let reason): appendLegacy([.text(NSAttributedString(string: reason))], to: stack, width: width)
            }
        }
    }
}
