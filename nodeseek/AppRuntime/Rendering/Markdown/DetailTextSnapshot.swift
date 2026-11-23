import UIKit

// 后台任务独占 TextKit 对象，视图只接收位图、字符范围及其几何位置。
nonisolated struct DetailTextSnapshot: Sendable {
    nonisolated struct Tile: Sendable {
        let rect: CGRect
        let image: CGImage
    }

    nonisolated struct CharacterBox: Sendable {
        let range: NSRange
        let rect: CGRect
        let line: Int
        let rtl: Bool
        let link: URL?
    }

    nonisolated struct Sticker: Sendable {
        let range: NSRange
        let rect: CGRect
        let token: String
        let url: URL
    }

    let string: String
    let size: CGSize
    let tiles: [Tile]
    let characters: [CharacterBox]
    let stickers: [Sticker]
    nonisolated struct Line: Sendable {
        let characters: Range<Int>
        let maxY: CGFloat
    }

    let lines: [Line]

    func characterIndex(at offset: Int) -> Int {
        var lower = 0
        var upper = characters.count
        while lower < upper {
            let mid = (lower + upper) / 2
            if NSMaxRange(characters[mid].range) <= offset { lower = mid + 1 } else { upper = mid }
        }
        return min(lower, characters.count - 1)
    }

    func line(at y: CGFloat) -> Range<Int>? {
        guard !lines.isEmpty else { return nil }
        var lower = 0
        var upper = lines.count
        while lower < upper {
            let mid = (lower + upper) / 2
            if lines[mid].maxY <= y { lower = mid + 1 } else { upper = mid }
        }
        return lines[min(lower, lines.count - 1)].characters
    }

    func copyText(in range: NSRange) -> String {
        let result = NSMutableString(string: (string as NSString).substring(with: range))
        for sticker in stickers.reversed() where NSIntersectionRange(range, sticker.range).length > 0 {
            result.replaceCharacters(in: NSRange(location: sticker.range.location - range.location, length: 1), with: sticker.token)
        }
        return result as String
    }
}

nonisolated struct DetailTextAppearance: Sendable, Equatable {
    let width: CGFloat
    let pointSize: CGFloat
    let scale: CGFloat
    let dark: Bool
}

nonisolated struct DetailTextSegment: Sendable {
    let runs: [DetailDocument.Inline]
    let pointSize: CGFloat
    var isListItem = false
    var isHeading = false
    var isAccentHeading = false
    var endsList = false
    var inQuote = false
    /// 列表嵌套层级，1 为顶层；每深一层整体右移一个悬挂缩进。
    var listLevel = 1
    /// 签名沿用旧版样式：统一常规字重、次要文字色和签名链接色，段落紧凑。
    var isSignature = false

    // 与旧版网页样式表一致：段落后 12，标题前 18、后 8，列表项之间 6。
    var spacingBefore: CGFloat { isHeading ? 18 : 0 }
    var spacingAfter: CGFloat { isSignature ? 2 : isHeading ? 8 : (isListItem && !endsList ? 6 : 12) }
}

