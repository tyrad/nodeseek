import XCTest
@testable import nodeseek

@MainActor
final class NodeSeekVoteServiceTests: XCTestCase {
    func testConcurrentReadsAreSharedButCompletedResultsAreNotCached() async throws {
        let client = VoteControlledClient()
        var completion: CheckedContinuation<NodeSeekVote, Error>?
        client.onLoad = { _ in try await withCheckedThrowingContinuation { completion = $0 } }
        let service = NodeSeekVoteService(client: client)
        let first = Task { try await service.load(id: 3108) }
        let second = Task { try await service.load(id: 3108) }
        await waitUntil { completion != nil }
        completion?.resume(returning: VoteTestService.makeVote())
        _ = try await first.value
        _ = try await second.value
        XCTAssertEqual(client.loadCount, 1)
        client.onLoad = { _ in VoteTestService.makeVote() }
        _ = try await service.load(id: 3108)
        XCTAssertEqual(client.loadCount, 2)
    }

    func testSubmissionInvalidatesEarlierReadIncludingItsError() async throws {
        for fails in [false, true] {
            let client = VoteControlledClient()
            var completion: CheckedContinuation<NodeSeekVote, Error>?
            client.onLoad = { _ in try await withCheckedThrowingContinuation { completion = $0 } }
            let service = NodeSeekVoteService(client: client)
            let read = Task { try await service.load(id: 3108) }
            await waitUntil { completion != nil }
            try await service.submit(id: 3108, ids: [14131])
            client.onLoad = { _ in VoteTestService.makeVote(voted: true) }
            if fails { completion?.resume(throwing: URLError(.timedOut)) }
            else { completion?.resume(returning: VoteTestService.makeVote()) }
            let result = try await read.value
            XCTAssertTrue(result.hasVoted)
            XCTAssertEqual(client.loadCount, 2)
        }
    }

    func testSessionChangeDiscardsOldReadEvenIfClientIgnoresCancellation() async {
        let client = VoteControlledClient()
        var completion: CheckedContinuation<NodeSeekVote, Error>?
        client.onLoad = { _ in try await withCheckedThrowingContinuation { completion = $0 } }
        let service = NodeSeekVoteService(client: client)
        let read = Task { try await service.load(id: 3108) }
        await waitUntil { completion != nil }
        NotificationCenter.default.post(name: .nodeSeekLoginSessionDidClose, object: nil)
        completion?.resume(returning: VoteTestService.makeVote())
        do { _ = try await read.value; XCTFail("旧会话结果必须丢弃") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testSessionChangeCancelsQueuedSubmitAndAllowsNewSessionSubmission() async throws {
        let client = VoteControlledClient()
        var completion: CheckedContinuation<Void, Never>?
        var oldTaskWasCancelled = false
        client.onSubmit = { _, _ in
            await withCheckedContinuation { completion = $0 }
            oldTaskWasCancelled = Task.isCancelled
        }
        let service = NodeSeekVoteService(client: client)
        let old = Task { try await service.submit(id: 3108, ids: [14131]) }
        await waitUntil { completion != nil }
        NotificationCenter.default.post(name: .nodeSeekLoginSessionDidClose, object: nil)
        client.onSubmit = { _, _ in }
        try await service.submit(id: 3108, ids: [14131])
        completion?.resume()
        do { try await old.value; XCTFail("旧会话提交不能报告成功") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(oldTaskWasCancelled)
        XCTAssertEqual(client.submitCount, 2)
    }

    func testConcurrentSubmitIsRejectedWithoutDuplicatingWrite() async throws {
        let client = VoteControlledClient()
        var completion: CheckedContinuation<Void, Never>?
        client.onSubmit = { _, _ in await withCheckedContinuation { completion = $0 } }
        let service = NodeSeekVoteService(client: client)
        let first = Task { try await service.submit(id: 3108, ids: [14131]) }
        await waitUntil { completion != nil }
        do { try await service.submit(id: 3108, ids: [14131]); XCTFail("同一投票不应并发写入") }
        catch { XCTAssertEqual(error.localizedDescription, "正在提交该投票，请稍候。") }
        completion?.resume()
        try await first.value
        XCTAssertEqual(client.submitCount, 1)
    }

    private func waitUntil(_ predicate: () -> Bool) async {
        for _ in 0..<100 {
            if predicate() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("等待受控请求超时")
    }
}

@MainActor
private final class VoteControlledClient: NodeSeekVoteServing {
    var loadCount = 0
    var submitCount = 0
    var onLoad: (Int) async throws -> NodeSeekVote = { _ in VoteTestService.makeVote() }
    var onSubmit: (Int, Set<Int>) async throws -> Void = { _, _ in }

    func load(id: Int) async throws -> NodeSeekVote {
        loadCount += 1
        return try await onLoad(id)
    }
    func submit(id: Int, ids: Set<Int>) async throws {
        submitCount += 1
        try await onSubmit(id, ids)
    }
}
