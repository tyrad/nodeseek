import Foundation
import Testing
@testable import nodeseek

@MainActor
struct UserStardustViewModelTests {
    @Test func transferDirectionIsNotInferredFromSignAlone() {
        #expect(record(1, type: "transfer", diff: -2).isOutgoingTransfer)
        #expect(!record(1, type: "transfer", diff: 2).isOutgoingTransfer)
        #expect(!record(1, type: "buyCode", diff: -2).isOutgoingTransfer)
        #expect(record(1, diff: 2).changeText == "+2")
        #expect(record(1, diff: -2).changeText == "-2")
        #expect(record(1, type: "futureType").typeText == "futureType")
    }

    @Test func failedPagePreservesRecordsAndRetriesSameCursor() async {
        let client = StardustStub()
        client.results = [
            .success(page([record(20)], more: true, cursor: 20)),
            .failure(URLError(.notConnectedToInternet)),
            .success(page([record(19)], more: false, cursor: 19))
        ]
        let model = UserStardustViewModel(uid: 31037, client: client)
        await model.load(refresh: true)
        await model.load(refresh: false)
        #expect(model.records.map(\.id) == [20])
        #expect(model.cursor == 20)
        #expect(model.errorMessage != nil)
        await model.load(refresh: false)
        #expect(client.cursors == [nil, 20, 20])
        #expect(model.records.map(\.id) == [20, 19])
        #expect(!model.hasMore)
        #expect(model.errorMessage == nil)
        await model.load(refresh: false)
        #expect(client.cursors.count == 3)
    }

    @Test func refreshReplacesRatherThanAppendsAndDeduplicatesPages() async {
        let client = StardustStub()
        client.results = [
            .success(page([record(20), record(19)], more: true, cursor: 19)),
            .success(page([record(19), record(18)], more: false, cursor: 18)),
            .success(page([record(21)], more: false, cursor: 21))
        ]
        let model = UserStardustViewModel(uid: 31037, client: client)
        await model.load(refresh: true)
        await model.load(refresh: false)
        #expect(model.records.map(\.id) == [20, 19, 18])
        await model.load(refresh: true)
        #expect(model.records.map(\.id) == [21])
        #expect(client.cursors == [nil, 19, nil])
    }

    @Test func malformedCursorIsAnErrorAndRetainsRetryPosition() async {
        let client = StardustStub()
        client.results = [
            .success(page([record(20)], more: true, cursor: 20)),
            .success(page([record(20)], more: true, cursor: 20))
        ]
        let model = UserStardustViewModel(uid: 31037, client: client)
        await model.load(refresh: true)
        await model.load(refresh: false)
        #expect(model.errorMessage != nil)
        #expect(model.cursor == 20)
        #expect(model.records.count == 1)
    }

    @Test func emptyListDoesNotInventAccountBalance() async {
        let client = StardustStub()
        client.results = [.success(page([], more: false, cursor: nil))]
        let model = UserStardustViewModel(uid: 31037, client: client)
        await model.load(refresh: true)
        await model.refreshProfile()
        #expect(model.hasLoaded)
        #expect(model.records.isEmpty)
        #expect(model.profile == nil)
        #expect(model.errorMessage == nil)
    }

    @Test func refreshFailureAfterLastPageKeepsDataAndRetryIntent() async {
        let client = StardustStub()
        client.results = [
            .success(page([record(20)], more: false, cursor: 20)),
            .failure(URLError(.timedOut)),
            .success(page([record(21)], more: false, cursor: 21))
        ]
        let model = UserStardustViewModel(uid: 31037, client: client)
        await model.load(refresh: true)
        await model.load(refresh: true)
        #expect(model.records.map(\.id) == [20])
        #expect(model.failedRefresh)
        #expect(!model.hasMore)
        await model.load(refresh: true)
        #expect(model.records.map(\.id) == [21])
        #expect(!model.failedRefresh)
        #expect(client.cursors == [nil, nil, nil])
    }

    @Test func oldPageCannotOverwriteNewRefresh() async {
        let client = StardustStub()
        client.results = [.success(page([record(20)], more: true, cursor: 20))]
        let model = UserStardustViewModel(uid: 31037, client: client)
        await model.load(refresh: true)
        client.suspendNext = true
        let oldTask = Task { await model.load(refresh: false) }
        while client.pending == nil { await Task.yield() }
        client.results = [.success(page([record(30)], more: false, cursor: 30))]
        await model.load(refresh: true)
        client.pending?.resume(returning: page([record(19)], more: false, cursor: 19))
        client.pending = nil
        await oldTask.value
        #expect(model.records.map(\.id) == [30])
        #expect(!model.isLoading)
    }
}

@MainActor
private final class StardustStub: UserStardustLoading {
    var cursors: [Int?] = []
    var results: [Result<UserStardustPage, Error>] = []
    var suspendNext = false
    var pending: CheckedContinuation<UserStardustPage, Error>?

    func loadStardust(uid: Int, beforeID: Int?) async throws -> UserStardustPage {
        cursors.append(beforeID)
        if suspendNext {
            suspendNext = false
            return try await withCheckedThrowingContinuation { pending = $0 }
        }
        return try results.removeFirst().get()
    }

    func loadProfile(uid: Int) async throws -> UserProfileRecord { throw URLError(.notConnectedToInternet) }
}

private func record(_ id: Int, type: String = "upvote", diff: Int = 1) -> UserStardustRecord {
    UserStardustRecord(id: id, memberID: 31037, peerID: 70992, type: type, diff: diff, result: 11, createdAt: "2026-10-28T08:33:51.000Z")
}

private func page(_ records: [UserStardustRecord], more: Bool, cursor: Int?) -> UserStardustPage {
    UserStardustPage(records: records, hasMore: more, cursor: cursor)
}
