#if DEBUG
import UIKit
import SafariServices

final class DetailMarkdownPrototypeController: UIViewController, UIScrollViewDelegate {
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let source: DetailFloorSource
    private let floorID: String
    private var version = 0
    private var appearance: DetailTextAppearance?
    private var task: Task<Void, Never>?
    private var photoPresenter: DetailPhotoBrowserPresenter?
    private let renderer: DetailFloorRenderer
    private let voteService: NodeSeekVoteServing?
    private(set) var copyText: String?
    private(set) var installedRequest: DetailFloorRequest?

    init(id: String, source: DetailFloorSource, voteService: NodeSeekVoteServing? = nil, renderer: DetailFloorRenderer = .init()) {
        self.renderer = renderer
        self.floorID = id
        self.source = source
        self.voteService = voteService
        super.init(nibName: nil, bundle: nil)
    }

    static func demo() -> DetailMarkdownPrototypeController {
        let line = "文字选择 👨‍👩‍👧‍👦 e\u{301} שלום مرحبا :xhj003: [NodeSeek](https://www.nodeseek.com)"
        let text = [line, String(repeating: line + "\n", count: 30)].joined(separator: "\n\n")
        return .init(id: "TextKit", source: .init(html: "", visibleMarkdown: text))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { task?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "TextKit"
        view.backgroundColor = .systemBackground
        scroll.delegate = self
        view.addSubview(scroll)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 8
        scroll.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -16),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -32)
        ])
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "doc.on.doc"), style: .plain, target: self, action: #selector(showCopy))
        navigationItem.rightBarButtonItem?.accessibilityLabel = NSLocalizedString("copy", tableName: "DetailPrototype", comment: "")
        navigationItem.rightBarButtonItem?.isEnabled = false
        NotificationCenter.default.addObserver(self, selector: #selector(invalidate), name: AppTextSizeSettings.didChangeNotification, object: nil)
    }

    @objc private func showCopy() {
        if let copyText { present(CommentCopySheetViewController(text: copyText), animated: true) }
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        viewIfLoaded?.setNeedsLayout()
    }

    @objc private func invalidate() { appearance = nil; view.setNeedsLayout() }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = scroll.bounds.width - 32
        guard width > 0 else { return }
        let font = UIFontMetrics(forTextStyle: .body).scaledFont(for: AppTypography.commentBodyFont(), compatibleWith: traitCollection)
        let next = DetailTextAppearance(width: width, pointSize: font.pointSize, scale: traitCollection.displayScale, dark: traitCollection.userInterfaceStyle == .dark)
        guard next != appearance else { updatePlayback(); return }
        appearance = next
        version += 1
        let request = DetailFloorRequest(id: floorID, version: version, source: source, appearance: next, baseURL: NodeSeekSite.baseURL)
        task?.cancel()
        // 保存显式主 actor 方法引用，同时避免任务持有整个页面。
        let receiver = WeakReceiver(self)
        task = renderer.start(request, deliver: receiver.install)
    }

    private final class WeakReceiver {
        weak var page: DetailMarkdownPrototypeController?
        init(_ page: DetailMarkdownPrototypeController) { self.page = page }
        func install(_ request: DetailFloorRequest, _ layout: sending DetailFloorLayout) { page?.install(request, layout) }
    }

    func install(_ request: DetailFloorRequest, _ layout: sending DetailFloorLayout) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard request.version == version, request.id == floorID, request.appearance == appearance else { return }
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        installedRequest = request
        copyText = request.source.visibleMarkdown
        let width = request.appearance.width
        switch layout {
        case .native(let blocks):
            append(blocks, to: stack, width: width)
        case .webpage(let blocks):
            copyText = copyText ?? CommentCopyTextFormatter.plainText(from: blocks, includingStickerCodes: true)
            appendLegacy(blocks, to: stack, width: width)
        }
        navigationItem.rightBarButtonItem?.isEnabled = copyText?.isEmpty == false
        view.setNeedsLayout()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) { updatePlayback() }
    private func updatePlayback() {
        func visit(_ view: UIView) {
            switch view {
            case let text as DetailSelectableTextView: text.updatePlayback(in: scroll)
            case let image as DetailImageBlockView: image.setPlaybackVisible(scroll.bounds.intersects(image.convert(image.bounds, to: scroll)))
            case let rich as DetailRichTextView: rich.setPlaybackVisible(scroll.bounds.intersects(rich.convert(rich.bounds, to: scroll)))
            default: view.subviews.forEach(visit)
            }
        }
        visit(stack)
    }

    private func open(_ url: URL) {
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return }
        present(SFSafariViewController(url: url), animated: true)
    }
    private func photos(_ urls: [URL], _ index: Int) {
        guard urls.indices.contains(index) else { return }
        let presenter = DetailPhotoBrowserPresenter(imageURLs: urls)
        photoPresenter = presenter
        presenter.present(from: self, initialIndex: index)
    }
    private func append(_ blocks: [DetailLayoutBlock], to stack: UIStackView, width: CGFloat) {
        for block in blocks {
            switch block {
            case .text(let snapshot):
                let text = DetailSelectableTextView(snapshot: snapshot, scale: traitCollection.displayScale,
                    onLink: { [weak self] in self?.open($0) }, stickerSizeChanged: { [weak self] in self?.invalidate() })
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
                        self.updatePlayback()
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
        control.addAction(UIAction { [weak page, weak control] _ in
            guard let page, let index = control?.selectedSegmentIndex, titles.indices.contains(index) else { return }
            page.layoutTask?.cancel()
            page.arrangedSubviews.forEach { $0.removeFromSuperview() }
            show(index, page)
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

    private func appendLegacy(_ blocks: [RenderedContentBlock], to stack: UIStackView, width: CGFloat) {
        let size = CGSize(width: max(1, width), height: .greatestFiniteMagnitude)
        let open: (URL) -> Void = { [weak self] in self?.open($0) }
        let photos: ([URL], Int) -> Void = { [weak self] in self?.photos($0, $1) }
        for block in blocks {
            switch block {
            case .text(let text):
                let rich = DetailRichTextView(frame: CGRect(origin: .zero, size: CGSize(width: width, height: 1)))
                rich.configure(text, onImageTapped: photos, onLinkTapped: open, onLayoutInvalidated: { [weak rich] in rich?.invalidateIntrinsicContentSize() })
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
                let view = DetailVoteView(id: id, service: voteService) { height?.constant = $0 }
                height = attach(view, to: stack, height: 65)
            case .terminal(let terminal):
                weak var height: NSLayoutConstraint?
                let view = DetailTerminalView(terminal: terminal, onImageTapped: photos) { original in
                    height?.constant = DetailImageLayout.presentation(for: original, maxWidth: width, kind: .report).size.height
                }
                height = attach(view, to: stack, height: DetailImageLayout.reportPlaceholderSize(maxWidth: width).height)
            case .image(let image):
                weak var height: NSLayoutConstraint?
                let view = DetailImageBlockView(imageBlock: image, imageKind: .normal, onImageLoaded: { original, kind in
                    height?.constant = DetailImageLayout.presentation(for: original, maxWidth: width, kind: kind ?? .normal).size.height
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
#endif
