import Kingfisher
import UIKit

private final class DetailPosition: UITextPosition {
    let offset: Int
    let document: UUID
    init(_ offset: Int, document: UUID) { self.offset = offset; self.document = document }
}

private final class DetailRange: UITextRange {
    let value: NSRange
    let document: UUID
    init(_ value: NSRange, document: UUID) { self.value = value; self.document = document }
    override var start: UITextPosition { DetailPosition(value.location, document: document) }
    override var end: UITextPosition { DetailPosition(NSMaxRange(value), document: document) }
    override var isEmpty: Bool { value.length == 0 }
}

private final class DetailSelectionRect: UITextSelectionRect {
    let box: CGRect
    let direction: NSWritingDirection
    let first: Bool
    let last: Bool
    init(_ box: CGRect, rtl: Bool, first: Bool, last: Bool) {
        self.box = box
        direction = rtl ? .rightToLeft : .leftToRight
        self.first = first
        self.last = last
    }
    override var rect: CGRect { box }
    override var writingDirection: NSWritingDirection { direction }
    override var containsStart: Bool { first }
    override var containsEnd: Bool { last }
    override var isVertical: Bool { false }
}

private final class DetailAccessibleText: UIAccessibilityElement {
    var activate: (() -> Void)?
    override func accessibilityActivate() -> Bool {
        guard let activate else { return false }
        activate()
        return true
    }
}

final class DetailSelectableTextView: UIView, UITextInput, UITextInteractionDelegate, UIGestureRecognizerDelegate {
    let snapshot: DetailTextSnapshot
    private let onLink: (URL) -> Void
    /// 签名字小、链接常挨在一起：给每个链接至少这么大的点击区，重叠时交给 onLinkCandidates 让用户选。正文为 nil。
    var linkTargetSize: CGSize?
    var onLinkCandidates: (([DetailLinkCandidate]) -> Void)?
    private var selection: DetailRange?
    private weak var playbackViewport: UIView?
    private var gifs = [DetailInlineImageView]()
    private let selectionInteraction = UITextInteraction(for: .nonEditable)
    private let document = UUID()
    private var endOffset: Int { snapshot.characters.last.map { NSMaxRange($0.range) } ?? 0 }
    private func position(_ offset: Int) -> DetailPosition { DetailPosition(offset, document: document) }
    private func range(_ value: NSRange) -> DetailRange { DetailRange(value, document: document) }
    private func owns(_ position: UITextPosition) -> Bool { (position as? DetailPosition)?.document == document }
    weak var inputDelegate: UITextInputDelegate?
    lazy var tokenizer: UITextInputTokenizer = UITextInputStringTokenizer(textInput: self)
    var markedTextStyle: [NSAttributedString.Key: Any]?
    let markedTextRange: UITextRange? = nil
    var hasText: Bool { !snapshot.string.isEmpty }
    var isEditable: Bool { false }
    override var canBecomeFirstResponder: Bool { true }
    override var intrinsicContentSize: CGSize { snapshot.size }

