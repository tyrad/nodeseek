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
    case tabs(titles: [String], pages: [[DetailLayoutBlock]])
    case widget(DetailDocument.Block)
}

nonisolated enum DetailFloorLayout {
    case native([DetailLayoutBlock])
    case webpage([RenderedContentBlock])
}

nonisolated struct DetailFloorRenderer: Sendable {
    typealias Delivery = @MainActor @Sendable (DetailFloorRequest, sending DetailFloorLayout) -> Void
    enum Step: Sendable { case parse, layout }
    var onStep: (@Sendable (Step, DetailFloorRequest) -> Void)?

    @MainActor
    func start(_ request: DetailFloorRequest, deliver: @escaping Delivery) -> Task<Void, Never> {
        Task.detached(priority: .userInitiated) {
            onStep?(.parse, request)
            let parsed = DetailMarkdownParser(baseURL: request.baseURL).render(request.source)
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

    private func layout(_ blocks: [DetailDocument.Block], appearance: DetailTextAppearance, width: CGFloat) throws -> [DetailLayoutBlock] {
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
                paragraphs.append(.init(runs: runs, pointSize: appearance.pointSize))
            case .heading(let level, let runs):
                paragraphs.append(.init(runs: runs.map { run in
                    if case let .text(text, style, link) = run { return .text(text, style.union(.bold), link) }
                    return run
                }, pointSize: appearance.pointSize * (1 + CGFloat(7-level) * 0.07)))
            case .quote(let nested):
                try flush()
                result.append(.quote(try layout(nested, appearance: appearance, width: max(1, width-12))))
            case .list(let start, let items):
                for (index, item) in items.enumerated() {
                    let prefix = DetailDocument.Inline.text(start.map { "\($0 + index). " } ?? "• ", [], nil)
                    if case .paragraph(let text) = item.first {
                        paragraphs.append(.init(runs: [prefix] + text, pointSize: appearance.pointSize))
                        if item.count == 1 { continue }
                        try flush()
                        result += try layout(Array(item.dropFirst()), appearance: appearance, width: width)
                    } else {
                        paragraphs.append(.init(runs: [prefix], pointSize: appearance.pointSize))
                        try flush()
                        result += try layout(item, appearance: appearance, width: width)
                    }
                }
            case .tabs(let tabs):
                try flush()
                result.append(.tabs(titles: tabs.map(\.title), pages: try tabs.map { try layout($0.blocks, appearance: appearance, width: width) }))
            default:
                try flush()
                result.append(.widget(block))
            }
        }
        try flush()
        return result
    }
}
