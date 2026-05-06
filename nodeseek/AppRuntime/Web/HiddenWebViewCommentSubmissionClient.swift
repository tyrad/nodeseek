//
//  HiddenWebViewCommentSubmissionClient.swift
//  nodeseek
//

import Foundation

struct HiddenWebViewCommentSubmissionClient {
    private let timeoutInterval: TimeInterval

    init(timeoutInterval: TimeInterval = 20) {
        self.timeoutInterval = timeoutInterval
    }

    func submitComment(postID: Int, content: String, referer: URL) async throws -> CommentAutomationResponse {
        try await withSharedHiddenWebViewLoader(
            logMessage: "准备通过隐藏 WebView 模拟评论提交: postID=\(postID), referer=\(referer.absoluteString)"
        ) { loader in
            try await loader.submitComment(
                pageURL: referer,
                content: content,
                timeoutInterval: timeoutInterval
            )
        }
    }
}

struct HiddenWebViewPostCollectionClient {
    private let timeoutInterval: TimeInterval

    init(timeoutInterval: TimeInterval = 20) {
        self.timeoutInterval = timeoutInterval
    }

    func submitCollection(postID: Int, action: String, referer: URL) async throws -> PostCollectionAutomationResponse {
        try await withSharedHiddenWebViewLoader(
            logMessage: "准备通过隐藏 WebView 提交收藏动作: postID=\(postID), action=\(action), referer=\(referer.absoluteString)"
        ) { loader in
            try await loader.submitCollection(
                pageURL: referer,
                postID: postID,
                action: action,
                timeoutInterval: timeoutInterval
            )
        }
    }
}

struct HiddenWebViewCommentUpvoteClient {
    private let timeoutInterval: TimeInterval

    init(timeoutInterval: TimeInterval = 20) {
        self.timeoutInterval = timeoutInterval
    }

    func submitUpvote(commentID: Int, action: String, referer: URL) async throws -> CommentUpvoteAutomationResponse {
        try await withSharedHiddenWebViewLoader(
            logMessage: "准备通过隐藏 WebView 提交评论点赞: commentID=\(commentID), action=\(action), referer=\(referer.absoluteString)"
        ) { loader in
            try await loader.submitCommentUpvote(
                pageURL: referer,
                commentID: commentID,
                action: action,
                timeoutInterval: timeoutInterval
            )
        }
    }
}

struct HiddenWebViewPostUpvoteClient {
    private let timeoutInterval: TimeInterval

    init(timeoutInterval: TimeInterval = 20) {
        self.timeoutInterval = timeoutInterval
    }

    func submitUpvote(postID: Int, action: String, referer: URL) async throws -> PostUpvoteAutomationResponse {
        try await withSharedHiddenWebViewLoader(
            logMessage: "准备通过隐藏 WebView 提交帖子点赞: postID=\(postID), action=\(action), referer=\(referer.absoluteString)"
        ) { loader in
            try await loader.submitPostUpvote(
                pageURL: referer,
                postID: postID,
                action: action,
                timeoutInterval: timeoutInterval
            )
        }
    }
}

struct HiddenWebViewCommentDislikeClient {
    private let timeoutInterval: TimeInterval

    init(timeoutInterval: TimeInterval = 20) {
        self.timeoutInterval = timeoutInterval
    }

    func submitDislike(commentID: Int, action: String, referer: URL) async throws -> CommentDislikeAutomationResponse {
        try await withSharedHiddenWebViewLoader(
            logMessage: "准备通过隐藏 WebView 提交评论反对: commentID=\(commentID), action=\(action), referer=\(referer.absoluteString)"
        ) { loader in
            try await loader.submitCommentDislike(
                pageURL: referer,
                commentID: commentID,
                action: action,
                timeoutInterval: timeoutInterval
            )
        }
    }
}

struct HiddenWebViewPostDislikeClient {
    private let timeoutInterval: TimeInterval

    init(timeoutInterval: TimeInterval = 20) {
        self.timeoutInterval = timeoutInterval
    }

    func submitDislike(postID: Int, action: String, referer: URL) async throws -> PostDislikeAutomationResponse {
        try await withSharedHiddenWebViewLoader(
            logMessage: "准备通过隐藏 WebView 提交帖子反对: postID=\(postID), action=\(action), referer=\(referer.absoluteString)"
        ) { loader in
            try await loader.submitPostDislike(
                pageURL: referer,
                postID: postID,
                action: action,
                timeoutInterval: timeoutInterval
            )
        }
    }
}

private func withSharedHiddenWebViewLoader<T>(
    logMessage: String,
    operation: @MainActor (HiddenWebViewLoader) async throws -> T
) async throws -> T {
    let requestLock = HiddenWebViewRequestLock.shared
    try await requestLock.acquire()
    do {
        try Task.checkCancellation()
        AppLog.info(.webView, logMessage)
        let loader = await MainActor.run {
            HiddenWebViewLoader.shared
        }
        let result = try await operation(loader)
        await requestLock.release()
        return result
    } catch {
        await requestLock.release()
        throw error
    }
}
