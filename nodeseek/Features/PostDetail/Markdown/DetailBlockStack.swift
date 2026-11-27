import UIKit

/// 原型与列表共用同一套内容块视图。排版任务只持有快照，媒体和选区属于当前视图。
final class DetailBlockStack: UIStackView {
    var renderer = DetailFloorRenderer()
    var scalesPreviewText = false
    var appearance: DetailTextAppearance?
    var voteService: NodeSeekVoteServing?
    var onLink: ((URL) -> Void)?
    var onSignatureLinks: (([DetailLinkCandidate]) -> Void)?
    /// 签名设置：文字里的链接按此放大点击区，重叠时由 onSignatureLinks 让用户选择。
    var linkTargetSize: CGSize?
    var onPhotos: (([URL], Int) -> Void)?
    var onStickerSizeChange: (() -> Void)?
    var onSizeChange: (() -> Void)?
    /// 图片尺寸由页面统一缓存：已知尺寸按最终高度占位，加载后回写。
    var imageSize: ((URL) -> CGSize?)?
    var onImageSize: ((URL, CGSize) -> Void)?
    /// 按楼层内第几个标签组读写选中栏，楼层复用重建后恢复原来的选中栏。
    var savedTab: ((Int) -> Int)?
    var onTabSelected: ((Int, Int) -> Void)?
    private var nextTabOrdinal = 0
    weak var viewport: UIView?

