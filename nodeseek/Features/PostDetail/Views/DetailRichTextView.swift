//
//  DetailRichTextView.swift
//  nodeseek
//
//  Created by Codex on 2026/4/30.
//

import DTCoreText
import Kingfisher
import UIKit

struct DetailLinkCandidate: Equatable {
    let title: String
    let subtitle: String
    let url: URL
}

/// 帖子详情正文和评论的富文本渲染视图。
final class DetailRichTextView: DTAttributedTextContentView, DTAttributedTextContentViewDelegate {
    private enum QuoteStyle {
        static let borderWidth: CGFloat = 3
        static let borderColor = UIColor.separator
        static let cornerRadius: CGFloat = 4
    }

    private var imageTapHandler: (([URL], Int) -> Void)?
    private var linkTapHandler: ((URL) -> Void)?
    private var signatureLinkCandidatesTapHandler: (([DetailLinkCandidate]) -> Void)?
    private var layoutInvalidatedHandler: (() -> Void)?
    private var attachmentLayoutUpdatedHandler: ((URL, CGSize, CGSize) -> Void)?
    private var lastLayoutWidth: CGFloat = 0
    private let diagnosticID = String(UUID().uuidString.prefix(8))
    private var pendingRelayoutWorkItem: DispatchWorkItem?
    private let stickerAspectRatioProvider: any StickerAspectRatioProviding = StickerAspectRatioCache.shared

    private enum RelayoutDebounce {
        static let interval: TimeInterval = 0.10
    }

