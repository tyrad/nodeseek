//
//  DetailRichTextView.swift
//  nodeseek
//
//  Created by Codex on 2026/4/30.
//

import DTCoreText
import Kingfisher
import OSLog
import UIKit

final class DetailRichTextView: DTAttributedTextContentView, DTAttributedTextContentViewDelegate {
    private enum QuoteStyle {
        static let borderWidth: CGFloat = 3
        static let borderColor = UIColor.separator
        static let cornerRadius: CGFloat = 4
    }

    private static let logger = Logger(subsystem: "com.nodeseek.app", category: "DetailRichTextView")

    private var imageTapHandler: (([URL], Int) -> Void)?
    private var linkTapHandler: ((URL) -> Void)?
    private var layoutInvalidatedHandler: (() -> Void)?
    private var attachmentLayoutUpdatedHandler: ((URL, CGSize, CGSize) -> Void)?
    private var lastLayoutWidth: CGFloat = 0
    private let diagnosticID = String(UUID().uuidString.prefix(8))

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        delegate = self
        shouldDrawImages = false
        shouldDrawLinks = true
        shouldLayoutCustomSubviews = true
        layoutFrameHeightIsConstrainedByBounds = false
        isUserInteractionEnabled = true
        setContentCompressionResistancePriority(.required, for: .vertical)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self] (view: Self, previousTraitCollection: UITraitCollection) in
            guard let self else { return }
            guard previousTraitCollection.userInterfaceStyle != view.traitCollection.userInterfaceStyle else { return }
            self.refreshAppearanceForCurrentTraits()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ layer: CALayer, in context: CGContext) {
        super.draw(layer, in: context)
        drawStrikethroughDecorations(in: layoutFrame, context: context)
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard let context = UIGraphicsGetCurrentContext() else { return }
        drawStrikethroughDecorations(in: layoutFrame, context: context)
    }

    func configure(
        _ attributedText: NSAttributedString?,
        onImageTapped: (([URL], Int) -> Void)?,
        onLinkTapped: ((URL) -> Void)? = nil,
        onLayoutInvalidated: (() -> Void)?,
        onAttachmentLayoutUpdated: ((URL, CGSize, CGSize) -> Void)? = nil
    ) {
        imageTapHandler = onImageTapped
        linkTapHandler = onLinkTapped
        layoutInvalidatedHandler = onLayoutInvalidated
        attachmentLayoutUpdatedHandler = onAttachmentLayoutUpdated
        attributedString = attributedText ?? NSAttributedString()
        logDiagnostics(
            "configure length=\(attributedString.length) bounds=\(Self.string(from: bounds.size)) attachments=\(attachmentDiagnostics())"
        )
        removeAllCustomViews()
        removeAllCustomViewsForLinks()
        layouter = nil
        relayoutText()
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    func refreshAppearanceForCurrentTraits() {
        rebuildAttributedTextLayout()
    }

    var debugAttributedString: NSAttributedString? {
        attributedString
    }

    override func layoutSubviews() {
        let width = bounds.width
        if width > 0, abs(width - lastLayoutWidth) > 0.5 {
            lastLayoutWidth = width
            logDiagnostics("layoutSubviews widthChanged width=\(Self.numberString(width)) bounds=\(Self.string(from: bounds.size))")
            layouter = nil
            relayoutText()
            invalidateIntrinsicContentSize()
        }
        super.layoutSubviews()
    }

    override var intrinsicContentSize: CGSize {
        richTextSize(constrainedToWidth: bounds.width)
    }

    override func systemLayoutSizeFitting(_ targetSize: CGSize) -> CGSize {
        let width = targetSize.width > 0 ? targetSize.width : bounds.width
        return richTextSize(constrainedToWidth: width)
    }

    override func systemLayoutSizeFitting(
        _ targetSize: CGSize,
        withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
        verticalFittingPriority: UILayoutPriority
    ) -> CGSize {
        let width = targetSize.width > 0 ? targetSize.width : bounds.width
        return richTextSize(constrainedToWidth: width)
    }

    private func rebuildAttributedTextLayout() {
        let snapshot = NSAttributedString(attributedString: attributedString)
        attributedString = snapshot
        removeAllCustomViews()
        removeAllCustomViewsForLinks()
        layouter = nil
        relayoutText()
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        setNeedsDisplay()
    }

    func attributedTextContentView(
        _ attributedTextContentView: DTAttributedTextContentView,
        viewFor attachment: DTTextAttachment,
        frame: CGRect
    ) -> UIView? {
        guard let contentURL = attachment.contentURL else {
            logDiagnostics("viewForAttachment skipped type=\(String(describing: type(of: attachment))) contentURL=\(String(describing: attachment.contentURL)) frame=\(Self.string(from: frame))")
            return nil
        }

        logDiagnostics(
            "viewForAttachment url=\(contentURL.absoluteString) frame=\(Self.string(from: frame)) original=\(Self.string(from: attachment.originalSize)) display=\(Self.string(from: attachment.displaySize)) bounds=\(Self.string(from: bounds.size))"
        )
        let viewFrame = Self.attachmentViewFrame(
            proposedFrame: frame,
            displaySize: attachment.displaySize
        )

        let isStickerAttachment = isStickerAttachment(attachment, contentURL: contentURL)
        if isVideoURL(contentURL), isStickerAttachment {
            return DetailInlineVideoStickerView(frame: viewFrame, videoURL: contentURL)
        }

        guard attachment is DTImageTextAttachment else {
            logDiagnostics("viewForAttachment skipped type=\(String(describing: type(of: attachment))) contentURL=\(String(describing: attachment.contentURL)) frame=\(Self.string(from: frame))")
            return nil
        }

        let imageView = DetailInlineImageView(
            frame: viewFrame,
            imageURL: contentURL,
            targetPixelWidth: targetImagePointSide(
                originalSize: attachment.originalSize,
                isSticker: isStickerAttachment
            ) * displayScale,
            displayScale: displayScale,
            allowsInlineAnimation: allowsInlineAnimation(
                originalSize: attachment.originalSize,
                isSticker: isStickerAttachment
            ),
            usesDetailImageOptimization: isStickerAttachment == false,
            onImageLoaded: { [weak self] loadedURL, imageSize in
                self?.handleLoadedImage(loadedURL, imageSize: imageSize)
            },
            onImageTapped: { [weak self] tappedURL in
                self?.handleImageTap(tappedURL)
            }
        )
        imageView.contentMode = contentMode(
            originalSize: attachment.originalSize,
            isSticker: isStickerAttachment
        )
        imageView.clipsToBounds = true
        imageView.isOpaque = false
        imageView.backgroundColor = .clear
        imageView.image = (attachment as? DTImageTextAttachment)?.image

        return imageView
    }

    nonisolated static func attachmentViewFrame(
        proposedFrame: CGRect,
        displaySize: CGSize
    ) -> CGRect {
        guard displaySize.width > 0,
              displaySize.height > 0 else {
            return proposedFrame
        }

        let yOffset = proposedFrame.height > displaySize.height
            ? (proposedFrame.height - displaySize.height) / 2
            : 0
        return CGRect(
            x: proposedFrame.minX,
            y: proposedFrame.minY + yOffset,
            width: displaySize.width,
            height: displaySize.height
        )
    }

    func attributedTextContentView(
        _ attributedTextContentView: DTAttributedTextContentView,
        viewForLink url: URL,
        identifier: String,
        frame: CGRect
    ) -> UIView? {
        DetailLinkOverlayButton(frame: frame, url: url) { [weak self] tappedURL in
            self?.linkTapHandler?(tappedURL)
        }
    }

    private func drawStrikethroughDecorations(
        in layoutFrame: DTCoreTextLayoutFrame?,
        context: CGContext
    ) {
        guard let layoutFrame else { return }
        let runs = layoutFrame.lines
            .compactMap { $0 as? DTCoreTextLayoutLine }
            .flatMap { line in line.glyphRuns.compactMap { $0 as? DTCoreTextGlyphRun } }
            .filter { run in
                guard run.isTrailingWhitespace() == false else { return false }
                return Self.hasStrikethroughAttribute(in: run.attributes)
            }
        guard runs.isEmpty == false else { return }

        let displayScale = max(traitCollection.displayScale, 1)
        let lineWidth = max(1 / displayScale, 0.5)

        context.saveGState()
        context.setLineWidth(lineWidth)
        context.setLineCap(.butt)

        for run in runs {
            let frame = run.frame
            guard frame.width > 0, frame.height > 0 else { continue }
            let color = Self.foregroundColor(in: run.attributes) ?? tintColor ?? .label
            let y = Self.pixelAligned(frame.minY + frame.height * 0.48, scale: displayScale)

            context.setStrokeColor(color.cgColor)
            context.move(to: CGPoint(x: frame.minX, y: y))
            context.addLine(to: CGPoint(x: frame.maxX, y: y))
            context.strokePath()
        }

        context.restoreGState()
    }

    private static func hasStrikethroughAttribute(in attributes: [AnyHashable: Any]) -> Bool {
        if let value = attributes[NSAttributedString.Key(DTStrikeOutAttribute)] as? NSNumber,
           value.boolValue {
            return true
        }
        if let value = attributes[NSAttributedString.Key.strikethroughStyle] as? NSNumber,
           value.intValue != 0 {
            return true
        }
        return false
    }

    private static func foregroundColor(in attributes: [AnyHashable: Any]) -> UIColor? {
        if let color = attributes[NSAttributedString.Key.foregroundColor] as? UIColor {
            return color
        }
        if let color = attributes[kCTForegroundColorAttributeName as NSAttributedString.Key] {
            if let uiColor = color as? UIColor {
                return uiColor
            }
            return UIColor(cgColor: color as! CGColor)
        }
        return nil
    }

    private static func pixelAligned(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        guard scale > 0 else { return value }
        return (value * scale).rounded() / scale
    }

    func attributedTextContentView(
        _ attributedTextContentView: DTAttributedTextContentView,
        shouldDrawBackgroundFor textBlock: DTTextBlock,
        frame: CGRect,
        context: CGContext,
        for layoutFrame: DTCoreTextLayoutFrame
    ) -> Bool {
        guard let backgroundColor = textBlock.backgroundColor else { return true }

        let quoteFrame = frame
        let backgroundPath = UIBezierPath(roundedRect: quoteFrame, cornerRadius: QuoteStyle.cornerRadius)
        let resolvedBackgroundColor = backgroundColor.resolvedColor(with: traitCollection)

        context.saveGState()
        context.setFillColor(resolvedBackgroundColor.cgColor)
        context.addPath(backgroundPath.cgPath)
        context.fillPath()
        let resolvedBorderColor = QuoteStyle.borderColor.resolvedColor(with: traitCollection)
        context.setFillColor(resolvedBorderColor.cgColor)
        context.fill(CGRect(
            x: quoteFrame.minX,
            y: quoteFrame.minY,
            width: QuoteStyle.borderWidth,
            height: quoteFrame.height
        ))
        context.restoreGState()
        return false
    }

    private func handleLoadedImage(_ url: URL, imageSize: CGSize) {
        guard let displaySize = updateImageAttachments(matching: url, originalSize: imageSize) else {
            logDiagnostics(
                "imageLoaded noAttachmentUpdate url=\(url.absoluteString) imageSize=\(Self.string(from: imageSize)) attachments=\(attachmentDiagnostics())"
            )
            return
        }
        logDiagnostics(
            "imageLoaded updated url=\(url.absoluteString) imageSize=\(Self.string(from: imageSize)) display=\(Self.string(from: displaySize))"
        )
        attachmentLayoutUpdatedHandler?(url, imageSize, displaySize)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.removeAllCustomViews()
            self.removeAllCustomViewsForLinks()
            self.layouter = nil
            self.relayoutText()
            self.invalidateIntrinsicContentSize()
            self.logDiagnostics(
                "imageLoaded relayout intrinsic=\(Self.string(from: self.intrinsicContentSize)) bounds=\(Self.string(from: self.bounds.size))"
            )
            self.setNeedsLayout()
            self.layoutInvalidatedHandler?()
        }
    }

    private func updateImageAttachments(matching url: URL, originalSize: CGSize) -> CGSize? {
        guard attributedString.length > 0,
              originalSize.width > 0,
              originalSize.height > 0 else {
            return nil
        }

        var updatedDisplaySize: CGSize?
        attributedString.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributedString.length)
        ) { value, _, _ in
            guard let attachment = value as? DTTextAttachment,
                  attachment.contentURL == url else {
                return
            }

            let isSticker = isStickerAttachment(attachment, contentURL: url)
            let presentation = DetailImageLayout.presentation(
                for: originalSize,
                maxWidth: maxImageWidth(isSticker: isSticker),
                isSticker: isSticker
            )
            let displaySize = presentation.size
            if isSticker == false, attachment.displaySize == displaySize {
                logDiagnostics(
                    "normal attachment fixed size unchanged url=\(url.absoluteString) imageSize=\(Self.string(from: originalSize)) display=\(Self.string(from: displaySize))"
                )
                return
            }
            guard attachment.originalSize != originalSize || attachment.displaySize != displaySize else {
                logDiagnostics(
                    "attachment already current url=\(url.absoluteString) original=\(Self.string(from: originalSize)) display=\(Self.string(from: displaySize))"
                )
                return
            }

            attachment.originalSize = originalSize
            attachment.displaySize = displaySize
            updatedDisplaySize = displaySize
        }
        return updatedDisplaySize
    }

    private func handleImageTap(_ tappedURL: URL) {
        guard let onImageTapped = imageTapHandler,
              let resolvedTappedURL = AvatarImageLoader.resolveImageURL(tappedURL) else {
            return
        }

        let urls = previewImageURLs()
        guard let index = urls.firstIndex(of: resolvedTappedURL) else { return }
        onImageTapped(urls, index)
    }

    private func previewImageURLs() -> [URL] {
        guard attributedString.length > 0 else { return [] }

        var urls: [URL] = []
        attributedString.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributedString.length)
        ) { value, _, _ in
            guard let attachment = value as? DTTextAttachment,
                  let contentURL = attachment.contentURL,
                  let resolvedURL = AvatarImageLoader.resolveImageURL(contentURL),
                  isVideoURL(resolvedURL) == false,
                  isStickerAttachment(attachment, contentURL: resolvedURL) == false,
                  urls.contains(resolvedURL) == false else {
                return
            }
            urls.append(resolvedURL)
        }
        return urls
    }

    private func maxImageWidth(isSticker: Bool) -> CGFloat {
        let width = bounds.width > 0 ? bounds.width : 320
        return isSticker ? min(width, DetailImageLayout.fixedStickerWidth) : width
    }

    private func targetImagePointSide(originalSize: CGSize, isSticker: Bool) -> CGFloat {
        let maxWidth = maxImageWidth(isSticker: isSticker)
        guard originalSize.width > 0, originalSize.height > 0 else {
            return isSticker ? maxWidth : max(maxWidth, DetailImageLayout.maxImageHeight)
        }

        return DetailImageLayout.presentation(
            for: originalSize,
            maxWidth: maxWidth,
            isSticker: isSticker
        ).targetPointSide
    }

    private func allowsInlineAnimation(originalSize: CGSize, isSticker: Bool) -> Bool {
        guard isSticker || (originalSize.width > 0 && originalSize.height > 0) else { return false }
        return DetailImageLayout.allowsInlineAnimation(
            for: originalSize,
            maxWidth: maxImageWidth(isSticker: isSticker),
            isSticker: isSticker
        )
    }

    private func contentMode(originalSize: CGSize, isSticker: Bool) -> UIView.ContentMode {
        let mode = DetailImageLayout.presentation(
            for: originalSize,
            maxWidth: maxImageWidth(isSticker: isSticker),
            isSticker: isSticker
        ).mode

        switch mode {
        case .thumbnailCrop:
            return .scaleAspectFill
        case .aspectFit:
            return .scaleAspectFit
        }
    }

    private func richTextSize(constrainedToWidth width: CGFloat) -> CGSize {
        guard attributedString.length > 0 else {
            return CGSize(width: UIView.noIntrinsicMetric, height: 0)
        }
        guard width > 0 else {
            return CGSize(width: UIView.noIntrinsicMetric, height: 1)
        }

        if abs(bounds.width - width) > 0.5 {
            var adjustedBounds = bounds
            adjustedBounds.size.width = width
            bounds = adjustedBounds
        }
        layoutFrame = nil
        _ = layoutFrame
        let size = super.intrinsicContentSize
        logDiagnostics(
            "richTextSize width=\(Self.numberString(width)) result=\(Self.string(from: size)) bounds=\(Self.string(from: bounds.size)) attachments=\(attachmentDiagnostics())"
        )
        return CGSize(width: UIView.noIntrinsicMetric, height: ceil(max(size.height, 1)))
    }

    private var displayScale: CGFloat {
        window?.windowScene?.screen.scale ?? traitCollection.displayScale
    }

    private func isStickerImageURL(_ url: URL) -> Bool {
        url.absoluteString.lowercased().contains("sticker")
    }

    private func isVideoURL(_ url: URL) -> Bool {
        let pathExtension = url.pathExtension.lowercased()
        return pathExtension == "mp4" || pathExtension == "mov" || pathExtension == "m4v" || pathExtension == "webm"
    }

    private func isStickerAttachment(_ attachment: DTTextAttachment, contentURL: URL) -> Bool {
        DetailAttachmentAttributes.hasClass("sticker", in: attachment.attributes) || isStickerImageURL(contentURL)
    }

    private func logDiagnostics(_ message: String) {
        guard NodeSeekDebugConfig.enableDetailRenderDiagnostics else { return }
        Self.logger.info("[\(self.diagnosticID, privacy: .public)] \(message, privacy: .public)")
    }

    private func attachmentDiagnostics() -> String {
        guard attributedString.length > 0 else { return "[]" }
        var parts: [String] = []
        attributedString.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributedString.length)
        ) { value, _, _ in
            guard let attachment = value as? DTTextAttachment else { return }
            parts.append(
                "url=\(attachment.contentURL?.absoluteString ?? "nil"),original=\(Self.string(from: attachment.originalSize)),display=\(Self.string(from: attachment.displaySize))"
            )
        }
        if parts.count > 6 {
            return "[\(parts.prefix(6).joined(separator: " | ")) | ... total=\(parts.count)]"
        }
        return "[\(parts.joined(separator: " | "))]"
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

private final class DetailLinkOverlayButton: UIButton {
    private let url: URL
    private let onTapped: (URL) -> Void

    init(frame: CGRect, url: URL, onTapped: @escaping (URL) -> Void) {
        self.url = url
        self.onTapped = onTapped
        super.init(frame: frame)
        backgroundColor = .clear
        addTarget(self, action: #selector(handleTap), for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    private func handleTap() {
        onTapped(url)
    }
}
