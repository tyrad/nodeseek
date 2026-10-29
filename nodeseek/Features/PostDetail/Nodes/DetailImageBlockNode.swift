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
    private var hasFailed = false
    private static let heightReductionThreshold: CGFloat = 1

    init(
        imageBlock: RenderedImageBlock,
        imageURLs: [URL],
        imageIndex: Int,
        initialImageSize: CGSize = .zero,
        imageKind: DetailImageKind? = nil,
        onImageTapped: @escaping ([URL], Int) -> Void,
        onImageSizeResolved: @escaping (URL, CGSize) -> Void = { _, _ in },
        onImageHeightReduced: @escaping () -> Void = {},
        onLayoutInvalidated: @escaping () -> Void
    ) {
        self.onLayoutInvalidated = onLayoutInvalidated
        self.onImageHeightReduced = onImageHeightReduced
        self.onImageSizeResolved = onImageSizeResolved
        self.imageURL = imageBlock.url
        let resolvedImageKind = imageKind ?? DetailImageKind.resolved(isSticker: false, imageURL: imageBlock.url)
        self.imageKind = resolvedImageKind
        self.loadedImageSize = initialImageSize.width > 0 && initialImageSize.height > 0 ? initialImageSize : .zero
        super.init()
        setViewBlock { [weak self] in
            DetailImageBlockView(
                imageBlock: imageBlock,
                imageKind: resolvedImageKind,
                onImageLoaded: { imageSize, resolvedKind in
                    self?.updateLoadedImageSize(imageSize, resolvedKind: resolvedKind)
                },
                onImageFailed: { self?.handleImageFailure() },
                onImageTapped: {
                    onImageTapped(imageURLs, imageIndex)
                }
            )
        }
        // 高度跟图片比例走。弹性拉伸保持默认 0，否则行高更新前会被父栈压回占位高度。
    }

    override func calculateSizeThatFits(_ constrainedSize: CGSize) -> CGSize {
        if hasFailed {
            return DetailImagePlaceholderView.failureSize(maxWidth: constrainedSize.width)
        }
        return DetailImageBlockLayout.measure(
            originalSize: loadedImageSize,
            constrainedSize: constrainedSize,
            kind: imageKind
        )
    }

    override func didLoad() {
        super.didLoad()
        updatePlaybackVisibility()
    }

    override func didEnterVisibleState() {
        super.didEnterVisibleState()
        updatePlaybackVisibility()
    }

    override func didExitVisibleState() {
        super.didExitVisibleState()
        updatePlaybackVisibility()
    }

    private func updatePlaybackVisibility() {
        guard isNodeLoaded else { return }
        (view as? DetailImageBlockView)?.setPlaybackVisible(isVisible)
    }

    func updateLoadedImageSize(_ imageSize: CGSize, resolvedKind: DetailImageKind? = nil) {
        guard imageSize.width > 0, imageSize.height > 0 else { return }
        let previousSize = loadedImageSize
        let wasFailed = hasFailed
        hasFailed = false
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
        guard wasFailed || previousLayout != nextLayout else { return }
        invalidateCalculatedLayout()
        setNeedsLayout()
        if nextLayout.height < previousLayout.height - Self.heightReductionThreshold {
            onImageHeightReduced()
        } else {
            // 变矮会重载整行。变高只重测，所以要清掉正文 cell 上仍停在占位高度的缓存。
            invalidateAncestorCellLayout()
            onLayoutInvalidated()
        }
    }

    private func handleImageFailure() {
        guard !hasFailed else { return }
        hasFailed = true
        invalidateCalculatedLayout()
        setNeedsLayout()
        invalidateAncestorCellLayout()
        // 只重测现有节点；重载整行会创建新节点并反复请求失败图片。
        onLayoutInvalidated()
    }

    private func invalidateAncestorCellLayout() {
        var ancestor = supernode
        while let node = ancestor {
            // 引用块等中间容器也有布局缓存，只清 cell 仍会复用旧高度。
            node.invalidateCalculatedLayout()
            if node is ASCellNode { return }
            ancestor = node.supernode
        }
    }
}

final class DetailImageBlockView: UIView {
    private let imageBlock: RenderedImageBlock
    private let onImageLoaded: (CGSize, DetailImageKind?) -> Void
    private let onImageFailed: () -> Void
    private let onImageTapped: () -> Void
    private let imageView = UIImageView()
    private let placeholderView = DetailImagePlaceholderView()
    private var loadedImage: UIImage?
    private var originalImageSize: CGSize = .zero
    private var hasStartedLoad = false
    private var resolvedImageKind: DetailImageKind
    private lazy var animationBinding = DetailAnimatedImageBinding(imageView: imageView)
    private var playbackVisible = false
    private var canDisplayImage = false

    var isPlayingWebP: Bool { animationBinding.isPlaying }

