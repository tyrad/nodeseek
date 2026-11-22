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
                let rendered = RenderedMagicTabsBlock(id: "", sections: sections.map { .init(title: $0.title, blocks: Self.galleryBlocks($0.blocks)) })
                tabs(sections.map(\.title), in: stack, gallery: { try await DetailMagicTabGallery.images(in: rendered, host: $0) }, initial: { page in
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
        var sectionIndex = 0
        /// 生成跨标签图集（含终端报告截图），与 Texture 版 `DetailMagicTabGallery` 一致。
        var gallery: ((UIView) async throws -> [DetailMagicTabGallery.Image])?
        var galleryTask: Task<Void, Never>?
        deinit { layoutTask?.cancel(); galleryTask?.cancel() }
    }

    private static var knownImageSizes: [URL: CGSize] = [:]

    static func rememberImageSize(_ size: CGSize, for url: URL) {
        guard size.width > 0, size.height > 0 else { return }
        if knownImageSizes.count > 500 { knownImageSizes.removeAll(keepingCapacity: true) }
        knownImageSizes[url] = size
    }

    private static func tabPage(containing view: UIView?) -> TabPage? {
        var current = view
        while let view = current {
            if let page = view as? TabPage { return page }
            current = view.superview
        }
        return nil
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
    private func tabs(_ titles: [String], in parent: UIStackView,
                      gallery: ((UIView) async throws -> [DetailMagicTabGallery.Image])? = nil, initial: ((TabPage) -> Void)? = nil,
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

        func makePage(_ index: Int) -> TabPage {
            let page = TabPage()
            page.axis = .vertical
            page.spacing = 10
            page.sectionIndex = index
            page.gallery = gallery
            return page
        }

        strip.onSelect = { [weak self, weak strip] index in
            guard let strip, titles.indices.contains(index), index != strip.selectedIndex else { return }
            strip.select(index)
            pending?.layoutTask?.cancel()
            let page = makePage(index)
            pending = page
            show(index, page) { [weak self, weak page] in
                guard let page, pending === page else { return }
                pending = nil
                install(page, index: index)
                self?.onSizeChange?()
            }
        }
        let first = makePage(0)
        install(first, index: 0)
        if let initial { initial(first) } else { show(0, first) {} }
    }

    /// 与旧版一致：点图时以整楼图片（含引用内，不含标签页）为图集，从点中的那张开始。
    private func openGallery(at url: URL) {
        var urls: [URL] = []
        func visit(_ view: UIView) {
            if view is TabPage { return }
            if let image = view as? DetailImageBlockView { urls.append(image.url); return }
            view.subviews.forEach(visit)
        }
        visit(self)
        guard let index = urls.firstIndex(of: url) else { onPhotos?([url], 0); return }
        onPhotos?(urls, index)
    }

    /// 标签内点图：先生成所有标签的图集（终端报告需截图，期间显示加载），失败时只看当前这张。
    private func openTabGallery(_ page: TabPage, tapped: URL) {
        guard let gallery = page.gallery else { onPhotos?([tapped], 0); return }
        guard page.galleryTask == nil else { return }
        let loading = DetailGalleryLoadingView()
        loading.center = CGPoint(x: page.bounds.midX, y: min(page.bounds.midY, 120))
        page.addSubview(loading)
        page.galleryTask = Task { [weak self, weak page] in
            defer { loading.removeFromSuperview(); page?.galleryTask = nil }
            guard let page else { return }
            do {
                let entries = try await gallery(page)
                try Task.checkCancellation()
                var urls = entries.map(\.url)
                let index: Int
                if let found = entries.firstIndex(where: { $0.sectionIndex == page.sectionIndex && $0.url == tapped }) {
                    index = found
                } else {
                    index = urls.count
                    urls.append(tapped)
                }
                self?.onPhotos?(urls, index)
            } catch {
                guard !Task.isCancelled else { return }
                self?.onPhotos?([tapped], 0)
            }
        }
    }

    /// 图集只关心图片和终端报告，其余块不参与。
    private static func galleryBlocks(_ blocks: [DetailDocument.Block]) -> [RenderedContentBlock] {
        blocks.flatMap { block -> [RenderedContentBlock] in
            switch block {
            case let .image(alt, url): return [.image(.init(url: url, altText: alt))]
            case .terminal(let ansi): return [.terminal(.init(ansi: ansi))]
            case .quote(let children): return [.quote(.init(children: galleryBlocks(children)))]
            case .list(_, let items): return items.flatMap(galleryBlocks)
            case .table(let rows): return [.table(table(rows))]
            case .tabs(let tabs): return [.tabs(.init(id: "", sections: tabs.map { .init(title: $0.title, blocks: galleryBlocks($0.blocks)) }))]
            case .paragraph, .heading, .code, .vote, .divider: return []
            }
        }
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
        let photos: ([URL], Int) -> Void = { [weak self, weak stack] urls, index in
            if let page = Self.tabPage(containing: stack), urls.indices.contains(index) {
                self?.openTabGallery(page, tapped: urls[index])
            } else {
                self?.onPhotos?(urls, index)
            }
        }
        for block in blocks {
            switch block {
            case .text(let text):
                let rich = DetailRichTextView(frame: CGRect(origin: .zero, size: CGSize(width: width, height: 1)))
                rich.configure(text, onImageTapped: photos, onLinkTapped: open, onSignatureLinkCandidatesTapped: onSignatureLinks, onLayoutInvalidated: { [weak self, weak rich] in rich?.invalidateIntrinsicContentSize(); self?.onSizeChange?() })
                stack.addArrangedSubview(rich)
            case .quote(let children): appendLegacy(children.children, to: quote(in: stack), width: DetailQuoteLayout.contentWidth(width))
            case .tabs(let content):
                tabs(content.sections.map(\.title), in: stack, gallery: { try await DetailMagicTabGallery.images(in: content, host: $0) }) { [weak self] index, page, ready in
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
                // 与旧版一致：标签内的图按报告图展示，点开后图集跨所有标签。
                let inTab = Self.tabPage(containing: stack) != nil
                let kind: DetailImageKind = inTab ? .report : DetailImageKind.resolved(isSticker: false, imageURL: image.url)
                let view = DetailImageBlockView(imageBlock: image, imageKind: kind, onImageLoaded: { [weak self] original, resolved in
                    Self.rememberImageSize(original, for: image.url)
                    height?.constant = DetailImageLayout.presentation(for: original, maxWidth: width, kind: resolved ?? kind).size.height
                    self?.onSizeChange?()
                }, onImageTapped: { [weak self, weak stack] in
                    if let page = Self.tabPage(containing: stack) { self?.openTabGallery(page, tapped: image.url) } else { self?.openGallery(at: image.url) }
                })
                // 与旧版一致：同一进程内加载过的图按已知尺寸占位，复用或重新进入时不再先缩后撑。
                let placeholder = Self.knownImageSizes[image.url].map { DetailImageLayout.presentation(for: $0, maxWidth: width, kind: kind).size }
                    ?? (kind == .report ? DetailImageLayout.reportPlaceholderSize(maxWidth: width) : DetailImageLayout.normalPlaceholderSize(maxWidth: width))
                height = attach(view, to: stack, height: placeholder.height)
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
