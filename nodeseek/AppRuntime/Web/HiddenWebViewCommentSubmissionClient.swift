//
//  HiddenWebViewCommentSubmissionClient.swift
//  nodeseek
//

import Foundation

private protocol PostActionAutomationResult {
    var ok: Bool { get }
}

extension CommentAutomationResponse: PostActionAutomationResult {}
extension PostCollectionAutomationResponse: PostActionAutomationResult {}
extension CommentUpvoteAutomationResponse: PostActionAutomationResult {}

struct WebViewPostActionPagePreparer: PostDetailActionPagePreparing {
    private let timeoutInterval: TimeInterval

    init(timeoutInterval: TimeInterval = 20) {
        self.timeoutInterval = timeoutInterval
    }

    func prepareActionPage(pageURL: URL) {
        HiddenWebViewPostActionPageScheduler.prepare(
            pageURL: pageURL,
            timeoutInterval: timeoutInterval,
            reason: "详情页打开预热"
        )
    }
}

enum HiddenWebViewPostActionPageScheduler {
    private static let requestLock = HiddenWebViewRequestLock()
    private static let channel = HiddenWebViewChannel.isolated(UUID())

    static func prepare(pageURL: URL, timeoutInterval: TimeInterval, reason: String) {
        Task {
            do {
                try await withPostActionHiddenWebViewLoader(
                    logMessage: "准备预热帖子动作隐藏 WebView: reason=\(reason), url=\(pageURL.absoluteString)"
                ) { loader in
                    try await loader.prepareAutomationPage(
                        pageURL: pageURL,
                        timeoutInterval: timeoutInterval,
                        reason: reason
                    )
                }
            } catch {
                AppLog.warning(.webView, "帖子动作隐藏 WebView 预热失败: reason=\(reason), url=\(pageURL.absoluteString), error=\(error.localizedDescription)")
            }
        }
    }

    static func refreshAfterSuccessfulAction(
        pageURL: URL,
        timeoutInterval: TimeInterval,
        actionName: String,
        succeeded: Bool
    ) {
        guard succeeded else { return }
        prepare(
            pageURL: pageURL,
            timeoutInterval: timeoutInterval,
            reason: "\(actionName)成功后刷新"
        )
    }

    fileprivate static var lockAndChannel: (HiddenWebViewRequestLock, HiddenWebViewChannel) {
        (requestLock, channel)
    }
}

enum HiddenWebViewPageActionScheduler {
    private static let requestLock = HiddenWebViewRequestLock()
    private static let channel = HiddenWebViewChannel.isolated(UUID())

    fileprivate static var lockAndChannel: (HiddenWebViewRequestLock, HiddenWebViewChannel) {
        (requestLock, channel)
    }
}

private struct HiddenWebViewPostActionSubmitter {
    let timeoutInterval: TimeInterval

    func submit<Response: PostActionAutomationResult>(
        referer: URL,
        actionName: String,
        logMessage: String,
        operation: @MainActor (HiddenWebViewLoader) async throws -> Response
    ) async throws -> Response {
        try await withPostActionHiddenWebViewLoader(logMessage: logMessage) { loader in
            let response = try await operation(loader)
            HiddenWebViewPostActionPageScheduler.refreshAfterSuccessfulAction(
                pageURL: referer,
                timeoutInterval: timeoutInterval,
                actionName: actionName,
                succeeded: response.ok
            )
            return response
        }
    }
}

struct HiddenWebViewCommentSubmissionClient {
    private let timeoutInterval: TimeInterval

    init(timeoutInterval: TimeInterval = 20) {
        self.timeoutInterval = timeoutInterval
    }

