//
//  PostDetailTestTarget.swift
//  nodeseek
//
//  Created by Codex on 2026/4/30.
//

import Foundation

#if DEBUG
struct PostDetailTestTarget: Equatable {
    let post: PostSummary
    let page: Int
    let anchorID: String?

    init?(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false,
              let url = URL(string: trimmed, relativeTo: NodeSeekSite.baseURL)?.absoluteURL,
              NodeSeekSite.isNodeSeekHost(url),
              let route = NodeSeekPostRouteResolver.route(for: url, baseURL: NodeSeekSite.baseURL) else {
            return nil
        }

        self.page = route.page
        self.anchorID = route.anchorID
        self.post = PostSummary(
            id: route.postID,
            title: "详情测试 #\(route.postID)",
            url: url,
            authorName: "详情测试",
            nodeName: nil,
            replyCount: 0,
            lastActivityText: nil
        )
    }

}

struct PostDetailDebugLink: Equatable {
    let title: String
    let url: URL

    var target: PostDetailTestTarget? {
        PostDetailTestTarget(rawValue: url.absoluteString)
    }

    static let allCases: [PostDetailDebugLink] = [
        PostDetailDebugLink(
            title: "qute嵌套",
            url: URL(string: "https://www.nodeseek.com/post-720543-1")!
        ),
        PostDetailDebugLink(
            title: "svg兼容问题",
            url: URL(string: "https://www.nodeseek.com/post-720369-1")!
        )
    ]
}
#endif
