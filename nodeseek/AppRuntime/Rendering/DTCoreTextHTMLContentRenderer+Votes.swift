import Foundation

extension DTCoreTextHTMLContentRenderer {
    func renderVoteParts(_ parts: [NodeSeekVoteParser.Part], baseURL: URL, maxImageWidth: CGFloat) -> [RenderedContentBlock] {
        parts.flatMap { part -> [RenderedContentBlock] in
            switch part {
            case .html(let html):
                return renderContentBlocks(fragment: html, baseURL: baseURL, maxImageWidth: maxImageWidth)
            case .vote(let id):
                return [.vote(id)]
            case .quote(let children):
                return [.quote(.init(children: renderVoteParts(children, baseURL: baseURL, maxImageWidth: maxImageWidth)))]
            }
        }
    }
}
