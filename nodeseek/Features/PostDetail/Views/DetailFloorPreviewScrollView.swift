import UIKit

/// 两种单楼预览复用正式详情的楼层头部和内容块。滚动范围随异步媒体的实际高度变化。
final class DetailFloorPreviewScrollView: UIScrollView, UIScrollViewDelegate {
    let floor = DetailFloorListCell(frame: .zero)
    private var imageSizes: [URL: CGSize] = [:]
    private var tabs: [Int: Int] = [:]
    private var needsMeasurement = true
    private var renderedWidth: CGFloat = 0
    typealias Delivery = @MainActor @Sendable (sending [RenderedContentBlock]?) -> Void
    typealias Loader = (CGFloat, UITraitCollection, @escaping Delivery) -> Task<Void, Never>?
    private var loading: Task<Void, Never>?
    private var generation = 0
    var onMeasuredHeight: ((CGFloat) -> Void)?
    var loadContent: Loader? {
        didSet { invalidateContent() }
    }

    static func background(_ render: @escaping @Sendable (CGFloat) -> [RenderedContentBlock]?) -> Loader {
        { width, traits, deliver in
            Task.detached(priority: .userInitiated) {
                guard !Task.isCancelled else { return }
                var blocks: [RenderedContentBlock]?
                traits.performAsCurrent { blocks = render(width) }
                guard !Task.isCancelled else { return }
                await deliver(blocks)
            }
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil, loading != nil { invalidateContent() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        backgroundColor = .systemBackground
        floor.body.scalesPreviewText = true
        floor.body.viewport = self
        floor.body.imageSize = { [weak self] in self?.imageSizes[$0] }
        floor.body.onImageSize = { [weak self] url, size in self?.imageSizes[url] = size }
        floor.body.savedTab = { [weak self] in self?.tabs[$0] ?? 0 }
        floor.body.onTabSelected = { [weak self] ordinal, index in self?.tabs[ordinal] = index }
        floor.body.onSizeChange = { [weak self] in
            self?.needsMeasurement = true
            self?.setNeedsLayout()
        }
        addSubview(floor)
        NotificationCenter.default.addObserver(self, selector: #selector(invalidateContent),
                                               name: AppTextSizeSettings.didChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc func invalidateContent() {
        loading?.cancel()
        generation += 1
        renderedWidth = 0
        setNeedsLayout()
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previous)
            || traitCollection.preferredContentSizeCategory != previous?.preferredContentSizeCategory {
            invalidateContent()
        }
    }

    var configureHeader: ((DetailFloorListCell) -> Void)?

    func refreshHeader() {
        configureHeader?(floor)
        needsMeasurement = true
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        let bodyWidth = width - PostDetailContentLayout.horizontalInset * 2 - floor.textIndent
        guard bodyWidth > 0 else { return }
        if renderedWidth != width {
            renderedWidth = width
            needsMeasurement = true
            floor.frame.size.width = width
            floor.layoutIfNeeded()
            configureHeader?(floor)
            loading?.cancel()
            generation += 1
            let version = generation
            loading = loadContent?(bodyWidth, traitCollection) { [weak self] blocks in
                guard let self, generation == version else { return }
                loading = nil
                floor.body.removeAllBlocks()
                if let blocks { floor.body.appendLegacy(blocks, to: floor.body, width: bodyWidth) }
                needsMeasurement = true
                setNeedsLayout()
            }
        }
        if needsMeasurement {
            needsMeasurement = false
            let size = CGSize(width: width, height: floor.measuredHeight(width: width))
            floor.frame = CGRect(origin: .zero, size: size)
            if contentSize != size {
                contentSize = size
                onMeasuredHeight?(size.height)
            }
        }
        floor.refreshPlayback()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) { floor.refreshPlayback() }
}