    init(snapshot: DetailTextSnapshot, scale: CGFloat, onLink: @escaping (URL) -> Void, stickerSizeChanged: @escaping () -> Void) {
        self.snapshot = snapshot
        self.onLink = onLink
        super.init(frame: CGRect(origin: .zero, size: snapshot.size))
        for tile in snapshot.tiles {
            let layer = CALayer()
            layer.contents = tile.image
            layer.contentsScale = scale
            layer.frame = tile.rect
            self.layer.addSublayer(layer)
        }
        for sticker in snapshot.stickers {
            if ["mp4", "webm"].contains(sticker.url.pathExtension.lowercased()) {
                addSubview(DetailInlineVideoStickerView(frame: sticker.rect, videoURL: sticker.url))
            } else {
                let image = DetailInlineImageView(frame: sticker.rect, imageURL: sticker.url, targetPixelWidth: sticker.rect.width * scale,
                    displayScale: scale, allowsInlineAnimation: true, usesDetailImageOptimization: false,
                    onImageLoaded: { [weak self] url, size in
                        if let viewport = self?.playbackViewport { self?.updatePlayback(in: viewport) }
                        StickerAspectRatioCache.shared.recordLoadedSize(size, for: url)
                        guard let cached = StickerAspectRatioCache.shared.cachedSourceSize(for: url) else { return }
                        let measured = DetailImageLayout.presentation(for: cached, maxWidth: snapshot.size.width, kind: .sticker).size
                        if abs(measured.width - sticker.rect.width) > 0.5 { stickerSizeChanged() }
                    }, onImageTapped: { _ in })
                if sticker.url.pathExtension.lowercased() == "gif" {
                    image.autoPlayAnimatedImage = false
                    gifs.append(image)
                }
                image.isUserInteractionEnabled = false
                addSubview(image)
            }
        }
        selectionInteraction.delegate = self
        selectionInteraction.textInput = self
        addInteraction(selectionInteraction)
        let tap = UITapGestureRecognizer(target: self, action: #selector(openLink(_:)))
        tap.delegate = self
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func updatePlayback(in viewport: UIView) {
        playbackViewport = viewport
        for case let image as DetailInlineImageView in subviews {
            let visible = window != nil && viewport.bounds.intersects(image.convert(image.bounds, to: viewport))
            image.setPlaybackVisible(visible)
            if !image.autoPlayAnimatedImage {
                if visible { image.startAnimating() } else { image.stopAnimating() }
            }
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { gifs.forEach { $0.stopAnimating() } }
    }

    // UIKit 将 UITextInput 自动暴露为一个文本框。让外层容器负责逐段朗读和链接激活。
    func accessibleContainer() -> UIView {
        let container = UIView(frame: bounds)
        container.isAccessibilityElement = false
        container.addSubview(self)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: container.leadingAnchor),
            trailingAnchor.constraint(equalTo: container.trailingAnchor),
            topAnchor.constraint(equalTo: container.topAnchor),
            bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        var elements: [DetailAccessibleText] = []
        var start = 0
        let boxes = snapshot.characters
        while start < boxes.count {
            let link = boxes[start].link
            var end = start + 1
            var rect = boxes[start].rect
            while end < boxes.count && boxes[end].link == link {
                rect = rect.union(boxes[end].rect)
                end += 1
            }
            let element = DetailAccessibleText(accessibilityContainer: container)
            element.isAccessibilityElement = true
            element.accessibilityFrameInContainerSpace = rect
            element.accessibilityLabel = snapshot.copyText(in: NSUnionRange(boxes[start].range, boxes[end-1].range))
            element.accessibilityTraits = link == nil ? .staticText : .link
            if let link { element.activate = { [weak self] in self?.onLink(link) } }
            elements.append(element)
            start = end
        }
        container.accessibilityElements = elements
        return container
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        hasLink(at: touch.location(in: self))
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer is UITapGestureRecognizer
    }

    @objc private func openLink(_ tap: UITapGestureRecognizer) {
        activateLink(at: tap.location(in: self))
    }

    func hasLink(at point: CGPoint) -> Bool {
        linkTargetSize == nil ? linkHit(at: point) != nil : !linkCandidates(at: point).isEmpty
    }

    /// 打开该点的链接；放大点击区命中多个时交给 onLinkCandidates。返回是否命中了链接。
    @discardableResult
    func activateLink(at point: CGPoint) -> Bool {
        guard linkTargetSize != nil else {
            guard let hit = linkHit(at: point) else { return false }
            onLink(hit.url)
            return true
        }
        let candidates = linkCandidates(at: point)
        guard let first = candidates.first else { return false }
        if candidates.count > 1, let onLinkCandidates {
            onLinkCandidates(candidates)
        } else {
            onLink(first.url)
        }
        return true
    }

    /// 放大点击区包含该点的链接，按行和从左到右排列；同一行连续的同一链接合并为一段。
    func linkCandidates(at point: CGPoint) -> [DetailLinkCandidate] {
        guard let size = linkTargetSize, selection?.isEmpty != false else { return [] }
        var result: [DetailLinkCandidate] = []
        for segment in linkSegments {
            let rect = segment.rect
            var target = rect.insetBy(dx: min(0, (rect.width - size.width) / 2), dy: min(0, (rect.height - size.height) / 2))
            // 与旧版一致，向上不越过本段文字顶部，免得盖住上方正文的最后一行。
            let top = min(rect.minY, max(0, target.minY))
            target = CGRect(x: target.minX, y: top, width: target.width, height: target.maxY - top)
            guard target.contains(point) else { continue }
            let candidate = DetailLinkCandidate(title: segment.title, subtitle: segment.url.absoluteString, url: segment.url)
            if !result.contains(candidate) { result.append(candidate) }
        }
        return result
    }

    private lazy var linkSegments: [(url: URL, rect: CGRect, title: String)] = {
        var segments: [(url: URL, rect: CGRect, title: String)] = []
        let boxes = snapshot.characters
        var start = 0
        while start < boxes.count {
            guard let url = boxes[start].link else { start += 1; continue }
            var end = start + 1
            var rect = boxes[start].rect
            while end < boxes.count, boxes[end].link == url, boxes[end].line == boxes[start].line {
                rect = rect.union(boxes[end].rect)
                end += 1
            }
            let title = snapshot.copyText(in: NSUnionRange(boxes[start].range, boxes[end - 1].range))
            segments.append((url, rect, title.trimmingCharacters(in: .whitespacesAndNewlines)))
            start = end
        }
        return segments.sorted { abs($0.rect.minY - $1.rect.minY) > 0.5 ? $0.rect.minY < $1.rect.minY : $0.rect.minX < $1.rect.minX }
    }()

    static let linkHitPadding: CGFloat = 12

    /// 实际点中的文字优先；落在空隙时，才在邻近的排版行里找最近的链接。
    func linkHit(at point: CGPoint) -> (url: URL, distance: CGFloat)? {
        let padding = Self.linkHitPadding
        guard selection?.isEmpty != false,
              let first = snapshot.line(at: point.y - padding)?.lowerBound,
              let last = snapshot.line(at: point.y + padding)?.upperBound else { return nil }
        var closest: (url: URL, distance: CGFloat)?
        let string = snapshot.string as NSString
        for box in snapshot.characters[first..<last] {
            let rect = box.rect
            if rect.contains(point), box.link == nil {
                let unit = string.character(at: box.range.location)
                if !(CharacterSet.whitespacesAndNewlines as NSCharacterSet).characterIsMember(unit) { return nil }
            }
            guard let url = box.link else { continue }
            let dx = max(rect.minX - point.x, point.x - rect.maxX, 0)
            let dy = max(rect.minY - point.y, point.y - rect.maxY, 0)
            let distance = dx * dx + dy * dy
            if distance <= padding * padding, distance < closest?.distance ?? .infinity {
                closest = (url, distance)
            }
        }
        return closest
    }

    func interactionWillBegin(_ interaction: UITextInteraction) { becomeFirstResponder() }

    var selectedTextRange: UITextRange? {
        get { selection }
        set {
            let range = newValue as? DetailRange
            guard range == nil || range?.document == document else { return }
            guard range?.value != selection?.value else { return }
            inputDelegate?.selectionWillChange(self)
            selection = range
            inputDelegate?.selectionDidChange(self)
        }
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(copy(_:)) { return selection?.isEmpty == false }
        if action == #selector(selectAll(_:)) { return hasText }
        return false
    }
    override func copy(_ sender: Any?) {
        guard let range = selection?.value, range.length > 0 else { return }
        UIPasteboard.general.string = snapshot.copyText(in: range)
    }
    override func selectAll(_ sender: Any?) {
        selectedTextRange = self.range(NSRange(location: 0, length: endOffset))
    }
    var beginningOfDocument: UITextPosition { self.position(0) }
    var endOfDocument: UITextPosition { self.position(endOffset) }
    func text(in range: UITextRange) -> String? {
        guard let own = range as? DetailRange, own.document == document else { return nil }
        let range = own.value
        return (snapshot.string as NSString).substring(with: range)
    }
    func insertText(_ text: String) {}
    func deleteBackward() {}
    func replace(_ range: UITextRange, withText text: String) {}
    func setMarkedText(_ markedText: String?, selectedRange: NSRange) {}
    func unmarkText() {}
    func setBaseWritingDirection(_ writingDirection: NSWritingDirection, for range: UITextRange) {}

    private func index(_ position: UITextPosition) -> Int { (position as? DetailPosition)?.offset ?? 0 }
    func textRange(from fromPosition: UITextPosition, to toPosition: UITextPosition) -> UITextRange? {
        guard owns(fromPosition), owns(toPosition) else { return nil }
        let a = index(fromPosition), b = index(toPosition)
        return self.range(NSRange(location: min(a,b), length: abs(b-a)))
    }
    func position(from position: UITextPosition, offset: Int) -> UITextPosition? {
        guard owns(position) else { return nil }
        let (value, overflow) = index(position).addingReportingOverflow(offset)
        return !overflow && (0...endOffset).contains(value) ? self.position(value) : nil
    }
    func compare(_ position: UITextPosition, to other: UITextPosition) -> ComparisonResult {
        let delta = offset(from: position, to: other)
        return delta == 0 ? .orderedSame : (delta > 0 ? .orderedAscending : .orderedDescending)
    }
    func offset(from: UITextPosition, to toPosition: UITextPosition) -> Int { index(toPosition) - index(from) }

    private func box(at offset: Int) -> DetailTextSnapshot.CharacterBox? {
        guard !snapshot.characters.isEmpty else { return nil }
        return snapshot.characters[snapshot.characterIndex(at: offset)]
    }

    func caretRect(for position: UITextPosition) -> CGRect {
        let offset = index(position)
        guard let box = box(at: offset) else { return .zero }
        let atEnd = offset >= NSMaxRange(box.range)
        return CGRect(x: atEnd != box.rtl ? box.rect.maxX : box.rect.minX, y: box.rect.minY, width: 1, height: box.rect.height)
    }
    func baseWritingDirection(for position: UITextPosition, in direction: UITextStorageDirection) -> NSWritingDirection {
        (box(at: index(position))?.rtl ?? false) ? .rightToLeft : .leftToRight
    }
    func position(from position: UITextPosition, in direction: UITextLayoutDirection, offset: Int) -> UITextPosition? {
        var p = position
        var dir = direction
        if offset < 0 {
            switch dir { case .left: dir = .right; case .right: dir = .left; case .up: dir = .down; default: dir = .up }
        }
        guard offset.magnitude <= snapshot.characters.count else { return nil }
        for _ in 0..<offset.magnitude {
            guard let box = box(at: index(p)) else { return nil }
            if dir == .up || dir == .down {
                let next = dir == .up ? snapshot.characters.last(where: { $0.line < box.line }) : snapshot.characters.first(where: { $0.line > box.line })
                guard let next, let hit = closestPosition(to: CGPoint(x: caretRect(for: p).minX, y: next.rect.midY)) else { return nil }
                p = hit
            } else if (dir == .right) != box.rtl {
                guard index(p) < endOffset else { return nil }
                p = self.position(NSMaxRange(box.range))
            } else {
                guard index(p) > 0, let previous = self.box(at: index(p)-1) else { return nil }
                p = self.position(previous.range.location)
            }
        }
        return p
    }
    func position(within range: UITextRange, farthestIn direction: UITextLayoutDirection) -> UITextPosition? {
        let rtl = baseWritingDirection(for: range.start, in: .forward) == .rightToLeft
        if direction == .up { return range.start }
        if direction == .down { return range.end }
        return (direction == .right) != rtl ? range.end : range.start
    }
    func characterRange(byExtending position: UITextPosition, in direction: UITextLayoutDirection) -> UITextRange? {
        guard let next = self.position(from: position, in: direction, offset: 1) else { return nil }
        return textRange(from: position, to: next)
    }
    func handlesTouch(at point: CGPoint) -> Bool {
        if selection?.isEmpty == false { return true }
        if linkTargetSize != nil, hasLink(at: point) { return true }
        // 仅用于手势起点。保留字边缘容差，拖选仍由 UITextInput 按最近字符定位。
        let tolerance: CGFloat = 5
        guard let first = snapshot.line(at: point.y - tolerance)?.lowerBound,
              let last = snapshot.line(at: point.y + tolerance)?.upperBound else { return false }
        return snapshot.characters[first..<last].contains { box in
            guard box.rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point) else { return false }
            return (snapshot.string as NSString).character(at: box.range.location) != 10
        }
    }

    private func nearest(_ point: CGPoint) -> DetailTextSnapshot.CharacterBox? {
        guard let line = snapshot.line(at: point.y) else { return nil }
        return snapshot.characters[line].min { abs(point.x - $0.rect.midX) < abs(point.x - $1.rect.midX) }
    }
    func closestPosition(to point: CGPoint) -> UITextPosition? {
        guard let box = nearest(point) else { return beginningOfDocument }
        let trailing = (point.x > box.rect.midX) != box.rtl
        return self.position(trailing ? NSMaxRange(box.range) : box.range.location)
    }
    func closestPosition(to point: CGPoint, within range: UITextRange) -> UITextPosition? {
        guard let p = closestPosition(to: point) else { return nil }
        return self.position(min(index(range.end), max(index(range.start), index(p))))
    }
    func characterRange(at point: CGPoint) -> UITextRange? { nearest(point).map { self.range($0.range) } }
    func firstRect(for range: UITextRange) -> CGRect { selectionRects(for: range).first?.rect ?? caretRect(for: range.start) }
    func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
        guard let own = range as? DetailRange, own.document == document, own.value.length > 0 else { return [] }
        let lower = snapshot.characterIndex(at: own.value.location)
        let upper = snapshot.characterIndex(at: NSMaxRange(own.value) - 1)
        let boxes = snapshot.characters[lower...upper]
        var results: [DetailSelectionRect] = []
        var start = boxes.startIndex
        while start < boxes.endIndex {
            let first = boxes[start]
            var end = start + 1
            var rect = first.rect
            while end < boxes.endIndex, boxes[end].line == first.line, boxes[end].rtl == first.rtl,
                  rect.insetBy(dx: -1, dy: -1).intersects(boxes[end].rect) {
                rect = rect.union(boxes[end].rect)
                end += 1
            }
            results.append(.init(rect, rtl: first.rtl, first: start == boxes.startIndex, last: end == boxes.endIndex))
            start = end
        }
        return results
    }
}
