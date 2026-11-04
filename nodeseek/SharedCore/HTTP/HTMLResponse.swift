//
//  HTMLResponse.swift
//  nodeseek
//
//  Created by Codex on 2026/5/21.
//

import Foundation

nonisolated struct HTMLResponse: Sendable {
    let statusCode: Int
    let headers: [String: String]
    let finalURL: URL
    let html: String
    private let challengeCache = ResponseChallengeCache()

    init(statusCode: Int, headers: [String: String], finalURL: URL, html: String) {
        self.statusCode = statusCode
        self.headers = headers
        self.finalURL = finalURL
        self.html = html
    }

    func cachedChallenge(compute: () -> ChallengeKind?) -> ChallengeKind? {
        challengeCache.value(compute: compute)
    }
}

// 响应内容不可变，副本可共享检测结果；跨线程访问时也只计算一次。
private nonisolated final class ResponseChallengeCache: @unchecked Sendable {
    private let lock = NSLock()
    private var didCompute = false
    private var result: ChallengeKind?

    func value(compute: () -> ChallengeKind?) -> ChallengeKind? {
        lock.lock()
        defer { lock.unlock() }
        if !didCompute {
            result = compute()
            didCompute = true
        }
        return result
    }
}