    func submitComment(postID: Int, content: String, referer: URL) async throws -> CommentAutomationResponse {
        let startedAt = Date()
        AppLog.info(.webView, "HiddenWebViewCommentSubmissionClient 收到评论提交: postID=\(postID), contentLength=\(content.count), timeout=\(Int(timeoutInterval))s")
        return try await withPostActionHiddenWebViewLoader(
            logMessage: "准备通过隐藏 WebView 模拟评论提交: postID=\(postID), referer=\(referer.absoluteString)"
        ) { loader in
            AppLog.info(.webView, "HiddenWebViewCommentSubmissionClient 已拿到 loader，开始提交: postID=\(postID), elapsedMs=\(AppLog.elapsedMilliseconds(since: startedAt))")
            let response = try await loader.submitComment(
                pageURL: referer,
                content: content,
                timeoutInterval: timeoutInterval
            )
            HiddenWebViewPostActionPageScheduler.refreshAfterSuccessfulAction(
                pageURL: referer,
                timeoutInterval: timeoutInterval,
                actionName: "评论提交",
                succeeded: response.ok
            )
            AppLog.info(.webView, "HiddenWebViewCommentSubmissionClient 提交结束: postID=\(postID), ok=\(response.ok), reason=\(response.reason), elapsedMs=\(AppLog.elapsedMilliseconds(since: startedAt))")
            return response
        }
    }
}

struct HiddenWebViewPostCollectionClient {
    private let timeoutInterval: TimeInterval
    private let actionSubmitter: HiddenWebViewPostActionSubmitter

    init(timeoutInterval: TimeInterval = 20) {
        self.timeoutInterval = timeoutInterval
        self.actionSubmitter = HiddenWebViewPostActionSubmitter(timeoutInterval: timeoutInterval)
    }

