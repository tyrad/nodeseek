//
//  AccountVaultModels.swift
//  nodeseek
//

import Foundation

nonisolated enum AccountCredentialState: String, Codable, Equatable, Sendable {
    case valid
    case expired
}

nonisolated struct SavedAccount: Codable, Equatable, Sendable {
    let uid: Int
    var displayName: String
    var avatarURL: URL?
    var profileURL: URL
    var stats: [String]
    var lastUsedAt: Date
    var credentialState: AccountCredentialState

    init(
        uid: Int,
        displayName: String,
        avatarURL: URL? = nil,
        profileURL: URL,
        stats: [String] = [],
        lastUsedAt: Date = Date(),
        credentialState: AccountCredentialState = .valid
    ) {
        self.uid = uid
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.profileURL = profileURL
        self.stats = stats
        self.lastUsedAt = lastUsedAt
        self.credentialState = credentialState
    }

    init?(
        account: AccountResponse,
        lastUsedAt: Date = Date(),
        credentialState: AccountCredentialState = .valid
    ) {
        guard account.isLoggedIn,
              let profileURL = account.profileURL,
              let uid = account.nodeSeekUID,
              uid > 0 else {
            return nil
        }
        self.init(
            uid: uid,
            displayName: account.displayName,
            avatarURL: account.avatarURL,
            profileURL: profileURL,
            stats: account.stats,
            lastUsedAt: lastUsedAt,
            credentialState: credentialState
        )
    }

    func toAccountResponse() -> AccountResponse {
        AccountResponse(
            displayName: displayName,
            isLoggedIn: true,
            avatarURL: avatarURL,
            profileURL: profileURL,
            stats: stats
        )
    }
}
