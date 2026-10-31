//
//  PostSummaryText.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import UIKit

/// 帖子列表行的标题与元信息富文本，首页、搜索列表共用。
enum PostSummaryText {
    static func metadataAttributedText(
        for post: PostSummary,
        specialFollowRules: [SpecialFollowKeywordRule] = []
    ) -> NSAttributedString {
        let font = PostListCellStyle.Typography.metadataFont
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.secondaryLabel
        ]
        let metadata = NSMutableAttributedString()

        func appendSeparatorIfNeeded() {
            guard metadata.length > 0 else { return }
            metadata.append(NSAttributedString(string: "  ", attributes: attributes))
        }

        if let authorName = AuthorDisplayPolicy.displayName(from: post.authorName) {
            appendSeparatorIfNeeded()
            metadata.append(SpecialFollowKeywordHighlighter.attributedText(
                string: authorName,
                baseAttributes: attributes,
                rules: specialFollowRules
            ))
        }

        appendSeparatorIfNeeded()
        metadata.append(metricAttributedText(
            systemName: "eye",
            value: post.viewCount,
            font: font,
            attributes: attributes
        ))

        appendSeparatorIfNeeded()
        metadata.append(metricAttributedText(
            systemName: "bubble.left",
            value: post.replyCount,
            font: font,
            attributes: attributes
        ))

        if let lastActivity = lastActivityText(for: post) {
            appendSeparatorIfNeeded()
            metadata.append(NSAttributedString(string: lastActivity, attributes: attributes))
        }

