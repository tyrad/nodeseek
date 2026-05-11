//
//  UserContentRecords.swift
//  nodeseek
//
//  Created by Codex on 2026/5/11.
//

import Foundation

nonisolated struct UserDiscussionRecord: Equatable, Sendable {
    let rank: Int
    let title: String
    let postID: Int
}

nonisolated struct UserCommentRecord: Equatable, Sendable {
    let postID: Int
    let title: String
    let rank: Int
    let floorID: Int
    let text: String

    var commentPage: Int {
        max(1, (floorID + 9) / 10)
    }

    var anchorID: String {
        "\(floorID)"
    }
}

nonisolated struct UserCollectionRecord: Equatable, Sendable {
    let title: String
    let postID: Int
    let rank: Int
}

extension AccountResponse {
    nonisolated var nodeSeekUID: Int? {
        guard let profileURL else { return nil }
        return NodeSeekUserIDResolver.uid(from: profileURL)
    }
}

enum NodeSeekUserIDResolver {
    nonisolated static func uid(from url: URL) -> Int? {
        let components = url.pathComponents
        guard let spaceIndex = components.firstIndex(of: "space") else { return nil }
        let idIndex = components.index(after: spaceIndex)
        guard idIndex < components.endIndex else { return nil }
        return Int(components[idIndex])
    }
}

enum UserContentPostSummaryFactory {
    nonisolated static func postSummary(id: Int, title: String) -> PostSummary {
        let stringID = "\(id)"
        return PostSummary(
            id: stringID,
            title: title,
            url: NodeSeekSite.postURL(id: stringID, page: 1),
            authorName: "",
            nodeName: nil,
            replyCount: 0,
            lastActivityText: nil
        )
    }
}
