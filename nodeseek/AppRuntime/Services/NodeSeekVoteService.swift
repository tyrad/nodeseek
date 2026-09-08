import Foundation

@MainActor
protocol NodeSeekVoteServing: AnyObject {
    func load(id: Int) async throws -> NodeSeekVote
    func submit(id: Int, ids: Set<Int>) async throws
}

struct NodeSeekVoteError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

extension Notification.Name {
    static let nodeSeekVoteDidChange = Notification.Name("nodeSeekVoteDidChange")
}

@MainActor
final class NodeSeekVoteService: NodeSeekVoteServing {
    static let shared = NodeSeekVoteService(client: NodeSeekVoteAPIClient())

    private struct Read {
        let token = UUID()
        let revision: Int
        let task: Task<NodeSeekVote, Error>
    }

    private let client: NodeSeekVoteServing
    private var reads: [Int: Read] = [:]
    private var revisions: [Int: Int] = [:]
    private var submissions: [Int: Task<Void, Error>] = [:]
    private var sessionGeneration = 0

    init(client: NodeSeekVoteServing) {
        self.client = client
        NotificationCenter.default.addObserver(self, selector: #selector(sessionChanged), name: .nodeSeekLoginSessionDidClose, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        reads.values.forEach { $0.task.cancel() }
        submissions.values.forEach { $0.cancel() }
    }

    @objc private func sessionChanged() {
        sessionGeneration += 1
        reads.values.forEach { $0.task.cancel() }
        submissions.values.forEach { $0.cancel() }
        reads.removeAll()
        submissions.removeAll()
        revisions.removeAll()
    }

    func load(id: Int) async throws -> NodeSeekVote {
        let generation = sessionGeneration
        while true {
            try Task.checkCancellation()
            guard generation == sessionGeneration else { throw CancellationError() }
            let read: Read
            if let existing = reads[id] {
                read = existing
            } else {
                let task = Task { [client] in
                    try Task.checkCancellation()
                    return try await client.load(id: id)
                }
                read = Read(revision: revisions[id, default: 0], task: task)
                reads[id] = read
            }
            let result = await read.task.result
            if reads[id]?.token == read.token { reads[id] = nil }
            try Task.checkCancellation()
            guard generation == sessionGeneration else { throw CancellationError() }
            // 提交期间发出的旧读取（包括失败）不能覆盖提交后的状态。
            if read.revision != revisions[id, default: 0] { continue }
            return try result.get()
        }
    }

    func submit(id: Int, ids: Set<Int>) async throws {
        try Task.checkCancellation()
        guard submissions[id] == nil else { throw NodeSeekVoteError(message: "正在提交该投票，请稍候。") }
        let generation = sessionGeneration
        let task = Task { [client] in
            try Task.checkCancellation()
            try await client.submit(id: id, ids: ids)
        }
        submissions[id] = task
        let result = await task.result
        guard generation == sessionGeneration else { throw CancellationError() }
        submissions[id] = nil
        revisions[id, default: 0] += 1
        reads.removeValue(forKey: id)?.task.cancel()
        NotificationCenter.default.post(name: .nodeSeekVoteDidChange, object: self, userInfo: ["voteID": id])
        try result.get()
    }
}
