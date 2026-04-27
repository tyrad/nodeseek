//
//  NodeSeekResult.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation

enum ChallengeKind: Equatable, Sendable {
    case loginRequired(URL)
    case cloudflare(URL)
    case blocked(URL)
    case unsupported(URL)
}

extension ChallengeKind {
    var logDescription: String {
        switch self {
        case .loginRequired(let url):
            return "loginRequired(\(url.absoluteString))"
        case .cloudflare(let url):
            return "cloudflare(\(url.absoluteString))"
        case .blocked(let url):
            return "blocked(\(url.absoluteString))"
        case .unsupported(let url):
            return "unsupported(\(url.absoluteString))"
        }
    }
}

enum NodeSeekResult<Value: Sendable>: Sendable {
    case value(Value)
    case challenge(ChallengeKind)
}
