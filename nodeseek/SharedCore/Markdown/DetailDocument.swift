import Foundation

nonisolated struct DetailDocument: Equatable, Sendable {
    nonisolated struct Style: OptionSet, Sendable {
        let rawValue: Int
        static let bold = Self(rawValue: 1)
        static let italic = Self(rawValue: 2)
        static let strike = Self(rawValue: 4)
        static let code = Self(rawValue: 8)
    }

    nonisolated enum Inline: Equatable, Sendable {
        case text(String, Style, URL?)
        case sticker(token: String, url: URL)
    }

    nonisolated struct Tab: Equatable, Sendable {
        let title: String
        let blocks: [Block]
    }

    nonisolated indirect enum Block: Equatable, Sendable {
        case paragraph([Inline])
        case heading(Int, [Inline])
        case quote([Block])
        case list(start: Int?, items: [[Block]])
        case table(rows: [[[Inline]]])
        case code(language: String?, text: String)
        case terminal(String)
        case image(alt: String, url: URL)
        /// 地址无效的图片，按加载失败占位显示。
        case brokenImage(alt: String)
        case vote(Int)
        case tabs([Tab])
        case divider
    }

    let blocks: [Block]
}

nonisolated struct DetailFloorSource: Equatable, Sendable {
    let html: String
    let visibleMarkdown: String?

    init(post: PostDetail) {
        html = post.contentHTML
        visibleMarkdown = post.isRestricted ? nil : post.visibleMarkdown
    }

    init(comment: Comment) {
        html = comment.contentHTML
        visibleMarkdown = comment.hasVisibleMarkdown ? comment.markdown : nil
    }

    init(html: String, visibleMarkdown: String?) {
        self.html = html
        self.visibleMarkdown = visibleMarkdown
    }
}

nonisolated enum DetailDocumentResult: Equatable, Sendable {
    case native(DetailDocument)
    case webpage(html: String)
}
