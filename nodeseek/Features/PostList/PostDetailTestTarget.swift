//
//  PostDetailTestTarget.swift
//  nodeseek
//
//  Created by Codex on 2026/4/30.
//

import Foundation

#if DEBUG
struct PostDetailTestTarget: Equatable {
    private static let baseURL = URL(string: "https://www.nodeseek.com")!
    private static let postPathRegex = try! NSRegularExpression(
        pattern: "^/post-([0-9]+)(?:-([0-9]+))?/?$",
        options: []
    )

    let post: PostSummary
    let page: Int

    init?(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false,
              let url = URL(string: trimmed, relativeTo: Self.baseURL)?.absoluteURL,
              Self.isNodeSeekHost(url),
              let match = Self.postMatch(in: url.path) else {
            return nil
        }

        let normalizedPage = max(match.page, 1)
        self.page = normalizedPage
        self.post = PostSummary(
            id: match.postID,
            title: "详情测试 #\(match.postID)",
            url: url,
            authorName: "详情测试",
            nodeName: nil,
            replyCount: 0,
            lastActivityText: nil
        )
    }

    private static func postMatch(in path: String) -> (postID: String, page: Int)? {
        let range = NSRange(path.startIndex..<path.endIndex, in: path)
        guard let match = postPathRegex.firstMatch(in: path, options: [], range: range),
              match.numberOfRanges >= 3,
              let postIDRange = Range(match.range(at: 1), in: path) else {
            return nil
        }

        let page: Int
        if match.range(at: 2).location != NSNotFound,
           let pageRange = Range(match.range(at: 2), in: path) {
            page = Int(path[pageRange]) ?? 1
        } else {
            page = 1
        }

        return (
            postID: String(path[postIDRange]),
            page: page
        )
    }

    private static func isNodeSeekHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "nodeseek.com" || host.hasSuffix(".nodeseek.com")
    }
}
#endif
