//
//  DetailImageBlockNode.swift
//  nodeseek
//
//  Created by Codex on 2026/4/30.
//

import AsyncDisplayKit
import UIKit

final class DetailImageBlockNode: ASDisplayNode {
    private let onLayoutInvalidated: () -> Void
    private let onImageHeightReduced: () -> Void
    private let onImageSizeResolved: (URL, CGSize) -> Void
    private let imageURL: URL
    private var imageKind: DetailImageKind
    private var loadedImageSize: CGSize
    private static let heightReductionThreshold: CGFloat = 1

    init(
        imageBlock: RenderedImageBlock,
        imageURLs: [URL],
        imageIndex: Int,
        initialImageSize: CGSize = .zero,
        onImageTapped: @escaping ([URL], Int) -> Void,
        onImageSizeResolved: @escaping (URL, CGSize) -> Void = { _, _ in },
        onImageHeightReduced: @escaping () -> Void = {},
        onLayoutInvalidated: @escaping () -> Void
    ) {
        self.onLayoutInvalidated = onLayoutInvalidated
        self.onImageHeightReduced = onImageHeightReduced
        self.onImageSizeResolved = onImageSizeResolved
        self.imageURL = imageBlock.url
        self.imageKind = DetailImageKind.resolved(isSticker: false, imageURL: imageBlock.url)
        self.loadedImageSize = initialImageSize.width > 0 && initialImageSize.height > 0 ? initialImageSize : .zero
        super.init()
        setViewBlock { [weak self] in
            DetailImageBlockView(
                imageBlock: imageBlock,
                onImageLoaded: { imageSize, resolvedKind in
                    self?.updateLoadedImageSize(imageSize, resolvedKind: resolvedKind)
                },
                onImageTapped: {
                    onImageTapped(imageURLs, imageIndex)
                }
            )
        }
        style.flexGrow = 1
        style.flexShrink = 1
    }

    override func calculateSizeThatFits(_ constrainedSize: CGSize) -> CGSize {
        DetailImageBlockLayout.measure(
            originalSize: loadedImageSize,
            constrainedSize: constrainedSize,
            kind: imageKind
        )
    }

    func updateLoadedImageSize(_ imageSize: CGSize, resolvedKind: DetailImageKind? = nil) {
        guard imageSize.width > 0, imageSize.height > 0 else { return }
        let previousSize = loadedImageSize
        let previousKind = imageKind
        if let resolvedKind {
            imageKind = resolvedKind
        }
        loadedImageSize = imageSize
        onImageSizeResolved(imageURL, imageSize)
        let previousLayout = DetailImageBlockLayout.presentationSize(
            originalSize: previousSize,
            maxWidth: calculatedSize.width,
            kind: previousKind
        )
        let nextLayout = DetailImageBlockLayout.presentationSize(
            originalSize: imageSize,
            maxWidth: calculatedSize.width,
            kind: imageKind
        )
        guard previousLayout != nextLayout else { return }
        invalidateCalculatedLayout()
        setNeedsLayout()
        if nextLayout.height < previousLayout.height - Self.heightReductionThreshold {
            onImageHeightReduced()
        } else {
            onLayoutInvalidated()
        }
    }
}

private final class DetailImageBlockView: UIView {
    private let imageBlock: RenderedImageBlock
    private let onImageLoaded: (CGSize, DetailImageKind?) -> Void
    private let onImageTapped: () -> Void
    private let imageView = UIImageView()
    private var hasStartedLoad = false
    private var resolvedImageKind: DetailImageKind

    init(
        imageBlock: RenderedImageBlock,
        onImageLoaded: @escaping (CGSize, DetailImageKind?) -> Void,
        onImageTapped: @escaping () -> Void
    ) {
        self.imageBlock = imageBlock
        self.onImageLoaded = onImageLoaded
        self.onImageTapped = onImageTapped
        self.resolvedImageKind = DetailImageKind.resolved(isSticker: false, imageURL: nil)
        super.init(frame: .zero)
        configureView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = DetailImageBlockLayout.imageFrame(
            originalSize: imageView.image?.size ?? .zero,
            bounds: bounds,
            kind: resolvedImageKind
        )
        imageView.contentMode = DetailImageBlockLayout.contentMode(
            originalSize: imageView.image?.size ?? .zero,
            maxWidth: bounds.width,
            kind: resolvedImageKind
        )
        loadImageIfNeeded()
    }

