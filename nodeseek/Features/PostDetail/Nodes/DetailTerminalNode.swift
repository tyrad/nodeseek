import AsyncDisplayKit
import ImageIO
import UIKit

final class DetailTerminalNode: ASDisplayNode {
    private let lineCount: Int
    private var loadedSize: CGSize = .zero
    private let onLayoutInvalidated: () -> Void

    init(terminal: RenderedTerminalBlock, onImageTapped: @escaping ([URL], Int) -> Void, onLayoutInvalidated: @escaping () -> Void) {
        lineCount = terminal.ansi.components(separatedBy: "\n").count
        self.onLayoutInvalidated = onLayoutInvalidated
        super.init()
        setViewBlock { [weak self] in
            DetailTerminalView(terminal: terminal, onImageTapped: onImageTapped, onImageLoaded: { size in
                guard let self, self.loadedSize != size else { return }
                self.loadedSize = size
                self.invalidateCalculatedLayout()
                self.setNeedsLayout()
                self.onLayoutInvalidated()
            })
        }
        style.flexGrow = 1
        style.flexShrink = 1
    }

    override func calculateSizeThatFits(_ constrainedSize: CGSize) -> CGSize {
        let width = constrainedSize.width.isFinite && constrainedSize.width > 0 ? constrainedSize.width : 320
        let size = loadedSize == .zero ? CGSize(width: 875, height: CGFloat(lineCount) * 21 + 32) : loadedSize
        let imageSize = DetailImageBlockLayout.measure(originalSize: size, constrainedSize: CGSize(width: width, height: .greatestFiniteMagnitude), kind: .report)
        return CGSize(width: width, height: imageSize.height)
    }
}

final class DetailTerminalView: UIView {
    private let terminal: RenderedTerminalBlock
    private let onImageTapped: ([URL], Int) -> Void
    private let onImageLoaded: (CGSize) -> Void
    private let imageView = UIImageView()
    private let openButton = UIButton(type: .custom)
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let retryButton = UIButton(type: .system)
    private var task: Task<Void, Never>?
    private(set) var snapshot: TerminalSnapshot?
    private var failed = false

    init(terminal: RenderedTerminalBlock, onImageTapped: @escaping ([URL], Int) -> Void, onImageLoaded: @escaping (CGSize) -> Void) {
        self.terminal = terminal
        self.onImageTapped = onImageTapped
        self.onImageLoaded = onImageLoaded
        super.init(frame: .zero)
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 8
        clipsToBounds = true
        imageView.contentMode = .scaleAspectFit
        imageView.accessibilityIdentifier = "detail-terminal-image"
        openButton.accessibilityIdentifier = "detail-terminal-open-report"
        openButton.accessibilityLabel = "放大图片"
        openButton.isEnabled = false
        openButton.addTarget(self, action: #selector(openReport), for: .touchUpInside)
        statusLabel.font = .preferredFont(forTextStyle: .caption1)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 2
        statusLabel.isAccessibilityElement = false
        statusLabel.text = "正在生成报告图片…"
        retryButton.setTitle("重试", for: .normal)
        retryButton.isHidden = true
        retryButton.addTarget(self, action: #selector(retry), for: .touchUpInside)
        [imageView, statusLabel, spinner, openButton, retryButton].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        openButton.frame = bounds
        imageView.frame = bounds
        statusLabel.frame = CGRect(x: 12, y: max(0, bounds.height - 42), width: max(0, bounds.width - 24), height: 40)
        spinner.center = imageView.center
        retryButton.frame = CGRect(x: (bounds.width - 80) / 2, y: max(0, imageView.bounds.midY - 22), width: 80, height: 44)
        startIfNeeded()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { task?.cancel(); task = nil }
        else { startIfNeeded() }
    }

    private func startIfNeeded() {
        guard window != nil, bounds.width > 0, task == nil, snapshot == nil, !failed else { return }
        spinner.startAnimating()
        task = Task { [weak self, terminal] in
            guard let host = self else { return }
            do {
                let result = try await TerminalSnapshotRenderer.shared.render(terminal, in: host)
                try Task.checkCancellation()
                guard let first = result.pages.first else { return }
                let previewWidth = max(host.bounds.width * host.traitCollection.displayScale, 640)
                let previewLongestSide = min(2048, previewWidth * max(1, first.height / first.width))
                guard let image = Self.thumbnail(first.url, pixelWidth: previewLongestSide) else {
                    throw TerminalSnapshotRenderer.SnapshotError.invalidOutput
                }
                host.snapshot = result
                host.imageView.image = image
                host.openButton.isEnabled = true
                host.statusLabel.text = nil
                host.onImageLoaded(CGSize(width: first.width, height: first.height))
                host.spinner.stopAnimating()
                host.task = nil
            } catch is CancellationError {
                // 离屏或切栏时取消等待，重新出现后按需读取缓存或重新生成。
            } catch {
                guard !Task.isCancelled else { return }
                host.failed = true
                host.statusLabel.text = error.localizedDescription
                host.retryButton.isHidden = false
                host.spinner.stopAnimating()
                host.task = nil
            }
        }
    }

    private static func thumbnail(_ url: URL, pixelWidth: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(pixelWidth),
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    @objc private func retry() {
        failed = false
        retryButton.isHidden = true
        statusLabel.text = "正在生成报告图片…"
        startIfNeeded()
    }

    @objc private func openReport() {
        guard let snapshot else { return }
        onImageTapped(snapshot.pages.map(\.url), 0)
    }
}
