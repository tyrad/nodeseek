//
//  DetailInlineImageView.swift
//  nodeseek
//
//  Created by Codex on 2026/4/30.
//

import Kingfisher
import UIKit

/// 帖子详情富文本中的内联图片视图。
final class DetailInlineImageView: AnimatedImageView {
    private let imageURL: URL
    private let targetPixelWidth: CGFloat
    private let displayScale: CGFloat
    private let allowsInlineAnimation: Bool
    private let usesDetailImageOptimization: Bool
    /// 用于判断是否按长图展示；为 nil 时不做长图处理，例如表情图。
    private let longImageLayoutWidth: CGFloat?
    private let onImageLoaded: (URL, CGSize) -> Void
    private let onImageFailed: (URL) -> Void
    private let onImageTapped: (URL) -> Void
    private var originalImageSize: CGSize?
    private var resolvedImageKind: DetailImageKind = .normal
    private var loadToken: UUID?
    private let placeholderView = DetailImagePlaceholderView()
    private lazy var animationBinding = DetailAnimatedImageBinding(imageView: self)
    private let diagnosticID = String(UUID().uuidString.prefix(8))

    init(
        frame: CGRect,
        imageURL: URL,
        targetPixelWidth: CGFloat,
        displayScale: CGFloat,
        allowsInlineAnimation: Bool,
        usesDetailImageOptimization: Bool,
        longImageLayoutWidth: CGFloat? = nil,
        onImageLoaded: @escaping (URL, CGSize) -> Void,
        onImageFailed: @escaping (URL) -> Void = { _ in },
        onImageTapped: @escaping (URL) -> Void
    ) {
        self.imageURL = imageURL
        self.targetPixelWidth = targetPixelWidth
        self.displayScale = displayScale
        self.allowsInlineAnimation = allowsInlineAnimation
        self.usesDetailImageOptimization = usesDetailImageOptimization
        self.longImageLayoutWidth = longImageLayoutWidth
        self.onImageLoaded = onImageLoaded
        self.onImageFailed = onImageFailed
        self.onImageTapped = onImageTapped
        super.init(frame: frame)
        autoPlayAnimatedImage = true
        framePreloadCount = 6
        needsPrescaling = true
        purgeFramesOnBackground = true
        isUserInteractionEnabled = true
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        addSubview(placeholderView)
        DetailImageDimmingView.install(on: self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        placeholderView.frame = bounds
        updateLongImagePreview()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        animationBinding.windowDidChange()
    }

    func setPlaybackVisible(_ visible: Bool) { animationBinding.setVisible(visible) }

    var isPlayingWebP: Bool { animationBinding.isPlaying }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()

        guard superview != nil else {
            logDiagnostics("removed url=\(imageURL.absoluteString) frame=\(Self.string(from: frame))")
            loadToken = nil
            kf.cancelDownloadTask()
            purgeFrames()
            animationBinding.reset()
            return
        }
        guard loadToken == nil, !placeholderView.hasFailed else { return }
        placeholderView.isHidden = false

        let token = UUID()
        loadToken = token
        logDiagnostics(
            "startLoad url=\(imageURL.absoluteString) frame=\(Self.string(from: frame)) targetPixelWidth=\(Self.numberString(targetPixelWidth)) displayScale=\(Self.numberString(displayScale))"
        )

        if shouldUseAnimatedInlineLoader {
            loadAnimatedImage(token: token)
            return
        }

        ImageLoad.url(imageURL)
            .toDetailInline(
                maxPixelWidth: targetPixelWidth,
                displayScale: displayScale,
                allowsOptimization: usesDetailImageOptimization
            )
            .loadResult { [weak self] result in
                DispatchQueue.main.async {
                    guard let self, self.loadToken == token else { return }
                    self.applyLoadedImage(result)
                }
            }
    }