    private func configureView() {
        backgroundColor = .clear
        clipsToBounds = true
        imageView.backgroundColor = .secondarySystemBackground
        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = true
        imageView.accessibilityLabel = imageBlock.altText
        imageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        addSubview(imageView)
    }

    private func loadImageIfNeeded() {
        guard hasStartedLoad == false else { return }
        hasStartedLoad = true
        let scale = window?.windowScene?.screen.scale ?? traitCollection.displayScale
        let targetPixelWidth = max(bounds.width, DetailImageLayout.maxImageHeight) * max(scale, 1)
        DetailImageLoader.shared.loadImageForInlineResult(
            imageBlock.url,
            maxPixelWidth: targetPixelWidth,
            displayScale: scale
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, let image = result.image else { return }
                if let resolvedKind = result.resolvedKind {
                    self.resolvedImageKind = resolvedKind
                }
                self.imageView.image = image
                self.onImageLoaded(image.size, result.resolvedKind)
                self.setNeedsLayout()
            }
        }
    }

    @objc
    private func handleTap() {
        onImageTapped()
    }
}

enum DetailImageBlockLayout {
    private static let fallbackWidth: CGFloat = 320

    static func measure(originalSize: CGSize, constrainedSize: CGSize) -> CGSize {
        measure(originalSize: originalSize, constrainedSize: constrainedSize, kind: .normal)
    }

    static func measure(originalSize: CGSize, constrainedSize: CGSize, kind: DetailImageKind) -> CGSize {
        let width = resolvedWidth(constrainedSize.width)
        let size = presentationSize(originalSize: originalSize, maxWidth: width, kind: kind)
        return CGSize(width: width, height: ceil(size.height))
    }

    static func imageFrame(originalSize: CGSize, bounds: CGRect) -> CGRect {
        imageFrame(originalSize: originalSize, bounds: bounds, kind: .normal)
    }

    static func imageFrame(originalSize: CGSize, bounds: CGRect, kind: DetailImageKind) -> CGRect {
        let size = presentationSize(originalSize: originalSize, maxWidth: bounds.width, kind: kind)
        return CGRect(x: 0, y: 0, width: size.width, height: size.height)
    }

    static func contentMode(originalSize: CGSize, maxWidth: CGFloat) -> UIView.ContentMode {
        contentMode(originalSize: originalSize, maxWidth: maxWidth, kind: .normal)
    }

    static func contentMode(originalSize: CGSize, maxWidth: CGFloat, kind: DetailImageKind) -> UIView.ContentMode {
        switch presentation(originalSize: originalSize, maxWidth: maxWidth, kind: kind).mode {
        case .thumbnailCrop:
            return .scaleAspectFill
        case .aspectFit:
            return .scaleAspectFit
        }
    }

    static func presentationSize(originalSize: CGSize, maxWidth: CGFloat) -> CGSize {
        presentationSize(originalSize: originalSize, maxWidth: maxWidth, kind: .normal)
    }

    static func presentationSize(originalSize: CGSize, maxWidth: CGFloat, kind: DetailImageKind) -> CGSize {
        presentation(originalSize: originalSize, maxWidth: maxWidth, kind: kind).size
    }

    private static func presentation(
        originalSize: CGSize,
        maxWidth: CGFloat,
        kind: DetailImageKind = .normal
    ) -> DetailImagePresentation {
        DetailImageLayout.presentation(
            for: originalSize,
            maxWidth: resolvedWidth(maxWidth),
            kind: kind
        )
    }

    private static func resolvedWidth(_ width: CGFloat) -> CGFloat {
        guard width.isFinite, width > 0 else { return fallbackWidth }
        return width
    }
}
