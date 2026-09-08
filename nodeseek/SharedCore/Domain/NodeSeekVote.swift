import Foundation

nonisolated struct NodeSeekVote: Decodable, Equatable, Sendable {
    struct Item: Decodable, Equatable, Sendable {
        let vote_item_id: Int
        let text: String
        let voted: Bool
        let count: Int?
    }

    let id: Int
    let title: String
    let multiple: Bool
    let isPublic: Bool
    let locked: Bool
    let items: [Item]

    var hasVoted: Bool { items.contains(where: \.voted) }
    var selectedIDs: Set<Int> { Set(items.filter(\.voted).map(\.vote_item_id)) }
    var canSubmit: Bool { !locked && !hasVoted && !items.isEmpty }

    func accepts(_ ids: Set<Int>) -> Bool {
        canSubmit && !ids.isEmpty && (multiple || ids.count == 1)
            && ids.isSubset(of: Set(items.map(\.vote_item_id)))
    }
}

nonisolated struct NodeSeekVoteResponse: Decodable, Sendable {
    let success: Bool
    let message: String?
    let vote: NodeSeekVote?
}