    /// 清空正文以便重新装入；标签组序号随之从头计数，复用后能对上之前的选中栏。
    func removeAllBlocks() {
        arrangedSubviews.forEach { $0.removeFromSuperview() }
        nextTabOrdinal = 0
    }

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
                if let size = linkTargetSize {
                    text.linkTargetSize = size
                    text.onLinkCandidates = { [weak self] in self?.onSignatureLinks?($0) }
                }
                stack.addArrangedSubview(text.accessibleContainer())
            case .quote(let children):
                append(children, to: quote(in: stack), width: DetailQuoteLayout.contentWidth(width))
            case .tabs(let sections, let firstPage):
                let rendered = RenderedMagicTabsBlock(id: "", sections: sections.map { .init(title: $0.title, blocks: Self.galleryBlocks($0.blocks)) })
                tabs(sections.map(\.title), in: stack, width: width, gallery: { try await DetailMagicTabGallery.images(in: rendered, host: $0) }, initial: { page in
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
                case .stardust(let receipt): appendLegacy([.stardust(receipt)], to: stack, width: width)
                case .vote(let id): appendLegacy([.vote(id)], to: stack, width: width)
                case .terminal(let ansi): appendLegacy([.terminal(.init(ansi: ansi))], to: stack, width: width)
                case .code(_, let text): appendLegacy([.codeBlock(.init(text: text))], to: stack, width: width)
                case .table(let rows): appendLegacy([.table(Self.table(rows))], to: stack, width: width)
                case .brokenImage(let alt):
                    let placeholder = DetailImagePlaceholderView()
                    placeholder.showFailure(true)
                    if !alt.isEmpty { placeholder.accessibilityValue = alt }
                    // 与加载失败的图片同尺寸，靠左排列。
                    let size = DetailImagePlaceholderView.failureSize(maxWidth: width)
                    let row = UIView()
                    row.addSubview(placeholder)
                    placeholder.frame = CGRect(origin: .zero, size: size)
                    attach(row, to: stack, height: size.height)
                case .divider:
                    let line = UIView()
                    line.backgroundColor = .separator
                    attach(line, to: stack, height: 1)
                default: assertionFailure("Unexpected text block")
                }
            }
        }
    }

    private static func table(_ rows: [[DetailDocument.TableCell]]) -> RenderedTableBlock {
        .init(rows: rows.enumerated().map { row, cells in
            .init(cells: cells.map { cell in
                switch cell {
                case .image(let url):
                    return .init(text: "", imageURL: url, isHeader: row == 0)
                case .inline(let runs):
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
                }
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
        /// 生成跨标签图集（含终端报告截图），规则同预览使用的 `DetailMagicTabGallery`。
        var gallery: ((UIView) async throws -> [DetailMagicTabGallery.Image])?
        var galleryTask: Task<Void, Never>?
        deinit { layoutTask?.cancel(); galleryTask?.cancel() }
    }

    private static func tabPage(containing view: UIView?) -> TabPage? {
        var current = view
        while let view = current {
            if let page = view as? TabPage { return page }
            current = view.superview
        }
        return nil
    }

    /// 文字标签条：选中项加粗、加下划线，其余用次级文字色。
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
                // 按文字自身宽度排列，不被栈视图拉伸。
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

    /// 标签页内容区高度以第一栏为准，较长的栏在区内滚动，切换时楼层高度不变；
    /// 新栏排好后才替换旧栏，避免切换瞬间出现空白。只保留当前栏，未选中的栏不占用正文位图。
    private func tabs(_ titles: [String], in parent: UIStackView, width: CGFloat,
                      gallery: ((UIView) async throws -> [DetailMagicTabGallery.Image])? = nil, initial: ((TabPage) -> Void)? = nil,
                      show: @escaping (Int, TabPage, @escaping () -> Void) -> Void) {
        guard !titles.isEmpty else { return }
        let ordinal = nextTabOrdinal
        nextTabOrdinal += 1
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
                    // 恢复选中栏时第一栏可能还没布局，按内容宽度先量出高度。
                    let measured = current.bounds.height > 0 ? current.bounds.height : current.systemLayoutSizeFitting(
                        CGSize(width: max(1, width), height: UIView.layoutFittingCompressedSize.height),
                        withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
                    frozen.constant = max(44, ceil(measured))
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
            self?.onTabSelected?(ordinal, index)
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
        if let saved = savedTab?(ordinal), saved != 0, titles.indices.contains(saved) {
            strip.onSelect?(saved)
        }
    }

    /// 点图统一入口：标签内的图打开跨标签图集，其余用调用方给出的图集和点中那张的位置。
    /// 同一张图可能在楼里出现多次，位置按点中的视图算，不按地址查。
    private func openPhoto(_ url: URL, in view: UIView?, gallery: () -> (urls: [URL], index: Int?)) {
        if let page = Self.tabPage(containing: view) { openTabGallery(page, tapped: url); return }
        let (urls, index) = gallery()
        guard let index, urls.indices.contains(index) else { onPhotos?([url], 0); return }
        onPhotos?(urls, index)
    }

    /// 整楼图片（含引用内，不含标签页）组成图集。
    private func floorImages() -> [DetailImageBlockView] {
        var images: [DetailImageBlockView] = []
        func visit(_ view: UIView) {
            if view is TabPage { return }
            if let image = view as? DetailImageBlockView { images.append(image); return }
            view.subviews.forEach(visit)
        }
        visit(self)
        return images
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
            case .paragraph, .heading, .code, .stardust, .vote, .divider, .brokenImage: return []
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

    #if DEBUG
    func appendMarkdownFallbackNotice(for source: DetailFloorSource) {
        let hasSource = source.visibleMarkdown?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let label = UILabel()
        label.text = DetailListStrings.text(hasSource ? "debug-markdown-unsupported" : "debug-markdown-unavailable")
        label.font = .preferredFont(forTextStyle: .caption1)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .systemRed
        label.numberOfLines = 0
        label.accessibilityIdentifier = "detail-markdown-fallback"
        addArrangedSubview(label)
    }
    #endif

    private func previewText(_ text: NSAttributedString) -> NSAttributedString {
        let scaled = NSMutableAttributedString(attributedString: text)
        let metrics = UIFontMetrics(forTextStyle: .body)
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            let font = value as? UIFont ?? AppTypography.commentBodyFont()
            scaled.addAttribute(.font, value: metrics.scaledFont(for: font, compatibleWith: traitCollection), range: range)
        }
        return scaled
    }

    func appendLegacy(_ blocks: [RenderedContentBlock], to stack: UIStackView, width: CGFloat) {
        let size = CGSize(width: max(1, width), height: .greatestFiniteMagnitude)
        let open: (URL) -> Void = { [weak self] in self?.onLink?($0) }
        let photos: ([URL], Int) -> Void = { [weak self, weak stack] urls, index in
            guard urls.indices.contains(index) else { return }
            self?.openPhoto(urls[index], in: stack) { (urls, index) }
        }
        for block in blocks {
            switch block {
            case .text(let text):
                let rich = DetailRichTextView(frame: CGRect(origin: .zero, size: CGSize(width: width, height: 1)))
                rich.configure(scalesPreviewText ? previewText(text) : text, onImageTapped: photos, onLinkTapped: open, onSignatureLinkCandidatesTapped: onSignatureLinks, onLayoutInvalidated: { [weak self, weak rich] in rich?.invalidateIntrinsicContentSize(); self?.onSizeChange?() })
                stack.addArrangedSubview(rich)
            case .quote(let children): appendLegacy(children.children, to: quote(in: stack), width: DetailQuoteLayout.contentWidth(width))
            case .tabs(let content):
                tabs(content.sections.map(\.title), in: stack, width: width, gallery: { try await DetailMagicTabGallery.images(in: content, host: $0) }) { [weak self] index, page, ready in
                    self?.appendLegacy(content.sections[index].blocks, to: page, width: width)
                    ready()
                }
            case .table(let table):
                attach(DetailTableScrollView(table: table, onImageTapped: photos, onLinkTapped: open), to: stack,
                       height: DetailTableLayout.measure(table: table, constrainedSize: size).height)
            case .codeBlock(let code):
                attach(DetailCodeBlockView(codeBlock: code), to: stack, height: DetailCodeBlockLayout.measure(codeBlock: code, constrainedSize: size).height)
            case .stardust(let receipt):
                stack.addArrangedSubview(DetailStardustView(receipt: receipt, open: open))
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
                weak var tapped: DetailImageBlockView?
                // 标签内的图按报告图展示，点开后图集跨所有标签。
                let inTab = Self.tabPage(containing: stack) != nil
                let kind: DetailImageKind = inTab ? .report : DetailImageKind.resolved(isSticker: false, imageURL: image.url)
                let view = DetailImageBlockView(imageBlock: image, imageKind: kind, onImageLoaded: { [weak self] original, resolved in
                    self?.onImageSize?(image.url, original)
                    height?.constant = DetailImageLayout.presentation(for: original, maxWidth: width, kind: resolved ?? kind).size.height
                    self?.onSizeChange?()
                }, onImageFailed: { [weak self] in
                    height?.constant = DetailImagePlaceholderView.failureSize(maxWidth: width).height
                    self?.onSizeChange?()
                }, onImageTapped: { [weak self, weak stack] in
                    guard let self else { return }
                    self.openPhoto(image.url, in: stack) {
                        let images = self.floorImages()
                        return (images.map(\.url), images.firstIndex { $0 === tapped })
                    }
                })
                tapped = view
                // 同一进程内加载过的图按已知尺寸占位，复用或重新进入时不再先缩后撑。
                let placeholder = imageSize?(image.url).map { DetailImageLayout.presentation(for: $0, maxWidth: width, kind: kind).size }
                    ?? (kind == .report ? DetailImageLayout.reportPlaceholderSize(maxWidth: width) : DetailImageLayout.normalPlaceholderSize(maxWidth: width))
                // 正文图片可被读屏点按，E2E 按地址定位。
                view.isAccessibilityElement = true
                view.accessibilityTraits = [.image, .button]
                view.accessibilityLabel = image.altText.flatMap { $0.isEmpty ? nil : $0 } ?? DetailListStrings.text("image")
                view.accessibilityValue = image.url.absoluteString
                view.accessibilityIdentifier = "detail-content-image"
                height = attach(view, to: stack, height: placeholder.height)
            case .iframeLink(let link):
                // 嵌入内容显示为带标题和来源的卡片。
                attach(DetailIFrameLinkView(iframeBlock: link) { open(link.openURL) }, to: stack,
                       height: DetailIFrameLinkLayout.measure(iframeBlock: link, constrainedSize: size).height)
            case .imagePlaceholder(let url): appendLegacy([.text(NSAttributedString(string: url?.absoluteString ?? "🖼"))], to: stack, width: width)
            case .unsupported(let reason): appendLegacy([.text(NSAttributedString(string: reason))], to: stack, width: width)
            }
        }
    }
}