nonisolated enum DetailTextTypesetter {
    // 使用自有属性保存跳转目标，避免 NSLayoutManager 强制覆盖站点链接颜色及下划线。
    private static let linkTarget = NSAttributedString.Key("DetailTextLinkTarget")

    // 附件只负责预留空间。显式透明图避免 TextKit 在媒体视图下绘制默认文件图标。
    private static let attachmentPlaceholder: UIImage = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1), format: format).image { _ in }
    }()


    static func layout(_ segments: [DetailTextSegment], appearance: DetailTextAppearance,
                       width: CGFloat) throws -> DetailTextSnapshot {
        let traits = UITraitCollection(userInterfaceStyle: appearance.dark ? .dark : .light)
        let color = ReadingColors.text.resolvedColor(with: traits)
        let linkColor = NodeSeekLinkStyle.color.resolvedColor(with: traits)
        let storage = NSTextStorage()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = DTCoreTextHTMLContentRenderer.Layout.bodyLineSpacing
        var attachments: [(index: Int, size: CGSize, token: String, url: URL)] = []
        for (index, segment) in segments.enumerated() {
            if index > 0 {
                // 两个换行保留复制出的段落。空行单独测量，避免按正文字号撑高。
                let gap = NSMutableParagraphStyle()
                gap.minimumLineHeight = segments[index-1].spacingAfter + segment.spacingBefore
                gap.maximumLineHeight = gap.minimumLineHeight
                storage.append(NSAttributedString(string: "\n", attributes: [.font: UIFont.systemFont(ofSize: segments[index-1].pointSize), .paragraphStyle: paragraph]))
                storage.append(NSAttributedString(string: "\n", attributes: [.font: UIFont.systemFont(ofSize: 1), .paragraphStyle: gap]))
            }
            let pointSize = segment.pointSize
            let start = storage.length
            let foreground = segment.isSignature ? NodeSeekSignatureStyle.textColor.resolvedColor(with: traits)
                : segment.isAccentHeading ? (appearance.dark ? UIColor.systemGreen.resolvedColor(with: traits) : NodeSeekLinkStyle.color) : color
            let runLinkColor = segment.isSignature ? NodeSeekSignatureStyle.linkColor.resolvedColor(with: traits) : linkColor
            for run in segment.runs {
                switch run {
                case let .text(string, style, url):
                    var font = style.contains(.code) ? UIFont.monospacedSystemFont(ofSize: pointSize, weight: .regular) : UIFont.systemFont(ofSize: pointSize)
                    var options = font.fontDescriptor.symbolicTraits
                    if style.contains(.bold) && !segment.isSignature { options.insert(.traitBold) }
                    if style.contains(.italic) && !segment.isSignature { options.insert(.traitItalic) }
                    if let descriptor = font.fontDescriptor.withSymbolicTraits(options) {
                        font = UIFont(descriptor: descriptor, size: pointSize)
                    }
                    var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: url == nil ? foreground : runLinkColor]
                    if let url { attrs[linkTarget] = url }
                    if style.contains(.strike) { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                    storage.append(NSAttributedString(string: string, attributes: attrs))
                case let .sticker(token, url):
                    let original = StickerAspectRatioCache.shared.cachedSourceSize(for: url) ?? .zero
                    let size = DetailImageLayout.presentation(for: original, maxWidth: width, kind: .sticker).size
                    let attachment = NSTextAttachment()
                    attachment.image = attachmentPlaceholder
                    attachment.bounds = CGRect(origin: .zero, size: size)
                    attachments.append((storage.length, size, token, url))
                    storage.append(NSAttributedString(attachment: attachment))
                }
            }
            let style = paragraph.mutableCopy() as! NSMutableParagraphStyle
            // 旧版按 CSS line-height 排版：行高为字号乘倍数后取整，额外行距不再叠加。
            style.lineSpacing = 0
            // 旧版签名行距为 2，约为字号的 1.2 倍再加 2。
            style.minimumLineHeight = segment.isSignature ? ceil(pointSize * 1.2 + 2) : ceil(pointSize * (segment.isHeading ? 1.28 : 1.42))
            if segment.isListItem {
                // 旧版列表符号顶格，换行悬挂缩进 22；引用内不缩进。
                let nested = CGFloat(max(0, segment.listLevel - 1)) * 22
                style.firstLineHeadIndent = nested
                style.headIndent = nested + (segment.inQuote ? 0 : 22)
            }
            storage.addAttribute(.paragraphStyle, value: style, range: NSRange(location: start, length: storage.length - start))
        }
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: max(1, width), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        let height = max(1, ceil(layout.usedRect(for: container).maxY))
        let size = CGSize(width: max(1, width), height: height)
        let string = storage.string as NSString
        var characters: [DetailTextSnapshot.CharacterBox] = []
        var stickers: [DetailTextSnapshot.Sticker] = []
        var index = 0
        var attachmentIndex = 0
        while index < string.length {
            try Task.checkCancellation()
            let range = string.rangeOfComposedCharacterSequence(at: index)
            let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphs.length > 0 else { index = NSMaxRange(range); continue }
            var line = NSRange()
            let lineRect = layout.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: &line)
            var level: UInt8 = 0
            layout.getGlyphs(in: NSRange(location: glyphs.location, length: 1), glyphs: nil, properties: nil, characterIndexes: nil, bidiLevels: &level)
            var rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
            if attachmentIndex < attachments.count, attachments[attachmentIndex].index == index {
                let attachment = attachments[attachmentIndex]
                let baseline = layout.location(forGlyphAt: glyphs.location)
                let frame = CGRect(origin: CGPoint(x: lineRect.minX + baseline.x, y: lineRect.minY + baseline.y - attachment.size.height), size: attachment.size)
                stickers.append(.init(range: range, rect: frame, token: attachment.token, url: attachment.url))
                rect = frame
                attachmentIndex += 1
            } else if let font = storage.attribute(.font, at: index, effectiveRange: nil) as? UIFont {
                // 同行的高表情不应把普通文字的选择手柄顶到附件上沿。
                let baseline = lineRect.minY + layout.location(forGlyphAt: glyphs.location).y
                rect.origin.y = max(lineRect.minY, baseline - font.ascender)
                rect.size.height = max(0, min(lineRect.maxY, baseline - font.descender) - rect.minY)
            }
            rect.size.width = max(1, rect.width)
            characters.append(.init(range: range, rect: rect, line: line.location, rtl: level % 2 == 1, link: storage.attribute(linkTarget, at: index, effectiveRange: nil) as? URL))
            index = NSMaxRange(range)
        }

        var tiles: [DetailTextSnapshot.Tile] = []
        let format = UIGraphicsImageRendererFormat()
        format.scale = appearance.scale
        format.opaque = false
        var y: CGFloat = 0
        while y < height {
            try Task.checkCancellation()
            let rect = CGRect(x: 0, y: y, width: size.width, height: min(384, height - y))
            let glyphRange = layout.glyphRange(forBoundingRect: rect, in: container)
            let image = UIGraphicsImageRenderer(size: rect.size, format: format).image { _ in
                let origin = CGPoint(x: 0, y: -rect.minY)
                layout.drawBackground(forGlyphRange: glyphRange, at: origin)
                layout.drawGlyphs(forGlyphRange: glyphRange, at: origin)
            }
            if let cgImage = image.cgImage { tiles.append(.init(rect: rect, image: cgImage)) }
            y = rect.maxY
        }
        var lines: [DetailTextSnapshot.Line] = []
        var start = 0
        while start < characters.count {
            let glyph = characters[start].line
            var end = start + 1
            while end < characters.count, characters[end].line == glyph { end += 1 }
            // 附件与文字共享基线，但各自的底边不同。触点属于哪一行由整行的布局框决定。
            let rect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            lines.append(.init(characters: start..<end, maxY: rect.maxY))
            start = end
        }
        return .init(string: storage.string, size: size, tiles: tiles, characters: characters, stickers: stickers, lines: lines)
    }
}
