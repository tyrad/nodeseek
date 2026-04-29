//
//  AccountEntity.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation

struct AccountRequest {
    let refresh: Bool
}

struct AccountResponse: Equatable, Sendable {
    let displayName: String
    let isLoggedIn: Bool
    let avatarURL: URL?
    let profileURL: URL?
    let stats: [String]

    init(
        displayName: String,
        isLoggedIn: Bool,
        avatarURL: URL? = nil,
        profileURL: URL? = nil,
        stats: [String] = []
    ) {
        self.displayName = displayName
        self.isLoggedIn = isLoggedIn
        self.avatarURL = avatarURL
        self.profileURL = profileURL
        self.stats = stats
    }
}