    init(
        imageBlock: RenderedImageBlock,
        imageKind: DetailImageKind,
        onImageLoaded: @escaping (CGSize, DetailImageKind?) -> Void,
        onImageFailed: @escaping () -> Void = {},
        onImageTapped: @escaping () -> Void
    ) {
        self.imageBlock = imageBlock
        self.onImageLoaded = onImageLoaded
        self.onImageFailed = onImageFailed
        self.onImageTapped = onImageTapped
        self.resolvedImageKind = imageKind
        super.init(frame: .zero)
        configureView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        placeholderView.frame = bounds
        if !placeholderView.hasFailed, let visible = DetailImageBlockLayout.visibleImage(
            originalSize: originalImageSize,
            bounds: bounds,
            kind: resolvedImageKind
        ) {
            canDisplayImage = true
            imageView.isHidden = false
            placeholderView.isHidden = loadedImage != nil
            imageView.frame = visible.frame
            if !animationBinding.hasAnimation { imageView.image = loadedImage }
            imageView.contentMode = visible.contentMode
            DetailLongImagePreview.apply(to: imageView, isLongImage: visible.isLongImage)
        } else {
            canDisplayImage = false
            imageView.isHidden = true
            placeholderView.isHidden = false
            // 目标比当前行高更高时先留占位，等行高到位再按最终尺寸画，避免整张图先缩小再放大。
            imageView.frame = bounds
            if !animationBinding.hasAnimation { imageView.image = nil }
            // 角标是子视图，图片被清掉后不会跟着消失。
            DetailLongImagePreview.apply(to: imageView, isLongImage: false)
        }
        updatePlaybackVisibility()
        loadImageIfNeeded()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        animationBinding.windowDidChange()
    }

    func setPlaybackVisible(_ visible: Bool) {
        playbackVisible = visible
        updatePlaybackVisibility()
    }

    private func updatePlaybackVisibility() {
        animationBinding.setVisible(playbackVisible && canDisplayImage)
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
        DetailImageDimmingView.install(on: imageView)
        addSubview(placeholderView)
    }

    private func loadImageIfNeeded() {
        guard hasStartedLoad == false, bounds.width > 0 else { return }
        hasStartedLoad = true
        let scale = window?.windowScene?.screen.scale ?? traitCollection.displayScale
        let targetPixelWidth = max(bounds.width, DetailImageLayout.maxImageHeight) * max(scale, 1)
        ImageLoad.url(imageBlock.url)
            .toDetailInline(maxPixelWidth: targetPixelWidth, displayScale: scale)
            .loadResult { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.applyLoadedImage(result)
                }
            }
    }

    func applyLoadedImage(_ result: DetailInlineImageResult) {
        animationBinding.reset()
        guard !result.isFallback, let image = result.image else {
            loadedImage = nil
            originalImageSize = .zero
            placeholderView.showFailure(true)
            placeholderView.isHidden = false
            imageView.isHidden = true
            onImageFailed()
            setNeedsLayout()
            return
        }
        placeholderView.showFailure(false)
        if let resolvedKind = result.resolvedKind { resolvedImageKind = resolvedKind }
        originalImageSize = result.originalSize ?? image.size
        loadedImage = image
        if let asset = result.animationAsset,
           DetailImageLayout.allowsInlineAnimation(for: originalImageSize, maxWidth: bounds.width, kind: resolvedImageKind) {
            let scale = window?.windowScene?.screen.scale ?? traitCollection.displayScale
            animationBinding.load(asset, poster: image, maximumPixelSize: Int(ceil(bounds.width * max(scale, 1))))
        }
        onImageLoaded(originalImageSize, result.resolvedKind)
        setNeedsLayout()
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

    struct VisibleImage {
        let frame: CGRect
        let contentMode: UIView.ContentMode
        let isLongImage: Bool
    }

    /// 目标高度还放不进当前行时返回 nil，调用方继续显示占位，不先画一张缩小的图。
    static func visibleImage(originalSize: CGSize, bounds: CGRect, kind: DetailImageKind) -> VisibleImage? {
        guard originalSize.width > 0, originalSize.height > 0, bounds.height > 0 else { return nil }
        let proposed = presentation(originalSize: originalSize, maxWidth: bounds.width, kind: kind)
        guard proposed.size.height <= bounds.height + 0.5 else { return nil }
        return VisibleImage(
            frame: CGRect(origin: .zero, size: proposed.size),
            contentMode: contentMode(for: proposed.mode),
            isLongImage: proposed.mode == .topCrop
        )
    }

    private static func contentMode(for mode: DetailImageDisplayMode) -> UIView.ContentMode {
        switch mode {
        case .thumbnailCrop:
            return .scaleAspectFill
        case .aspectFit:
            return .scaleAspectFit
        case .topCrop:
            return .scaleToFill
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
