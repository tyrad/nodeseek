//
//  PostDetailAuthorFilter.swift
//  nodeseek
//
//  Created by Codex on 2026/10/29.
//

import Foundation

// 详情页「只看楼主 / 只看 TA」的客户端筛选条件；NodeSeek 没有服务端按作者过滤的参数。
struct PostDetailAuthorFilter: Equatable {
    let authorName: String
    let authorProfileURL: URL?
    let isPoster: Bool

    static func poster(of header: PostDetailHeaderContent) -> PostDetailAuthorFilter {
        PostDetailAuthorFilter(
            authorName: header.authorName,
            authorProfileURL: header.authorProfileURL,
            isPoster: true
        )
    }

    static func author(of comment: Comment) -> PostDetailAuthorFilter {
        PostDetailAuthorFilter(
            authorName: comment.authorName,
            authorProfileURL: comment.authorProfileURL,
            isPoster: comment.isPoster
        )
    }

    var bannerText: String {
        isPoster ? "只看楼主的回复" : "只看 \(authorName) 的回复"
    }

    func matches(_ comment: Comment) -> Bool {
        if isPoster, comment.isPoster {
            return true
        }
        // 主页链接带用户 ID，比用户名更稳定；任一方缺链接时才退回用户名。
        if let authorProfileURL, let commentProfileURL = comment.authorProfileURL {
            return authorProfileURL.absoluteString == commentProfileURL.absoluteString
        }
        return comment.authorName == authorName
    }
}