    private struct ImageAttachmentUpdate {
        let displaySize: CGSize
        let requiresRelayout: Bool
    }

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
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self] (view: Self, previousTraitCollection: UITraitCollection) in
                guard let self else { return }
                guard previousTraitCollection.userInterfaceStyle != view.traitCollection.userInterfaceStyle else { return }
                self.refreshAppearanceForCurrentTraits()
            }
        }
    }

    deinit {
        pendingRelayoutWorkItem?.cancel()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(iOS, introduced: 2.0, deprecated: 17.0)
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if #available(iOS 17.0, *) {
            return
        }
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else {
            return
        }
        refreshAppearanceForCurrentTraits()
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
        onSignatureLinkCandidatesTapped: (([DetailLinkCandidate]) -> Void)? = nil,
        onLayoutInvalidated: (() -> Void)?,
        onAttachmentLayoutUpdated: ((URL, CGSize, CGSize) -> Void)? = nil
    ) {
        pendingRelayoutWorkItem?.cancel()
        imageTapHandler = onImageTapped
        linkTapHandler = onLinkTapped
        signatureLinkCandidatesTapHandler = onSignatureLinkCandidatesTapped
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

    #if DEBUG
    func debugHandleLoadedImage(_ url: URL, imageSize: CGSize) {
        handleLoadedImage(url, imageSize: imageSize)
    }
    #endif

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

        let imageKind = DetailImageKind.resolved(isSticker: isStickerAttachment, imageURL: contentURL)
        let imageView = DetailInlineImageView(
            frame: viewFrame,
            imageURL: contentURL,
            targetPixelWidth: targetImagePointSide(
                originalSize: attachment.originalSize,
                kind: imageKind
            ) * displayScale,
            displayScale: displayScale,
            allowsInlineAnimation: allowsInlineAnimation(
                originalSize: attachment.originalSize,
                kind: imageKind
            ),
            usesDetailImageOptimization: imageKind == .normal,
            onImageLoaded: { [weak self] loadedURL, imageSize in
                self?.handleLoadedImage(loadedURL, imageSize: imageSize)
            },
            onImageTapped: { [weak self] tappedURL in
                self?.handleImageTap(tappedURL)
            }
        )
        imageView.contentMode = contentMode(
            originalSize: attachment.originalSize,
            kind: imageKind
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
        DetailLinkOverlayButton(frame: frame, url: url) { [weak self] button, tappedURL, point in
            self?.handleLinkTap(button: button, tappedURL: tappedURL, at: point)
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if super.point(inside: point, with: event) {
            return true
        }
        return signatureLinkOverlayButtons().contains { button in
            button.expandedHitFrame.contains(point)
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
        if shouldRecordStickerAspectRatio(for: url) {
            stickerAspectRatioProvider.recordLoadedSize(imageSize, for: url)
        }

        guard let update = updateImageAttachments(matching: url, originalSize: imageSize) else {
            logDiagnostics(
                "imageLoaded noAttachmentUpdate url=\(url.absoluteString) imageSize=\(Self.string(from: imageSize)) attachments=\(attachmentDiagnostics())"
            )
            return
        }
        guard update.requiresRelayout else {
            logDiagnostics(
                "imageLoaded metadataOnly url=\(url.absoluteString) imageSize=\(Self.string(from: imageSize)) display=\(Self.string(from: update.displaySize))"
            )
            return
        }
        logDiagnostics(
            "imageLoaded updated url=\(url.absoluteString) imageSize=\(Self.string(from: imageSize)) display=\(Self.string(from: update.displaySize))"
        )
        attachmentLayoutUpdatedHandler?(url, imageSize, update.displaySize)
        scheduleDebouncedRelayout(reason: "imageLoaded")
    }

    private func scheduleDebouncedRelayout(reason: String) {
        pendingRelayoutWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.removeAllCustomViews()
            self.removeAllCustomViewsForLinks()
            self.layouter = nil
            self.relayoutText()
            self.invalidateIntrinsicContentSize()
            self.logDiagnostics(
                "\(reason) relayout intrinsic=\(Self.string(from: self.intrinsicContentSize)) bounds=\(Self.string(from: self.bounds.size))"
            )
            self.setNeedsLayout()
            self.layoutInvalidatedHandler?()
        }
        pendingRelayoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + RelayoutDebounce.interval, execute: workItem)
    }

    private func updateImageAttachments(matching url: URL, originalSize: CGSize) -> ImageAttachmentUpdate? {
        guard attributedString.length > 0,
              originalSize.width > 0,
              originalSize.height > 0 else {
            return nil
        }

        var updatedAttachment: ImageAttachmentUpdate?
        attributedString.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributedString.length)
        ) { value, range, _ in
            guard let attachment = value as? DTTextAttachment,
                  attachment.contentURL == url else {
                return
            }

            let isSticker = isStickerAttachment(attachment, contentURL: url)
            let imageKind = DetailImageKind.resolved(isSticker: isSticker, imageURL: url)
            let isFixedQuoteImage = (attributedString.attribute(
                DetailAttachmentAttributes.fixedQuoteImage,
                at: range.location,
                effectiveRange: nil
            ) as? Bool) == true
            if isFixedQuoteImage, imageKind == .normal {
                let currentDisplaySize = attachment.displaySize
                let hasValidDisplaySize = currentDisplaySize.width > 0 && currentDisplaySize.height > 0
                if hasValidDisplaySize == false {
                    let fixedSize = DetailImageLayout.fixedNormalImageSize(
                        maxWidth: maxImageWidth()
                    )
                    attachment.displaySize = fixedSize
                    updatedAttachment = Self.merging(
                        updatedAttachment,
                        with: ImageAttachmentUpdate(displaySize: fixedSize, requiresRelayout: true)
                    )
                }
                if attachment.originalSize != originalSize {
                    attachment.originalSize = originalSize
                    updatedAttachment = Self.merging(
                        updatedAttachment,
                        with: ImageAttachmentUpdate(displaySize: attachment.displaySize, requiresRelayout: true)
                    )
                }
                return
            }
            let presentation = DetailImageLayout.presentation(
                for: originalSize,
                maxWidth: maxImageWidth(),
                kind: imageKind
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

            let displaySizeChanged = Self.layoutSizeNeedsUpdate(
                from: attachment.displaySize,
                to: displaySize
            )
            attachment.originalSize = originalSize
            if displaySizeChanged {
                attachment.displaySize = displaySize
            }
            updatedAttachment = Self.merging(
                updatedAttachment,
                with: ImageAttachmentUpdate(displaySize: attachment.displaySize, requiresRelayout: displaySizeChanged)
            )
        }
        return updatedAttachment
    }

    private func shouldRecordStickerAspectRatio(for url: URL) -> Bool {
        if isStickerImageURL(url) {
            return true
        }

        var shouldRecord = false
        attributedString.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributedString.length)
        ) { value, _, stop in
            guard let attachment = value as? DTTextAttachment,
                  attachment.contentURL == url,
                  isStickerAttachment(attachment, contentURL: url) else {
                return
            }
            shouldRecord = true
            stop.pointee = true
        }
        return shouldRecord
    }

    private static func merging(
        _ existing: ImageAttachmentUpdate?,
        with update: ImageAttachmentUpdate
    ) -> ImageAttachmentUpdate {
        ImageAttachmentUpdate(
            displaySize: update.displaySize,
            requiresRelayout: (existing?.requiresRelayout ?? false) || update.requiresRelayout
        )
    }

    private static func layoutSizeNeedsUpdate(from currentSize: CGSize, to newSize: CGSize) -> Bool {
        abs(currentSize.width - newSize.width) >= 0.5 || abs(currentSize.height - newSize.height) >= 0.5
    }

    private func handleImageTap(_ tappedURL: URL) {
        guard let onImageTapped = imageTapHandler,
              let resolvedTappedURL = ImageURLResolver.resolve(tappedURL) else {
            return
        }

        let urls = previewImageURLs()
        guard let index = urls.firstIndex(of: resolvedTappedURL) else { return }
        onImageTapped(urls, index)
    }

    private func handleLinkTap(button: DetailLinkOverlayButton, tappedURL: URL, at point: CGPoint) {
        guard isSignatureLinkOverlay(button) else {
            linkTapHandler?(tappedURL)
            return
        }

        let candidates = signatureLinkCandidates(near: point)
        if candidates.count > 1 {
            if let signatureLinkCandidatesTapHandler {
                signatureLinkCandidatesTapHandler(candidates)
            } else {
                linkTapHandler?(tappedURL)
            }
            return
        }

        linkTapHandler?(candidates.first?.url ?? tappedURL)
    }

    func debugSignatureLinkCandidates(near point: CGPoint) -> [DetailLinkCandidate] {
        signatureLinkCandidates(near: point)
    }

    fileprivate func isSignatureLinkOverlay(_ button: DetailLinkOverlayButton) -> Bool {
        let location = button.tag
        guard location >= 0, location < attributedString.length else { return false }
        guard (attributedString.attribute(
            NodeSeekSignatureStyle.linkAttribute,
            at: location,
            effectiveRange: nil
        ) as? Bool) == true else {
            return false
        }
        return Self.linkURL(from: attributedString.attribute(.link, at: location, effectiveRange: nil)) == button.url
    }

    private func signatureLinkCandidates(near point: CGPoint) -> [DetailLinkCandidate] {
        let buttons = signatureLinkOverlayButtons(near: point)
        guard buttons.isEmpty == false else { return [] }

        var candidates: [DetailLinkCandidate] = []
        for button in buttons {
            let candidate = DetailLinkCandidate(
                title: title(for: button),
                subtitle: button.url.absoluteString,
                url: button.url
            )
            guard candidates.contains(candidate) == false else { continue }
            candidates.append(candidate)
        }
        return candidates
    }

    private func signatureLinkOverlayButtons(near point: CGPoint? = nil) -> [DetailLinkOverlayButton] {
        subviews
            .compactMap { $0 as? DetailLinkOverlayButton }
            .filter { button in
                guard isSignatureLinkOverlay(button) else { return false }
                guard let point else { return true }
                return button.expandedHitFrame.contains(point)
            }
            .sorted { lhs, rhs in
                if abs(lhs.frame.minY - rhs.frame.minY) > 0.5 {
                    return lhs.frame.minY < rhs.frame.minY
                }
                return lhs.frame.minX < rhs.frame.minX
            }
    }

    private func title(for button: DetailLinkOverlayButton) -> String {
        let location = button.tag
        guard location >= 0, location < attributedString.length else {
            return Self.fallbackTitle(for: button.url)
        }

        var range = NSRange(location: 0, length: 0)
        guard Self.linkURL(from: attributedString.attribute(.link, at: location, effectiveRange: &range)) == button.url,
              range.location != NSNotFound,
              range.length > 0 else {
            return Self.fallbackTitle(for: button.url)
        }

        let rawTitle = (attributedString.string as NSString).substring(with: range)
        return Self.nonEmptyTitle(rawTitle) ?? Self.fallbackTitle(for: button.url)
    }

    nonisolated private static func linkURL(from value: Any?) -> URL? {
        if let url = value as? URL {
            return url
        }
        if let string = value as? String {
            return URL(string: string)
        }
        return nil
    }

    nonisolated private static func nonEmptyTitle(_ title: String?) -> String? {
        guard let title else { return nil }
        let normalized = title
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
        return normalized.isEmpty ? nil : normalized
    }

    nonisolated private static func fallbackTitle(for url: URL) -> String {
        if let host = url.host, host.isEmpty == false {
            return host
        }
        return url.absoluteString
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
                  let resolvedURL = ImageURLResolver.resolve(contentURL),
                  isVideoURL(resolvedURL) == false,
                  isStickerAttachment(attachment, contentURL: resolvedURL) == false,
                  urls.contains(resolvedURL) == false else {
                return
            }
            urls.append(resolvedURL)
        }
        return urls
    }

    private func maxImageWidth() -> CGFloat {
        bounds.width > 0 ? bounds.width : 320
    }

    private func targetImagePointSide(originalSize: CGSize, kind: DetailImageKind) -> CGFloat {
        let maxWidth = maxImageWidth()
        guard originalSize.width > 0, originalSize.height > 0 else {
            return kind == .sticker
                ? DetailImageLayout.presentation(for: .zero, maxWidth: maxWidth, kind: .sticker).targetPointSide
                : max(maxWidth, DetailImageLayout.maxImageHeight)
        }

        return DetailImageLayout.presentation(
            for: originalSize,
            maxWidth: maxWidth,
            kind: kind
        ).targetPointSide
    }

    private func allowsInlineAnimation(originalSize: CGSize, kind: DetailImageKind) -> Bool {
        guard kind == .sticker || (originalSize.width > 0 && originalSize.height > 0) else { return false }
        return DetailImageLayout.allowsInlineAnimation(
            for: originalSize,
            maxWidth: maxImageWidth(),
            kind: kind
        )
    }

    private func contentMode(originalSize: CGSize, kind: DetailImageKind) -> UIView.ContentMode {
        let mode = DetailImageLayout.presentation(
            for: originalSize,
            maxWidth: maxImageWidth(),
            kind: kind
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
        StickerImageRules.isStickerURL(url)
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
        AppLog.info(.rendering, "[\(diagnosticID)] \(message)")
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
    private enum HitArea {
        static let minimumSize = CGSize(width: 72, height: 48)
    }

    fileprivate let url: URL
    private let onTapped: (DetailLinkOverlayButton, URL, CGPoint) -> Void

    var expandedHitFrame: CGRect {
        let insetX = min(0, (frame.width - HitArea.minimumSize.width) / 2)
        let insetY = min(0, (frame.height - HitArea.minimumSize.height) / 2)
        return frame.insetBy(dx: insetX, dy: insetY)
    }

    private var expandedHitBounds: CGRect {
        let insetX = min(0, (bounds.width - HitArea.minimumSize.width) / 2)
        let insetY = min(0, (bounds.height - HitArea.minimumSize.height) / 2)
        return bounds.insetBy(dx: insetX, dy: insetY)
    }

    init(frame: CGRect, url: URL, onTapped: @escaping (DetailLinkOverlayButton, URL, CGPoint) -> Void) {
        self.url = url
        self.onTapped = onTapped
        super.init(frame: frame)
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard let richTextView = superview as? DetailRichTextView,
              richTextView.isSignatureLinkOverlay(self) else {
            return super.point(inside: point, with: event)
        }
        return expandedHitBounds.contains(point)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else {
            super.touchesEnded(touches, with: event)
            return
        }
        let localPoint = touch.location(in: self)
        guard point(inside: localPoint, with: event) else {
            super.touchesEnded(touches, with: event)
            return
        }
        let parentPoint = superview.map { convert(localPoint, to: $0) } ?? frame.center
        onTapped(self, url, parentPoint)
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