    func submitCollection(postID: Int, action: String, referer: URL) async throws -> PostCollectionAutomationResponse {
        try await actionSubmitter.submit(
            referer: referer,
            actionName: "收藏动作",
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
    private let actionSubmitter: HiddenWebViewPostActionSubmitter

    init(timeoutInterval: TimeInterval = 20) {
        self.timeoutInterval = timeoutInterval
        self.actionSubmitter = HiddenWebViewPostActionSubmitter(timeoutInterval: timeoutInterval)
    }

    func submitUpvote(commentID: Int, action: String, referer: URL) async throws -> CommentUpvoteAutomationResponse {
        try await actionSubmitter.submit(
            referer: referer,
            actionName: "评论点赞",
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
    private let actionSubmitter: HiddenWebViewPostActionSubmitter

    init(timeoutInterval: TimeInterval = 20) {
        self.timeoutInterval = timeoutInterval
        self.actionSubmitter = HiddenWebViewPostActionSubmitter(timeoutInterval: timeoutInterval)
    }

    func submitUpvote(postID: Int, action: String, referer: URL) async throws -> PostUpvoteAutomationResponse {
        try await actionSubmitter.submit(
            referer: referer,
            actionName: "帖子点赞",
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

struct HiddenWebViewCommentChickenLegClient {
    private let timeoutInterval: TimeInterval
    private let actionSubmitter: HiddenWebViewPostActionSubmitter

    init(timeoutInterval: TimeInterval = 20) {
        self.timeoutInterval = timeoutInterval
        self.actionSubmitter = HiddenWebViewPostActionSubmitter(timeoutInterval: timeoutInterval)
    }

    func submitChickenLeg(commentID: Int, action: String, referer: URL) async throws -> CommentChickenLegAutomationResponse {
        try await actionSubmitter.submit(
            referer: referer,
            actionName: "评论鸡腿",
            logMessage: "准备通过隐藏 WebView 提交评论鸡腿: commentID=\(commentID), action=\(action), referer=\(referer.absoluteString)"
        ) { loader in
            try await loader.submitCommentChickenLeg(
                pageURL: referer,
                commentID: commentID,
                action: action,
                timeoutInterval: timeoutInterval
            )
        }
    }
}

struct HiddenWebViewPostChickenLegClient {
    private let timeoutInterval: TimeInterval
    private let actionSubmitter: HiddenWebViewPostActionSubmitter

    init(timeoutInterval: TimeInterval = 20) {
        self.timeoutInterval = timeoutInterval
        self.actionSubmitter = HiddenWebViewPostActionSubmitter(timeoutInterval: timeoutInterval)
    }

    func submitChickenLeg(postID: Int, action: String, referer: URL) async throws -> PostChickenLegAutomationResponse {
        try await actionSubmitter.submit(
            referer: referer,
            actionName: "帖子鸡腿",
            logMessage: "准备通过隐藏 WebView 提交帖子鸡腿: postID=\(postID), action=\(action), referer=\(referer.absoluteString)"
        ) { loader in
            try await loader.submitPostChickenLeg(
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
    private let actionSubmitter: HiddenWebViewPostActionSubmitter

    init(timeoutInterval: TimeInterval = 20) {
        self.timeoutInterval = timeoutInterval
        self.actionSubmitter = HiddenWebViewPostActionSubmitter(timeoutInterval: timeoutInterval)
    }

    func submitDislike(commentID: Int, action: String, referer: URL) async throws -> CommentDislikeAutomationResponse {
        try await actionSubmitter.submit(
            referer: referer,
            actionName: "评论反对",
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
    private let actionSubmitter: HiddenWebViewPostActionSubmitter

    init(timeoutInterval: TimeInterval = 20) {
        self.timeoutInterval = timeoutInterval
        self.actionSubmitter = HiddenWebViewPostActionSubmitter(timeoutInterval: timeoutInterval)
    }

    func submitDislike(postID: Int, action: String, referer: URL) async throws -> PostDislikeAutomationResponse {
        try await actionSubmitter.submit(
            referer: referer,
            actionName: "帖子反对",
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

func withHiddenWebViewPageActionLoader<T>(
    logMessage: String,
    operation: @MainActor (HiddenWebViewLoader) async throws -> T
) async throws -> T {
    let startedAt = Date()
    let (requestLock, channel) = HiddenWebViewPageActionScheduler.lockAndChannel
    AppLog.info(.webView, "隐藏 WebView 页面动作请求锁等待开始")
    try await requestLock.acquire()
    AppLog.info(.webView, "隐藏 WebView 页面动作请求锁获取成功: waitMs=\(AppLog.elapsedMilliseconds(since: startedAt))")
    do {
        try Task.checkCancellation()
        AppLog.info(.webView, logMessage)
        let loader = await MainActor.run {
            HiddenWebViewLoader.loader(for: channel)
        }
        let result = try await operation(loader)
        await requestLock.release()
        AppLog.info(.webView, "隐藏 WebView 页面动作请求锁已释放: totalMs=\(AppLog.elapsedMilliseconds(since: startedAt))")
        return result
    } catch {
        await requestLock.release()
        AppLog.error(.webView, "隐藏 WebView 页面动作请求锁异常释放: error=\(error.localizedDescription), totalMs=\(AppLog.elapsedMilliseconds(since: startedAt))")
        throw error
    }
}

private func withPostActionHiddenWebViewLoader<T>(
    logMessage: String,
    operation: @MainActor (HiddenWebViewLoader) async throws -> T
) async throws -> T {
    let startedAt = Date()
    let (requestLock, channel) = HiddenWebViewPostActionPageScheduler.lockAndChannel
    AppLog.info(.webView, "帖子动作隐藏 WebView 请求锁等待开始")
    try await requestLock.acquire()
    AppLog.info(.webView, "帖子动作隐藏 WebView 请求锁获取成功: waitMs=\(AppLog.elapsedMilliseconds(since: startedAt))")
    do {
        try Task.checkCancellation()
        AppLog.info(.webView, logMessage)
        let loader = await MainActor.run {
            HiddenWebViewLoader.loader(for: channel)
        }
        let result = try await operation(loader)
        await requestLock.release()
        AppLog.info(.webView, "帖子动作隐藏 WebView 请求锁已释放: totalMs=\(AppLog.elapsedMilliseconds(since: startedAt))")
        return result
    } catch {
        await requestLock.release()
        AppLog.error(.webView, "帖子动作隐藏 WebView 请求锁异常释放: error=\(error.localizedDescription), totalMs=\(AppLog.elapsedMilliseconds(since: startedAt))")
        throw error
    }
}
