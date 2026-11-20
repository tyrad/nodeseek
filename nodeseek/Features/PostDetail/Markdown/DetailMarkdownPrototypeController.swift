#if DEBUG
import UIKit
import SafariServices

final class DetailMarkdownPrototypeController: UIViewController, UIScrollViewDelegate {
    private let scroll = UIScrollView()
    private let stack = DetailBlockStack()
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
        stack.renderer = renderer
        stack.voteService = voteService
        stack.viewport = scroll
        stack.onLink = { [weak self] in self?.open($0) }
        stack.onPhotos = { [weak self] in self?.photos($0, $1) }
        stack.onStickerSizeChange = { [weak self] in self?.invalidate() }
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
        stack.appearance = next
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
            stack.append(blocks, to: stack, width: width)
        case .webpage(let blocks):
            copyText = copyText ?? CommentCopyTextFormatter.plainText(from: blocks, includingStickerCodes: true)
            stack.appendLegacy(blocks, to: stack, width: width)
        }
        navigationItem.rightBarButtonItem?.isEnabled = copyText?.isEmpty == false
        view.setNeedsLayout()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) { updatePlayback() }
    private func updatePlayback() {
        stack.refreshPlayback()
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
}
#endif
