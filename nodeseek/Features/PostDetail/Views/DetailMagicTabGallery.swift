import DTCoreText
import UIKit

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