    func applyLoadedImage(_ result: DetailInlineImageResult) {
        guard !result.isFallback, result.image != nil else {
            applyLoadFailure()
            return
        }
        animationBinding.reset()
        placeholderView.showFailure(false)
        placeholderView.isHidden = true
        originalImageSize = result.originalSize ?? result.image?.size
        resolvedImageKind = result.resolvedKind ?? .normal
        image = result.image
        // 即使占位与最终尺寸相同、富文本不重排，也立即切换裁剪和角标。
        updateLongImagePreview()
        // 附件首次可能尚无尺寸，WebP 用加载后的原始尺寸重新判断是否允许动画。
        if let asset = result.animationAsset, let originalImageSize,
           DetailImageLayout.allowsInlineAnimation(for: originalImageSize, maxWidth: bounds.width,
                                                   kind: usesDetailImageOptimization ? .normal : .sticker) {
            animationBinding.load(asset, poster: result.image, maximumPixelSize: Int(ceil(targetPixelWidth)))
        }
        if let image {
            logDiagnostics(
                "loaded url=\(imageURL.absoluteString) imageSize=\(Self.string(from: image.size)) frame=\(Self.string(from: frame))"
            )
            onImageLoaded(imageURL, originalImageSize ?? image.size)
        } else {
            logDiagnostics("loaded nil url=\(imageURL.absoluteString)")
        }
    }

    func applyLoadFailure(notify: Bool = true) {
        animationBinding.reset()
        image = nil
        originalImageSize = nil
        DetailLongImagePreview.apply(to: self, isLongImage: false)
        placeholderView.showFailure(true)
        placeholderView.isHidden = false
        if notify { onImageFailed(imageURL) }
    }

    private func updateLongImagePreview() {
        guard let longImageLayoutWidth else { return }
        let isLongImage = image.map {
            DetailImageLayout.presentation(for: originalImageSize ?? $0.size, maxWidth: longImageLayoutWidth, kind: resolvedImageKind).mode == .topCrop
        } ?? false
        contentMode = isLongImage ? .scaleToFill : .scaleAspectFit
        DetailLongImagePreview.apply(to: self, isLongImage: isLongImage)
    }

    private var shouldUseAnimatedInlineLoader: Bool {
        allowsInlineAnimation && imageURL.pathExtension.lowercased() == "gif"
    }

    private func loadAnimatedImage(token: UUID) {
        guard let resolvedURL = ImageURLResolver.resolve(imageURL) else {
            logDiagnostics("animatedLoad invalidURL url=\(imageURL.absoluteString)")
            applyLoadFailure()
            return
        }

        logDiagnostics("animatedLoad start url=\(resolvedURL.absoluteString)")
        kf.setImage(
            with: resolvedURL,
            options: [
                .requestModifier(AnyModifier { request in
                    var modifiedRequest = request
                    WebRequestFingerprint.applyImageHeaders(to: &modifiedRequest)
                    return modifiedRequest
                })
            ]
        ) { [weak self] result in
            guard let self, self.loadToken == token else { return }
            switch result {
            case .success(let value):
                self.placeholderView.isHidden = true
                self.originalImageSize = value.image.size
                self.updateLongImagePreview()
                self.logDiagnostics(
                    "animatedLoad loaded url=\(resolvedURL.absoluteString) imageSize=\(Self.string(from: value.image.size)) frame=\(Self.string(from: self.frame))"
                )
                self.onImageLoaded(self.imageURL, value.image.size)
            case .failure(let error):
                self.applyLoadFailure()
                self.logDiagnostics(
                    "animatedLoad failed url=\(resolvedURL.absoluteString) error=\(error.localizedDescription)"
                )
            }
        }
    }

    @objc
    private func handleTap() {
        DetailPhotoTransitionAnchor.record(imageView: self, url: imageURL)
        onImageTapped(imageURL)
    }

    private func logDiagnostics(_ message: String) {
        guard NodeSeekDebugConfig.enableDetailRenderDiagnostics else { return }
        AppLog.info(.rendering, "[\(diagnosticID)] \(message)")
    }

    private static func string(from rect: CGRect) -> String {
        "x=\(numberString(rect.origin.x)),y=\(numberString(rect.origin.y)),w=\(numberString(rect.width)),h=\(numberString(rect.height))"
    }

    private static func string(from size: CGSize) -> String {
        "\(numberString(size.width))x\(numberString(size.height))"
    }

    private static func numberString(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }
}

extension DetailInlineImageView: DetailPhotoThumbnailSource {
    var detailPhotoThumbnailURL: URL? { imageURL }
    var detailPhotoThumbnailView: UIImageView { self }
}
