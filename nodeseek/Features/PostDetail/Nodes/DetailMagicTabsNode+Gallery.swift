import AsyncDisplayKit
import DTCoreText
import UIKit

extension DetailMagicTabsNode {
    func openGallery(sectionIndex: Int, imageURLs: [URL], imageIndex: Int) {
        guard galleryTask == nil, imageURLs.indices.contains(imageIndex) else { return }
        var responder: UIResponder? = view
        while let current = responder, !(current is UIViewController) { responder = current.next }
        guard let controller = responder as? UIViewController, controller.presentedViewController == nil else { return }
        let tappedURL = imageURLs[imageIndex]
        let requestID = UUID()
        galleryRequestID = requestID
        let loading = DetailGalleryLoadingView()
        let visibleRect = controller.view.convert(controller.view.bounds, to: view).intersection(view.bounds)
        let contentRect = visibleRect.intersection(view.bounds.inset(by: UIEdgeInsets(top: 56, left: 0, bottom: 0, right: 0)))
        let placement = contentRect.isNull ? (visibleRect.isNull ? view.bounds : visibleRect) : contentRect
        loading.center = CGPoint(x: placement.midX, y: placement.midY)
        loading.onRemoved = { [weak self] in self?.cancelGalleryPreparation() }
        galleryLoadingView = loading
        view.addSubview(loading)
        galleryTask = Task { [weak self, weak controller] in
            guard let self, let controller else { return }
            defer {
                loading.onRemoved = nil
                loading.removeFromSuperview()
                if self.galleryRequestID == requestID {
                    self.galleryTask = nil
                    self.galleryRequestID = nil
                    self.galleryLoadingView = nil
                }
            }
            do {
                let entries = try await DetailMagicTabGallery.images(in: self.tabs, host: self.view)
                try Task.checkCancellation()
                var urls = entries.map(\.url)
                let initialIndex: Int
                if let index = entries.firstIndex(where: { $0.sectionIndex == sectionIndex && $0.url == tappedURL }) {
                    initialIndex = index
                } else {
                    // 非标准附件仍保留点击目标，不错误地打开同组第一张图。
                    initialIndex = urls.count
                    urls.append(tappedURL)
                }
                guard controller.viewIfLoaded?.window != nil, controller.presentedViewController == nil else { return }
                self.onImageTapped(urls, initialIndex)
            } catch {
                guard !Task.isCancelled, controller.viewIfLoaded?.window != nil, controller.presentedViewController == nil else { return }
                let alert = UIAlertController(title: "图片准备失败", message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "重试", style: .default) { [weak self, weak alert] _ in
                    alert?.dismiss(animated: false) {
                        self?.openGallery(sectionIndex: sectionIndex, imageURLs: imageURLs, imageIndex: imageIndex)
                    }
                })
                alert.addAction(UIAlertAction(title: "取消", style: .cancel))
                controller.present(alert, animated: true)
            }
        }
    }

    func cancelGalleryPreparation() {
        galleryTask?.cancel()
        galleryTask = nil
        galleryRequestID = nil
        let loading = galleryLoadingView
        galleryLoadingView = nil
        loading?.onRemoved = nil
        loading?.removeFromSuperview()
    }
}

final class DetailGalleryLoadingView: UIVisualEffectView {
    var onRemoved: (() -> Void)?

    init() {
        super.init(effect: UIBlurEffect(style: .systemMaterial))
        frame = CGRect(x: 0, y: 0, width: 56, height: 56)
        layer.cornerRadius = 12
        clipsToBounds = true
        isUserInteractionEnabled = false
        accessibilityIdentifier = "detail-gallery-loading"
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.color = .label
        spinner.center = CGPoint(x: 28, y: 28)
        contentView.addSubview(spinner)
        spinner.startAnimating()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { onRemoved?() }
    }
}

@MainActor
enum DetailMagicTabGallery {
    struct Image {
        let sectionIndex: Int
        let url: URL
    }

    static func images(in tabs: RenderedMagicTabsBlock, host: UIView) async throws -> [Image] {
        var images: [Image] = []
        for (index, section) in tabs.sections.enumerated() {
            let urls = try await imageURLs(in: section.blocks, host: host)
            images += urls.map { Image(sectionIndex: index, url: $0) }
        }
        return images
    }

    private static func imageURLs(in blocks: [RenderedContentBlock], host: UIView) async throws -> [URL] {
        var urls: [URL] = []
        for block in blocks {
            try Task.checkCancellation()
            switch block {
            case .terminal(let terminal):
                let snapshot = try await TerminalSnapshotRenderer.shared.render(terminal, in: host)
                urls += snapshot.pages.map(\.url)
            case .image(let image): urls.append(image.url)
            case .quote(let quote): urls += try await imageURLs(in: quote.children, host: host)
            case .tabs(let tabs):
                for section in tabs.sections { urls += try await imageURLs(in: section.blocks, host: host) }
            case .table(let table): urls += table.rows.flatMap { $0.cells.compactMap(\.imageURL) }
            case .text(let text):
                text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, _ in
                    guard let attachment = value as? DTImageTextAttachment,
                          !DetailAttachmentAttributes.hasClass("sticker", in: attachment.attributes),
                          let url = ImageURLResolver.resolve(attachment.contentURL) else { return }
                    urls.append(url)
                }
            case .vote, .codeBlock, .iframeLink, .imagePlaceholder, .unsupported: break
            }
        }
        return urls
    }
}
