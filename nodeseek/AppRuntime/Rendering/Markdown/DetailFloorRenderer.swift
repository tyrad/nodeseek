import UIKit

nonisolated struct DetailFloorRequest: Equatable, Sendable {
    let id: String
    let version: Int
    let source: DetailFloorSource
    let appearance: DetailTextAppearance
    let baseURL: URL
}

nonisolated indirect enum DetailLayoutBlock: Sendable {
    case text(DetailTextSnapshot)
    case quote([DetailLayoutBlock])
    case tabs(sections: [DetailDocument.Tab], firstPage: [DetailLayoutBlock])
    case widget(DetailDocument.Block)
}

nonisolated enum DetailFloorLayout {
    case native([DetailLayoutBlock])
    case webpage([RenderedContentBlock])
}

nonisolated struct DetailFloorRenderer: Sendable {
    typealias Delivery = @MainActor @Sendable (DetailFloorRequest, sending DetailFloorLayout) -> Void
    enum Step: Sendable { case parse, layout }
    var mediaURLs: [URL: URL] = [:]
    var onStep: (@Sendable (Step, DetailFloorRequest) -> Void)?

    @MainActor
    func start(_ request: DetailFloorRequest, deliver: @escaping Delivery) -> Task<Void, Never> {
        Task.detached(priority: .userInitiated) {
            onStep?(.parse, request)
            let parsed = DetailMarkdownParser(baseURL: request.baseURL, mediaURLs: mediaURLs).render(request.source)
            guard !Task.isCancelled else { return }
            let result: DetailFloorLayout
            switch parsed {
            case .webpage(let html):
                onStep?(.layout, request)
                result = .webpage(DTCoreTextHTMLContentRenderer().render(fragment: html, baseURL: request.baseURL, maxImageWidth: request.appearance.width))
            case .native(let document):
                onStep?(.layout, request)
                guard let blocks = try? layout(document.blocks, appearance: request.appearance, width: request.appearance.width) else { return }
                result = .native(blocks)
            }
            guard !Task.isCancelled else { return }
            await deliver(request, result)
        }
    }

    /// 签名只有 HTML：能转成原生块就用 TextKit 排版（appearance.pointSize 为签名字号），否则退回网页渲染。
    @MainActor
    func startSignature(_ request: DetailFloorRequest, deliver: @escaping Delivery) -> Task<Void, Never> {
        Task.detached(priority: .userInitiated) {
            onStep?(.parse, request)
            let blocks = DetailSignatureDocument.blocks(html: request.source.html, baseURL: request.baseURL)
            guard !Task.isCancelled else { return }
            onStep?(.layout, request)
            let result: DetailFloorLayout
            if let blocks, let laid = try? layout(blocks, appearance: request.appearance, width: request.appearance.width, signature: true) {
                result = .native(laid)
            } else {
                result = .webpage(DTCoreTextHTMLContentRenderer().render(fragment: request.source.html, baseURL: request.baseURL,
                                                                          maxImageWidth: request.appearance.width))
            }
            guard !Task.isCancelled else { return }
            await deliver(request, result)
        }
    }

    @MainActor
    func startTab(_ section: DetailDocument.Tab, appearance: DetailTextAppearance, width: CGFloat,
                  deliver: @escaping @MainActor @Sendable ([DetailLayoutBlock]) -> Void) -> Task<Void, Never> {
        Task.detached(priority: .userInitiated) {
            guard let blocks = try? layout(section.blocks, appearance: appearance, width: width),
                  !Task.isCancelled else { return }
            await deliver(blocks)
        }
    }

    private func layout(_ blocks: [DetailDocument.Block], appearance: DetailTextAppearance, width: CGFloat,
                        inQuote: Bool = false, signature: Bool = false, listLevel: Int = 0) throws -> [DetailLayoutBlock] {
        var result: [DetailLayoutBlock] = []
        var paragraphs: [DetailTextSegment] = []
        func flush() throws {
            guard !paragraphs.isEmpty else { return }
            let text = try DetailTextTypesetter.layout(paragraphs, appearance: appearance, width: width)
            result.append(.text(text))
            paragraphs.removeAll(keepingCapacity: true)
        }
        for block in blocks {
            try Task.checkCancellation()
            switch block {
            case .paragraph(let runs):
                paragraphs.append(.init(runs: runs, pointSize: appearance.pointSize, isSignature: signature))
                // 网页保留报告链接，详情页另在链接下展示可预览的报告图。
                if runs.count == 1, case let .text(label, _, url?) = runs[0],
                   label == url.absoluteString, DetailImageURLRules.isCheckPlaceReportSVG(url) {
                    try flush()
                    result.append(.widget(.image(alt: "", url: url)))
                }
            case .heading(let level, let runs):
                paragraphs.append(.init(runs: runs.map { run in
                    if case let .text(text, style, link) = run { return .text(text, style.union(.bold), link) }
                    return run
                }, pointSize: appearance.pointSize + CGFloat([7, 5, 3, 2, 1, 0][max(0, min(5, level - 1))]),
                   isHeading: true, isAccentHeading: level == 2 && !inQuote))
            case .quote(let nested):
                try flush()
                result.append(.quote(try layout(nested, appearance: appearance, width: DetailQuoteLayout.contentWidth(width), inQuote: true)))
            case .list(let start, let items):
                // 与网页默认列表样式一致：一级实心圆点，二级空心圆点，更深用方块。
                let level = listLevel + 1
                let bullet = level == 1 ? "• " : level == 2 ? "◦ " : "▪ "
                for (index, item) in items.enumerated() {
                    let prefix = DetailDocument.Inline.text(start.map { "\($0 + index). " } ?? bullet, [], nil)
                    if case .paragraph(let text) = item.first {
                        paragraphs.append(.init(runs: [prefix] + text, pointSize: appearance.pointSize, isListItem: true, inQuote: inQuote, listLevel: level))
                        if item.count == 1 { continue }
                        try flush()
                        result += try layout(Array(item.dropFirst()), appearance: appearance, width: width, inQuote: inQuote, listLevel: level)
                    } else {
                        paragraphs.append(.init(runs: [prefix], pointSize: appearance.pointSize, isListItem: true, inQuote: inQuote, listLevel: level))
                        try flush()
                        result += try layout(item, appearance: appearance, width: width, inQuote: inQuote, listLevel: level)
                    }
                }
                // 旧版列表末项与后文间距和段落相同。
                if let last = paragraphs.indices.last, paragraphs[last].isListItem { paragraphs[last].endsList = true }
            case .tabs(let tabs):
                try flush()
                if let first = tabs.first {
                    let visible = try layout(first.blocks, appearance: appearance, width: width)
                    result.append(.tabs(sections: tabs, firstPage: visible))
                }
            default:
                try flush()
                result.append(.widget(block))
            }
        }
        try flush()
        return result
    }
}
