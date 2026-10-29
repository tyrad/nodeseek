//
//  EditableDiscussion.swift
//  nodeseek
//

import Foundation

/// 已发帖子的原文，从帖子页 `__config__.postData` 读出，作为编辑的起点和“有没有改动”的基准。
nonisolated struct EditableDiscussion: Equatable, Sendable {
    let postID: Int
    let title: String
    let content: String
    /// 板块发布后不能改，只用来展示；站点新增板块时可能为 nil。
    let category: DiscussionCategory?
    let rank: DiscussionReadRank
    /// 当前用户等级，决定“谁可以看”的可选项。
    let userLevel: Int

    var draft: NewDiscussionDraft {
        NewDiscussionDraft(title: title, content: content, category: category, rank: rank)
    }

    /// 只比较能改的三项：标题、正文、阅读限制。
    func isModified(by draft: NewDiscussionDraft) -> Bool {
        draft.title != title || draft.content != content || draft.rank != rank
    }

    /// 原来不是私有、改成私有时站点收手续费，和网页同一条规则。
    func requiresPrivateFee(for rank: DiscussionReadRank) -> Bool {
        rank == .onlyMe && self.rank != .onlyMe
    }

    static let privateFee = 10
}

extension NewDiscussionDraft {
    /// 编辑只校验标题和正文，板块不随请求提交。
    func validatedEditSubmission(postID: Int) throws -> EditDiscussionSubmission {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw NewDiscussionValidationError.titleEmpty }
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NewDiscussionValidationError.contentEmpty
        }
        return EditDiscussionSubmission(postID: postID, title: trimmedTitle, content: content, rank: rank)
    }
}

/// `POST /api/content/edit-discussion` 的请求体，字段与网页前端一致。
nonisolated struct EditDiscussionSubmission: Equatable, Sendable {
    static let mode = "edit-discussion"

    let postID: Int
    let title: String
    let content: String
    let rank: DiscussionReadRank

    var jsonObject: [String: Any] {
        [
            "content": content,
            "mode": Self.mode,
            "title": title,
            "postId": postID,
            "rank": rank.rawValue
        ]
    }

    func jsonData() throws -> Data {
        try JSONSerialization.data(withJSONObject: jsonObject, options: [.sortedKeys])
    }
}

/// 自己发的评论原文，从评论所在页 `__config__.postData.comments` 读出。只能改正文。
nonisolated struct EditableComment: Equatable, Sendable {
    let postID: Int
    let commentID: Int
    /// 楼层号，用来显示 `#1` 和刷新评论所在页。
    let floorIndex: Int
    let content: String

    var draft: NewDiscussionDraft {
        NewDiscussionDraft(content: content)
    }

    /// 评论所在页，和网页一样每页 10 楼，主楼在第一页。
    static func page(forFloor floor: Int) -> Int {
        floor <= 0 ? 1 : (floor - 1) / 10 + 1
    }
}

/// `POST /api/content/edit-comment` 的请求体，字段与网页前端一致。
nonisolated struct EditCommentSubmission: Equatable, Sendable {
    static let mode = "edit-comment"

    let commentID: Int
    let content: String

    init(commentID: Int, content: String) throws {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NewDiscussionValidationError.contentEmpty
        }
        self.commentID = commentID
        self.content = content
    }

    var jsonObject: [String: Any] {
        [
            "content": content,
            "mode": Self.mode,
            "commentId": commentID
        ]
    }

    func jsonData() throws -> Data {
        try JSONSerialization.data(withJSONObject: jsonObject, options: [.sortedKeys])
    }
}