        return metadata
    }

    static func titleAttributedText(
        for post: PostSummary,
        isVisited: Bool = false,
        specialFollowRules: [SpecialFollowKeywordRule] = []
    ) -> NSAttributedString {
        let font = PostListCellStyle.Typography.titleFont
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: isVisited ? UIColor.secondaryLabel : UIColor.label
        ]
        let title = NSMutableAttributedString()

        if post.isPinned {
            appendSymbol(
                "pin.fill",
                tintColor: .secondaryLabel,
                font: font,
                rotationAngle: .pi / 4,
                to: title
            )
            title.append(NSAttributedString(string: " ", attributes: attributes))
        }

        title.append(NSAttributedString(string: post.title, attributes: attributes))
        SpecialFollowKeywordHighlighter.applyHighlight(to: title, rules: specialFollowRules)

        guard post.isLocked else {
            return title
        }

        title.append(NSAttributedString(string: " ", attributes: attributes))

        appendSymbol(
            "lock.fill",
            tintColor: .systemRed,
            font: font,
            to: title
        )

        if let requiredReadingLevel = post.requiredReadingLevel {
            title.append(NSAttributedString(
                string: " \(requiredReadingLevel)",
                attributes: [
                    .font: font,
                    .foregroundColor: UIColor.systemRed
                ]
            ))
        }

        return title
    }

    // 首屏或字号变化后先统一预热，滚动时只复用缓存位图。
    static func prewarmSymbolImages() {
        ListSymbolImageRasterizer.shared.prewarm(
            titleFont: PostListCellStyle.Typography.titleFont,
            metadataFont: PostListCellStyle.Typography.metadataFont
        )
    }

    private static func appendSymbol(
        _ systemName: String,
        tintColor: UIColor,
        font: UIFont,
        rotationAngle: CGFloat = 0,
        to text: NSMutableAttributedString
    ) {
        guard let displayImage = ListSymbolImageRasterizer.shared.image(
            systemName: systemName,
            tintColor: tintColor,
            font: font,
            rotationAngle: rotationAngle
        ) else {
            return
        }

        let attachment = NSTextAttachment(image: displayImage)
        attachment.bounds = CGRect(
            x: 0,
            y: (font.capHeight - displayImage.size.height) / 2,
            width: displayImage.size.width,
            height: displayImage.size.height
        )
        text.append(NSAttributedString(attachment: attachment))
    }

    private static func metricAttributedText(
        systemName: String,
        value: Int,
        font: UIFont,
        attributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let text = NSMutableAttributedString()
        appendSymbol(
            systemName,
            tintColor: .secondaryLabel,
            font: font,
            to: text
        )
        if text.length > 0 {
            text.append(NSAttributedString(string: " ", attributes: attributes))
        }
        text.append(NSAttributedString(string: "\(value)", attributes: attributes))
        return text
    }

    private static func lastActivityText(for post: PostSummary) -> String? {
        let trimmed = post.lastActivityText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum PostListCellStyle {
    enum Typography {
        static let titleMaximumNumberOfLines: UInt = 0
        static let metadataMaximumNumberOfLines: UInt = 1
        static let titlePointSize: CGFloat = 17
        static let metadataPointSize: CGFloat = 13
        static let titleWeight = UIFont.Weight.medium
        static let metadataWeight = UIFont.Weight.regular

        static var titleFont: UIFont {
            AppTypography.listTitleFont()
        }

        static var metadataFont: UIFont {
            AppTypography.listMetadataFont()
        }
    }

    enum Avatar {
        static let size: CGFloat = 48
        static let cornerRadius: CGFloat = 9
        static let skeletonSize: CGFloat = 48
    }

    enum Layout {
        static let horizontalSpacing: CGFloat = 10
        static let verticalContentInset: CGFloat = 8
    }
}

typealias PostSummaryCellStyle = PostListCellStyle

/// 把列表系统符号预先画成位图。
/// 系统矢量符号绘制不是线程安全的；位图可缓存，也能被任意线程的富文本安全复用。
private final class ListSymbolImageRasterizer: @unchecked Sendable {
    static let shared = ListSymbolImageRasterizer()

    private let lock = NSLock()
    private var cache: [ListSymbolImageKey: UIImage] = [:]
    // 串行栅格化。系统矢量符号绘制不是线程安全的，不能并行画。
    private let rasterizeQueue = DispatchQueue(label: "com.nodeseek.app.list-symbol-rasterizer")

    func prewarm(titleFont: UIFont, metadataFont: UIFont) {
        _ = image(systemName: "eye", tintColor: .secondaryLabel, font: metadataFont, rotationAngle: 0)
        _ = image(systemName: "bubble.left", tintColor: .secondaryLabel, font: metadataFont, rotationAngle: 0)
        _ = image(systemName: "pin.fill", tintColor: .secondaryLabel, font: titleFont, rotationAngle: .pi / 4)
        _ = image(systemName: "lock.fill", tintColor: .systemRed, font: titleFont, rotationAngle: 0)
    }

    func image(
        systemName: String,
        tintColor: UIColor,
        font: UIFont,
        rotationAngle: CGFloat
    ) -> UIImage? {
        let resolvedColor = tintColor.resolvedColor(with: .current)
        let scale = currentScale()
        let key = ListSymbolImageKey(
            systemName: systemName,
            fontName: font.fontName,
            pointSize: font.pointSize,
            tintColor: resolvedColor,
            scale: scale,
            rotationAngle: rotationAngle
        )

        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        // 不回主线程等待，避免调用方在主线程同步等待时互相卡住。
        return rasterizeQueue.sync {
            lock.lock()
            if let cached = cache[key] {
                lock.unlock()
                return cached
            }
            lock.unlock()

            guard let rasterized = rasterize(
                systemName: systemName,
                tintColor: resolvedColor,
                font: font,
                scale: scale,
                rotationAngle: rotationAngle
            ) else {
                return nil
            }

            lock.lock()
            cache[key] = rasterized
            lock.unlock()
            return rasterized
        }
    }

    private func rasterize(
        systemName: String,
        tintColor: UIColor,
        font: UIFont,
        scale: CGFloat,
        rotationAngle: CGFloat
    ) -> UIImage? {
        let configuration = UIImage.SymbolConfiguration(font: font, scale: .small)
        guard let symbol = UIImage(systemName: systemName, withConfiguration: configuration)?
            .withTintColor(tintColor, renderingMode: .alwaysOriginal) else {
            return nil
        }

        let sourceSize = symbol.size
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return nil
        }

        let rotatedRect = CGRect(origin: .zero, size: sourceSize)
            .applying(CGAffineTransform(rotationAngle: rotationAngle))
        let canvasSize = CGSize(
            width: max(1, ceil(abs(rotatedRect.width))),
            height: max(1, ceil(abs(rotatedRect.height)))
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false

        let rasterized = UIGraphicsImageRenderer(size: canvasSize, format: format).image { context in
            let cgContext = context.cgContext
            cgContext.translateBy(x: canvasSize.width / 2, y: canvasSize.height / 2)
            if rotationAngle != 0 {
                cgContext.rotate(by: rotationAngle)
            }
            symbol.draw(in: CGRect(
                x: -sourceSize.width / 2,
                y: -sourceSize.height / 2,
                width: sourceSize.width,
                height: sourceSize.height
            ))
        }

        // 只把确认后的位图放进附件，矢量图在并发绘制时仍可能崩。
        guard rasterized.cgImage != nil, rasterized.isSymbolImage == false else {
            return nil
        }
        return rasterized
    }

    private func currentScale() -> CGFloat {
        let scale = UITraitCollection.current.displayScale
        return scale > 0 ? scale : UIScreen.main.scale
    }
}

private struct ListSymbolImageKey: Hashable {
    var systemName: String
    var fontName: String
    var pointSize: Int
    var red: Int
    var green: Int
    var blue: Int
    var alpha: Int
    var scale: Int
    var rotation: Int

    init(
        systemName: String,
        fontName: String,
        pointSize: CGFloat,
        tintColor: UIColor,
        scale: CGFloat,
        rotationAngle: CGFloat
    ) {
        let rgbColor = tintColor.cgColor.converted(
            to: CGColorSpaceCreateDeviceRGB(),
            intent: .defaultIntent,
            options: nil
        ) ?? tintColor.cgColor
        let components = rgbColor.components ?? [0, 0, 0, 1]
        let red = components[0]
        let green = components.count > 2 ? components[1] : components[0]
        let blue = components.count > 2 ? components[2] : components[0]
        let alpha = rgbColor.alpha

        self.systemName = systemName
        self.fontName = fontName
        self.pointSize = Int((pointSize * 100).rounded())
        self.red = Int((red * 255).rounded())
        self.green = Int((green * 255).rounded())
        self.blue = Int((blue * 255).rounded())
        self.alpha = Int((alpha * 255).rounded())
        self.scale = Int((scale * 100).rounded())
        self.rotation = Int((rotationAngle * 1000).rounded())
    }
}
