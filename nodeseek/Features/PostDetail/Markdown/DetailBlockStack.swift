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
                append(children, to: quote(in: stack), width: width-12)
            case .tabs(let sections, let firstPage):
                tabs(sections.map(\.title), in: stack, initial: { page in
                    self.append(firstPage, to: page, width: width)
                }) { [weak self] index, page in
                    guard let self, let appearance = self.appearance else { return }
                    page.layoutTask = self.renderer.startTab(sections[index], appearance: appearance, width: width) { [weak self, weak page] blocks in
                        guard !Task.isCancelled, let self, let page else { return }
                        self.append(blocks, to: page, width: width)
                        self.refreshPlayback()
                        self.onSizeChange?()
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
        stack.spacing = 6
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = .init(top: 4, leading: 12, bottom: 4, trailing: 0)
        stack.backgroundColor = .secondarySystemBackground
        parent.addArrangedSubview(stack)
        return stack
    }

    private final class TabPage: UIStackView {
        var layoutTask: Task<Void, Never>?
        deinit { layoutTask?.cancel() }
    }

    private func tabs(_ titles: [String], in parent: UIStackView, initial: ((TabPage) -> Void)? = nil,
                      show: @escaping (Int, TabPage) -> Void) {
        guard !titles.isEmpty else { return }
        let page = TabPage()
        page.accessibilityIdentifier = "detail-magic-tab-content"
        page.axis = .vertical
        page.spacing = 8
        let scroller = UIScrollView()
        scroller.showsHorizontalScrollIndicator = false
        let control = UISegmentedControl(items: titles)
        control.apportionsSegmentWidthsByContent = true
        control.selectedSegmentIndex = 0
        let font = UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: traitCollection)
        control.setTitleTextAttributes([.font: font], for: .normal)
        scroller.addSubview(control)
        control.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: scroller.contentLayoutGuide.leadingAnchor),
            control.trailingAnchor.constraint(equalTo: scroller.contentLayoutGuide.trailingAnchor),
            control.topAnchor.constraint(equalTo: scroller.contentLayoutGuide.topAnchor),
            control.bottomAnchor.constraint(equalTo: scroller.contentLayoutGuide.bottomAnchor),
            control.heightAnchor.constraint(equalTo: scroller.frameLayoutGuide.heightAnchor)
        ])
        control.addAction(UIAction { [weak self, weak page, weak control] _ in
            guard let page, let index = control?.selectedSegmentIndex, titles.indices.contains(index) else { return }
            page.layoutTask?.cancel()
            page.arrangedSubviews.forEach { $0.removeFromSuperview() }
            show(index, page)
            self?.onSizeChange?()
        }, for: .valueChanged)
        attach(scroller, to: parent, height: max(44, font.lineHeight + 16))
        parent.addArrangedSubview(page)
        if let initial { initial(page) } else { show(0, page) }
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
            case .quote(let children): appendLegacy(children.children, to: quote(in: stack), width: width-12)
            case .tabs(let content):
                tabs(content.sections.map(\.title), in: stack) { [weak self] index, page in
                    self?.appendLegacy(content.sections[index].blocks, to: page, width: width)
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
