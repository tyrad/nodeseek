//
//  NodeSeekSearchNoticeParser.swift
//  nodeseek
//

import Foundation
import Kanna

/// 搜索结果页一页的内容：帖子列表，以及没有帖子时站点给出的提示。
nonisolated struct NodeSeekSearchPage: Sendable, Equatable {
    let posts: [PostSummary]
    /// 例如「搜索词太短😭」「搜索词含有违规字符😭」「未找到有效帖子，请更换搜索词后重试」
    let notice: String?
}

/// 站点搜不到帖子时不返回错误码，而是在 #nsk-body-left 里直接渲染一句提示，这里把它取出来。
nonisolated enum NodeSeekSearchNoticeParser {
    static func notice(in html: String) -> String? {
        guard let document = try? HTML(html: html, encoding: .utf8) else { return nil }
        // 提示是正文区的直接子 div；占位块带 id，分页外层虽无 class 但里面有 nsk-pager，都排除掉
        let path = "//div[@id='nsk-body-left']/div[not(@id) and not(@class) and not(.//*[contains(@class, 'nsk-pager')])]"
        for node in document.xpath(path) {
            let text = (node.text ?? "")
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if !text.isEmpty {
                return text
            }
        }
        return nil
    }
}
