//
//  ChallengeSession.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation

enum NodeSeekSessionState: Equatable, Sendable {
    case idle
    case challengeRequired(ChallengeKind, updatedAt: Date)
    case ready(lastSucceededAt: Date)
}

actor NodeSeekSessionStore {
    static let shared = NodeSeekSessionStore()

    private var state: NodeSeekSessionState = .idle

    func recordChallenge(_ challenge: ChallengeKind) -> String {
        state = .challengeRequired(challenge, updatedAt: Date())
        return Self.message(for: challenge)
    }

    func recordSuccess() {
        state = .ready(lastSucceededAt: Date())
    }

    func currentState() -> NodeSeekSessionState {
        state
    }

    func reset() {
        state = .idle
    }

    private static func message(for challenge: ChallengeKind) -> String {
        switch challenge {
        case .loginRequired:
            return "本帖需要注册用户才能查看😭"
        case .cloudflare:
            return "站点当前需要 Cloudflare 验证，请稍后重试。"
        case .blocked:
            return "站点当前返回了拦截页面，请稍后重试。"
        case .unsupported:
            return "站点当前返回了无法处理的验证页面，请稍后重试。"
        }
    }
}
