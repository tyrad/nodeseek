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
    private var loadedImageSize: CGSize = .zero

    init(
        imageBlock: RenderedImageBlock,
        imageURLs: [URL],
        imageIndex: Int,
        onImageTapped: @escaping ([URL], Int) -> Void,
        onLayoutInvalidated: @escaping () -> Void
    ) {
        self.onLayoutInvalidated = onLayoutInvalidated
        super.init()
        setViewBlock { [weak self] in
            DetailImageBlockView(
                imageBlock: imageBlock,
                onImageLoaded: { imageSize in
                    self?.updateLoadedImageSize(imageSize)
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
            constrainedSize: constrainedSize
        )
    }

    private func updateLoadedImageSize(_ imageSize: CGSize) {
        guard imageSize.width > 0, imageSize.height > 0 else { return }
        let previousSize = loadedImageSize
        loadedImageSize = imageSize
        let previousLayout = DetailImageBlockLayout.presentationSize(
            originalSize: previousSize,
            maxWidth: calculatedSize.width
        )
        let nextLayout = DetailImageBlockLayout.presentationSize(
            originalSize: imageSize,
            maxWidth: calculatedSize.width
        )
        guard previousLayout != nextLayout else { return }
        invalidateCalculatedLayout()
        setNeedsLayout()
        onLayoutInvalidated()
    }
}

private final class DetailImageBlockView: UIView {
    private let imageBlock: RenderedImageBlock
    private let onImageLoaded: (CGSize) -> Void
    private let onImageTapped: () -> Void
    private let imageView = UIImageView()
    private var hasStartedLoad = false

    init(
        imageBlock: RenderedImageBlock,
        onImageLoaded: @escaping (CGSize) -> Void,
        onImageTapped: @escaping () -> Void
    ) {
        self.imageBlock = imageBlock
        self.onImageLoaded = onImageLoaded
        self.onImageTapped = onImageTapped
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
            bounds: bounds
        )
        imageView.contentMode = DetailImageBlockLayout.contentMode(
            originalSize: imageView.image?.size ?? .zero,
            maxWidth: bounds.width
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
        DetailImageLoader.shared.loadImageForInline(
            imageBlock.url,
            maxPixelWidth: targetPixelWidth,
            displayScale: scale
        ) { [weak self] image in
            DispatchQueue.main.async {
                guard let self, let image else { return }
                self.imageView.image = image
                self.onImageLoaded(image.size)
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
        let width = resolvedWidth(constrainedSize.width)
        let size = presentationSize(originalSize: originalSize, maxWidth: width)
        return CGSize(width: width, height: ceil(size.height))
    }

    static func imageFrame(originalSize: CGSize, bounds: CGRect) -> CGRect {
        let size = presentationSize(originalSize: originalSize, maxWidth: bounds.width)
        return CGRect(x: 0, y: 0, width: size.width, height: size.height)
    }

    static func contentMode(originalSize: CGSize, maxWidth: CGFloat) -> UIView.ContentMode {
        switch presentation(originalSize: originalSize, maxWidth: maxWidth).mode {
        case .thumbnailCrop:
            return .scaleAspectFill
        case .aspectFit:
            return .scaleAspectFit
        }
    }

    static func presentationSize(originalSize: CGSize, maxWidth: CGFloat) -> CGSize {
        presentation(originalSize: originalSize, maxWidth: maxWidth).size
    }

    private static func presentation(originalSize: CGSize, maxWidth: CGFloat) -> DetailImagePresentation {
        DetailImageLayout.presentation(
            for: originalSize,
            maxWidth: resolvedWidth(maxWidth),
            isSticker: false
        )
    }

    private static func resolvedWidth(_ width: CGFloat) -> CGFloat {
        guard width.isFinite, width > 0 else { return fallbackWidth }
        return width
    }
}
